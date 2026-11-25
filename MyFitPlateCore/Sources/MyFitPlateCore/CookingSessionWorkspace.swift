import Combine
import Foundation

public struct CookingSessionStep: Identifiable, Codable, Sendable {
    public var id: String
    public var requirementID: String
    public var recipeName: String
    public var text: String
    public var prerequisites: [String]
}

public enum CookingSessionRules {
    /// Free-form instructions retain their documented order within each recipe. No invented parallel timing.
    public static func steps(requirements: [MealCookingRequirement]) -> [CookingSessionStep] {
        requirements.flatMap { requirement in
            MealSuggestionReviewRules.instructionSteps(requirement.instructions ?? "").enumerated().map { index, text in
                .init(id: "\(requirement.id)-step-\(index)", requirementID: requirement.id, recipeName: requirement.name,
                      text: text, prerequisites: index == 0 ? [] : ["\(requirement.id)-step-\(index-1)"])
            }
        }
    }
    public static func canComplete(_ step: CookingSessionStep, completed: Set<String>) -> Bool { Set(step.prerequisites).isSubset(of: completed) }
    public static func selectedStepIndexes(steps: [CookingSessionStep], selected: Set<String>) -> [Int] {
        steps.indices.filter { selected.contains(steps[$0].requirementID) }
    }
    /// The earlier prep view merged matching recipe text. Retain that exact layout only
    /// to translate already-saved positional checks to their original requirement IDs.
    public static func legacyStepIDs(requirements: [MealCookingRequirement]) -> [String] {
        var groups = Set<String>()
        return requirements.flatMap { requirement -> [String] in
            guard let instructions = requirement.instructions,
                  groups.insert(requirement.name + requirement.ingredients.map(\.originalString).joined(separator: "\n") + instructions).inserted else { return [] }
            return steps(requirements: [requirement]).map(\.id)
        }
    }
    public static func checklist(requirements: [MealCookingRequirement], selected: Set<String>, completed: Set<String> = []) -> String {
        requirements.filter { selected.contains($0.id) }.map { requirement in
            let items = requirement.ingredients.map { ingredient -> String in
                let measured = InventoryQuantityRules.explicitLeadingAmount(ingredient.originalString) != nil
                return "  ☐ " + (measured ? "\(ingredient.quantity.formatted(.number.precision(.fractionLength(0...3)))) \(ingredient.unit) \(ingredient.name)" : "\(ingredient.name) · amount unconfirmed")
            }
            let steps = self.steps(requirements: [requirement]).map { "  \(completed.contains($0.id) ? "☑" : "☐") \($0.text)" }
            return (["\(requirement.name) · \(requirement.date.formatted(date: .abbreviated, time: .omitted))"] + items + steps).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
    public static func structuredChecklist(requirements: [MealCookingRequirement], selected: Set<String>) throws -> Data {
        struct Item: Codable { let name: String; let amount: Double?; let unit: String; let original: String }
        struct Session: Codable { let id: String; let name: String; let date: Date; let ingredients: [Item]; let steps: [CookingSessionStep] }
        let values = requirements.filter { selected.contains($0.id) }.map { requirement in
            Session(id: requirement.id, name: requirement.name, date: requirement.date,
                ingredients: requirement.ingredients.map { .init(name: $0.name, amount: InventoryQuantityRules.explicitLeadingAmount($0.originalString) == nil ? nil : $0.quantity, unit: $0.unit, original: $0.originalString) },
                steps: steps(requirements: [requirement]))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(values)
    }
}

public struct CookingTimerInspection: Identifiable, Codable, Sendable {
    public var id: String
    public var contextID: String
    public var timerID: UUID?
    public var name: String
    public var deadline: Date?
    public var pausedRemaining: TimeInterval
    public var finished: Bool
    public var stepID: String?
    public var instruction: String?
    public func remaining(now: Date = Date()) -> TimeInterval { deadline.map { max(0, $0.timeIntervalSince(now)) } ?? pausedRemaining }
}
public struct CookingTimerNotification: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let deadline: Date
}
public enum CookingNotificationRules {
    public static let identifierPrefix = "mfp.cooking."
    public static func alertCapacity(otherPendingCount: Int) -> Int { max(0, min(48, 64 - max(0, otherPendingCount))) }
    public static func identifier(userID: String, timer: CookingTimerInspection) -> String {
        let hash = (try? PlanFingerprint.make([userID, timer.contextID, timer.id])) ?? ""
        return identifierPrefix + hash
    }
    public static func timer(for notificationID: String, userID: String, in timers: [CookingTimerInspection]) -> CookingTimerInspection? {
        timers.first { identifier(userID: userID, timer: $0) == notificationID }
    }
    public static func requests(userID: String, timers: [CookingTimerInspection], now: Date = Date()) -> [CookingTimerNotification] {
        timers.compactMap { timer in
            guard let deadline = timer.deadline, deadline.timeIntervalSince1970.isFinite, deadline > now, !timer.finished else { return nil }
            return CookingTimerNotification(id: identifier(userID: userID, timer: timer), title: timer.name, deadline: deadline)
        }.sorted { $0.deadline < $1.deadline }.prefix(48).map { $0 }
    }
}

/// The account-local index makes timers inspectable outside their originating prep screen.
@MainActor public final class CookingTimerRegistry: ObservableObject {
    public static let shared = CookingTimerRegistry()
    @Published public private(set) var revision = 0
    @Published public private(set) var errorMessage: String?
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private struct Record: Codable { var contextID: String; var checkpoint: MealCookingCheckpoint }
    public func update(userID: String, contextID: String, checkpoint: MealCookingCheckpoint) {
        guard DIContainer.shared.authService.currentUserID == userID, let key = key(userID) else { return }
        let existing: [Record]
        do { existing = try load(userID) } catch {
            let message = "Your timer index could not be read. Original cooking checkpoints are kept; no index data was overwritten."
            if errorMessage != message { errorMessage = message }; return
        }
        if let same = existing.first(where: { $0.contextID == contextID }),
           (try? PlanFingerprint.make(same.checkpoint)) == (try? PlanFingerprint.make(checkpoint)) { return }
        if existing.allSatisfy({ $0.contextID != contextID }), checkpoint.timerEndDate == nil,
           checkpoint.pausedTimerRemaining == 0, !checkpoint.timerFinished, (checkpoint.additionalTimers ?? []).isEmpty { return }
        var records = existing
        records.removeAll { $0.contextID == contextID }
        if checkpoint.timerEndDate != nil || checkpoint.pausedTimerRemaining > 0 || checkpoint.timerFinished || !(checkpoint.additionalTimers ?? []).isEmpty {
            records.append(.init(contextID: contextID, checkpoint: checkpoint))
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key); errorMessage = nil; revision += 1
        NotificationCenter.default.post(name: .cookingTimersChanged, object: userID)
    }
    public func timers(userID: String) -> [CookingTimerInspection] {
        do { return try checkedTimers(userID: userID) } catch {
            Task { @MainActor [weak self] in
                let message = "Your timer index could not be read. Original cooking checkpoints are kept."
                if self?.errorMessage != message { self?.errorMessage = message }
            }
            return []
        }
    }
    public func checkedTimers(userID: String) throws -> [CookingTimerInspection] {
        guard DIContainer.shared.authService.currentUserID == userID else { throw MealPlanEditError.accountChanged }
        return try load(userID).flatMap { record -> [CookingTimerInspection] in
            let c = record.checkpoint
            var timers = (c.additionalTimers ?? []).map { timer in
                CookingTimerInspection(id: "\(record.contextID)|\(timer.id)", contextID: record.contextID, timerID: timer.id, name: timer.name,
                    deadline: timer.deadline, pausedRemaining: timer.pausedRemaining, finished: timer.finished, stepID: timer.stepID,
                    instruction: timer.instruction)
            }
            if c.timerEndDate != nil || c.pausedTimerRemaining > 0 || c.timerFinished {
                timers.append(.init(id: "\(record.contextID)|primary", contextID: record.contextID, name: "Cooking timer",
                    deadline: c.timerEndDate, pausedRemaining: c.pausedTimerRemaining, finished: c.timerFinished))
            }
            return timers
        }.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }
    private func key(_ userID: String) -> String? { AccountScopedStorageKey.make(prefix: "cooking-timer-index", userID: userID) }
    private func load(_ userID: String) throws -> [Record] {
        guard let key = key(userID), let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([Record].self, from: data)
    }
}
public extension Notification.Name { static let cookingTimersChanged = Notification.Name("cookingTimersChanged") }

public struct PantryRecipeShortage: Identifiable, Sendable {
    public var id: Int
    public var ingredient: String
    public var required: Double?
    public var unit: String
    public var available: Double
    public var lotIDs: [UUID]
    public var message: String
}
public struct PantryRecipeFit: Sendable {
    public var rows: [PantryRecipeShortage]
    public var blockers: [String]
    public var warnings: [String]
    public var canUseWithoutShopping: Bool { blockers.isEmpty && rows.allSatisfy { $0.required != nil && $0.available + 0.000001 >= $0.required! } }
}
public enum PantryRecipeFitRules {
    public static func ranked(_ recipes: [Recipe], stock: [PantryItem]) -> [Recipe] {
        recipes.enumerated().sorted { left, right in
            func score(_ recipe: Recipe) -> Double {
                guard let fit = try? review(recipe: recipe, servings: 1, stock: stock, exclusions: [], equipment: []) else { return -1 }
                let coverage = fit.rows.reduce(0.0) { total, row in total + (row.required.map { min(1, row.available / max($0, 0.000001)) } ?? 0) }
                return coverage / Double(max(fit.rows.count, 1))
            }
            let a = score(left.element), b = score(right.element)
            if a != b { return a > b }
            let timeA = left.element.planningProfile?.prepMinutes ?? .max, timeB = right.element.planningProfile?.prepMinutes ?? .max
            return timeA == timeB ? left.offset < right.offset : timeA < timeB
        }.map(\.element)
    }
    /// Coverage is allocated once across ingredient rows, never inferred from the model's stock claim.
    public static func review(recipe: Recipe, servings: Double, stock: [PantryItem], exclusions: [String], equipment: [String], now: Date = Date()) throws -> PantryRecipeFit {
        let selection = RecipePortionSelection(unit: .servings, amount: servings)
        let food = try RecipePortionRules.foodItem(for: recipe, selection: selection)
        let ingredients = try RecipePortionRules.ingredients(for: recipe, selection: selection)
        var balances = Dictionary(uniqueKeysWithValues: stock.map { ($0.id, $0.availableQuantity) })
        var rows: [PantryRecipeShortage] = [], blockers: [String] = [], warnings: [String] = []
        let profile = recipe.planningProfile?.isCurrent(for: recipe) == true ? recipe.planningProfile : nil
        for exclusion in exclusions where !exclusion.isEmpty {
            if MealPlanConstraintRules.contains((ingredients + [food.name]).joined(separator: " "), phrase: exclusion) { blockers.append("Contains \(exclusion).") } else if profile?.reviewedExclusions.contains(where: { MealPlanConstraintRules.normalized($0) == MealPlanConstraintRules.normalized(exclusion) }) != true { blockers.append("Ingredient review for \(exclusion) is missing.") }
        }
        if !equipment.isEmpty {
            guard let tools = profile?.equipment, !tools.isEmpty else {
                return PantryRecipeFit(rows: [], blockers: blockers + ["Confirm this recipe's required equipment in its editor."], warnings: [])
            }
            let missing = Set(tools.map(MealPlanConstraintRules.normalized)).subtracting(["no cooking"]).subtracting(equipment.map(MealPlanConstraintRules.normalized))
            if !missing.isEmpty { blockers.append("Missing equipment: \(missing.sorted().joined(separator: ", ")).") }
        }
        for (index, line) in ingredients.enumerated() {
            let parsed = IngredientLineParser.normalizedIngredient(from: line)
            guard InventoryQuantityRules.explicitLeadingAmount(line) != nil else {
                rows.append(.init(id: index, ingredient: parsed.name, required: nil, unit: parsed.unit, available: 0, lotIDs: [], message: "Amount unconfirmed; stock fit cannot be established.")); continue
            }
            var remaining = parsed.quantity, covered = 0.0, used: [UUID] = []
            for lot in stock.sorted(by: { ($0.bestBefore ?? .distantFuture) < ($1.bestBefore ?? .distantFuture) }) {
                guard lot.quantityVerified == true, lot.quantityUnknown != true, lot.isArchived != true, lot.cookedBatch == nil,
                      InventoryQuantityRules.usable(lot, now: now),
                      InventoryQuantityRules.ingredientIdentity(lot.name) == InventoryQuantityRules.ingredientIdentity(parsed.name),
                      lot.preparation != "Cooked" || parsed.name.lowercased().contains("cooked"),
                      let converted = InventoryQuantityRules.convert(balances[lot.id] ?? 0, from: lot.unit, to: parsed.unit),
                      converted > 0, remaining > 0 else { continue }
                let taken = min(converted, remaining)
                guard let lotAmount = InventoryQuantityRules.convert(taken, from: parsed.unit, to: lot.unit) else { continue }
                balances[lot.id, default: 0] -= lotAmount; remaining -= taken; covered += taken; used.append(lot.id)
            }
            rows.append(.init(id: index, ingredient: parsed.name, required: parsed.quantity, unit: parsed.unit, available: covered, lotIDs: used,
                message: remaining > 0.000001 ? "Buy or substitute \(remaining.formatted(.number.precision(.fractionLength(0...3)))) \(parsed.unit)." : "Covered by the selected confirmed lots."))
        }
        if rows.contains(where: { $0.required == nil }) { warnings.append("Unknown amounts remain untracked. Confirm them before claiming complete pantry coverage.") }
        return .init(rows: rows, blockers: blockers, warnings: warnings)
    }
}
