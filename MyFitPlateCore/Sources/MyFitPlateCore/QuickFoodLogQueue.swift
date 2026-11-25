import Combine
import Foundation

public struct PendingQuickFoodLog: Codable, Identifiable {
    public let id: UUID
    public let sourceFoodID: String
    public var draft: FoodLoggingDraft
    public let source: String
    public var isAccepted: Bool?
}

/// Small quick-log operations retain identity through hydration, ambiguous acceptance,
/// relaunch and cleanup failure. Independent foods can resolve without replacing each other.
@MainActor
public final class QuickFoodLogQueue: ObservableObject {
    @Published public private(set) var operations: [PendingQuickFoodLog] = []
    @Published public private(set) var savingIDs = Set<UUID>()
    @Published public private(set) var errorMessage: String?
    public let userID: String
    private let store: EditorDraftStore
    private let scope: String
    private var unreadable = false

    public init(userID: String, store: EditorDraftStore = EditorDraftStore(), scope: String = "quick-food-log-queue") {
        self.userID = userID
        self.store = store
        self.scope = scope
        do { operations = try store.load([PendingQuickFoodLog].self, userID: userID, scope: scope)?.value ?? [] } catch {
            unreadable = true; errorMessage = "Your previous quick log could not be opened. It has been kept unchanged."
        }
    }

    @discardableResult
    public func begin(food: FoodItem, date: Date, mealName: String, source: String, needsHydration: Bool,
                      dayContext: DiaryDayContext? = nil, trainingFuelTarget: TrainingFuelTarget? = nil) -> PendingQuickFoodLog? {
        guard usable, date.timeIntervalSinceReferenceDate.isFinite, !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let pending = operations.first(where: { $0.sourceFoodID == food.id }) { return pending }
        let capturedDay = dayContext ?? DiaryDayContext(userID: userID, date: Calendar.current.startOfDay(for: date))
        guard capturedDay?.isOwned(by: userID) == true else { return nil }
        var draft = FoodLoggingDraft(date: date, mealName: mealName, dayContext: capturedDay, trainingFuelTarget: trainingFuelTarget)
        var entry = FoodLoggingDraft.Entry(food: food)
        entry.hydrationPending = needsHydration
        draft.entries = [entry]
        let operation = PendingQuickFoodLog(id: UUID(), sourceFoodID: food.id, draft: draft, source: source)
        guard persist(operations + [operation]) else { return nil }
        return operation
    }

    @discardableResult
    public func hydrate(id: UUID, food: FoodItem) -> Bool {
        guard usable, let index = operations.firstIndex(where: { $0.id == id }), !operations[index].draft.isSubmitted,
              !savingIDs.contains(id), !operations[index].draft.entries.isEmpty else { return false }
        var next = operations
        let timestamp = next[index].draft.entries[0].food.timestamp
        next[index].draft.entries[0].food = food
        next[index].draft.entries[0].food.timestamp = timestamp
        next[index].draft.entries[0].hydrationPending = false
        return persist(next)
    }

    @discardableResult public func removeFuelContext(id: UUID) -> Bool {
        guard usable, let index = operations.firstIndex(where: { $0.id == id }),
              !operations[index].draft.isSubmitted, operations[index].isAccepted != true, !savingIDs.contains(id) else { return false }
        var next = operations; next[index].draft.trainingFuelTarget = nil
        return persist(next)
    }

    public func save(id: UUID, using service: DailyLogService, completion: @escaping (Bool) -> Void) {
        guard usable, service.isActiveAccount(userID), !savingIDs.contains(id),
              let index = operations.firstIndex(where: { $0.id == id }), operations[index].draft.isReadyToSubmit,
              operations[index].draft.dayContext?.isOwned(by: userID) ?? true else { completion(false); return }
        if operations[index].isAccepted == true {
            if let target = operations[index].draft.trainingFuelTarget {
                _ = service.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: operations[index].draft.foods, userID: userID)
            }
            completion(true); return
        }
        var next = operations
        if !next[index].draft.isSubmitted, let target = next[index].draft.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.stageFoodLink(target: target, foods: next[index].draft.foods, date: next[index].draft.date, using: service, userID: userID)
            } catch { errorMessage = error.localizedDescription; completion(false); return }
        }
        next[index].draft.isSubmitted = true
        guard persist(next) else { completion(false); return }
        let operation = operations[index]
        if let target = operation.draft.trainingFuelTarget {
            do {
                guard let fuel = service.trainingFuelPlanStore else { throw TrainingFuelLibraryError.changed }
                try fuel.authorizeFoodLink(target: target, foods: operation.draft.foods, userID: userID)
            } catch { errorMessage = "Could not prepare the saved fuel link. Retry this review; no new food was sent."; completion(false); return }
        }
        savingIDs.insert(id)
        service.addMealGroupsToLog(for: userID, date: operation.draft.date,
            mealGroups: [(mealName: operation.draft.mealName, foodItems: operation.draft.foods)],
            source: operation.source, deduplicateFoodIDs: true, dayContext: operation.draft.dayContext) { [weak self] accepted in
                guard let self else { completion(false); return }
                self.savingIDs.remove(id)
                guard self.usable, service.isActiveAccount(self.userID) else { completion(false); return }
                guard accepted else {
                    self.errorMessage = "Could not save this food. Its reviewed amount and original day are kept for retry."
                    completion(false)
                    return
                }
                if let target = operation.draft.trainingFuelTarget {
                    _ = service.trainingFuelPlanStore?.acceptFoodLink(target: target, foods: operation.draft.foods, userID: self.userID)
                }
                var acceptedState = self.operations
                if let savedIndex = acceptedState.firstIndex(where: { $0.id == id }) { acceptedState[savedIndex].isAccepted = true }
                if self.persist(acceptedState) { completion(true) } else {
                    self.errorMessage = "Your food was saved. Retry to clear its receipt; it will not be logged twice."
                    completion(false)
                }
            }
    }

    @discardableResult
    public func finish(id: UUID) -> Bool {
        guard usable, operations.contains(where: { $0.id == id && $0.isAccepted == true }), !savingIDs.contains(id) else { return false }
        return persist(operations.filter { $0.id != id })
    }

    private var usable: Bool {
        guard !unreadable, DIContainer.shared.authService.currentUserID == userID else {
            if !unreadable { errorMessage = "Sign back into the account that opened this quick log." }
            return false
        }
        return true
    }

    private func persist(_ next: [PendingQuickFoodLog]) -> Bool {
        guard usable else { return false }
        do {
            try store.save(next, userID: userID, scope: scope)
            operations = next
            errorMessage = nil
            return true
        } catch { errorMessage = "Could not keep this quick log on the device. Nothing new was sent; retry."; return false }
    }
}

public struct QuickMacroDraft: Codable, Equatable {
    public var calories = ""
    public var protein = ""
    public var carbs = ""
    public var fats = ""
    public let date: Date
    public let mealName: String
    public let foodID: String
    public var numberLocaleIdentifier: String?
    public var trainingFuelTarget: TrainingFuelTarget?

    public init(date: Date, mealName: String, foodID: String = UUID().uuidString) {
        self.date = date
        self.mealName = mealName
        self.foodID = foodID
        numberLocaleIdentifier = Locale.current.identifier
    }

    public var food: FoodItem? {
        let locale = Locale(identifier: numberLocaleIdentifier ?? Locale.current.identifier)
        guard let energy = Self.number(calories, locale: locale), let protein = Self.number(protein, locale: locale),
              let carbs = Self.number(carbs, locale: locale), let fats = Self.number(fats, locale: locale) else { return nil }
        let total = calories.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? protein * 4 + carbs * 4 + fats * 9 : energy
        guard total.isFinite, total > 0 else { return nil }
        return FoodItem(id: foodID, name: "Quick add macros", calories: total, protein: protein, carbs: carbs, fats: fats,
                        servingSize: "1 custom entry", servingWeight: 1, sourceMetadata: .userEntered(sourceName: "Quick add"))
    }

    /// A full decimal is required; suffixes, scientific overflow, NaN and negatives
    /// are never silently changed into a zero-valued nutrition entry.
    public static func number(_ text: String, locale: Locale = .current) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return 0 }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let decimal = formatter.decimalSeparator ?? "."
        let group = formatter.groupingSeparator ?? ","
        let decPattern = NSRegularExpression.escapedPattern(for: decimal)
        let groupPattern = NSRegularExpression.escapedPattern(for: group)
        let integer = group.isEmpty || group == decimal ? "[0-9]+" : "(?:[0-9]+|[0-9]{1,3}(?:\(groupPattern)[0-9]{3})+)"
        let pattern = "^(?:\(integer)(?:\(decPattern)[0-9]*)?|\(decPattern)[0-9]+)$"
        guard text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let ungrouped = group.isEmpty || group == decimal ? text : text.replacingOccurrences(of: group, with: "")
        guard let value = Double(ungrouped.replacingOccurrences(of: decimal, with: ".")), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
