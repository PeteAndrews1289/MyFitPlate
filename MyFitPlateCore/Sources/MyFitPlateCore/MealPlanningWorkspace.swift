import Combine
import CryptoKit
import Foundation

public enum PlanningDocumentRules {
    public static func canonicalized<Value: Codable>(_ value: Value) throws -> Value {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Value.self, from: encoded(value))
    }
    public static func fingerprint<Value: Encodable>(_ value: Value) throws -> String {
        SHA256.hash(data: try encoded(value)).map { String(format: "%02x", $0) }.joined()
    }
    private static func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var box = encoder.singleValueContainer(); try box.encode((date.timeIntervalSince1970 * 1_000).rounded())
        }
        return try encoder.encode(value)
    }
    public static func validID(_ value: String) -> Bool { !value.isEmpty && value.count <= 128 && !value.contains("/") }
}

public protocol PlanningWorkspaceDocument: Codable, Identifiable where ID == String {
    var id: String { get }
    var revisionID: String { get }
    var name: String { get }
    func validate() throws
    func validateStoredSnapshot() throws
}
public extension PlanningWorkspaceDocument {
    func validateStoredSnapshot() throws { try validate() }
}

public struct MealCompositionSnapshot: Codable, Hashable, Sendable {
    public var title: String
    public var components: [FoodItem]
    public var sourceID: String?
    public var revisionID: String
    public init(title: String, components: [FoodItem], sourceID: String? = nil, revisionID: String = UUID().uuidString) {
        self.title = title; self.components = components; self.sourceID = sourceID; self.revisionID = revisionID
    }
}

public struct SavedMealComposition: PlanningWorkspaceDocument, Sendable {
    public var id: String
    public var revisionID: String
    public var name: String
    public var components: [FoodItem]
    public var updatedAt: Date
    public var isArchived: Bool
    public init(id: String = UUID().uuidString, name: String, components: [FoodItem]) {
        self.id = id; revisionID = UUID().uuidString; self.name = name; self.components = components
        updatedAt = Date(); isArchived = false
    }
    public func validate() throws {
        guard PlanningDocumentRules.validID(id), PlanningDocumentRules.validID(revisionID), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 200, (1...40).contains(components.count), Set(components.map(\.id)).count == components.count,
              components.allSatisfy({ food in !food.name.isEmpty && food.mealComposition == nil &&
                  ([food.calories, food.protein, food.carbs, food.fats, food.servingWeight] + MicronutrientKey.allCases.compactMap { food.micronutrientValue(for: $0) }).allSatisfy { $0.isFinite && $0 >= 0 && $0 < 1_000_000_000 } }),
              Nutrition.total(for: components).calories.isFinite, Nutrition.total(for: components).calories < 100_000,
              updatedAt.timeIntervalSince1970.isFinite else { throw MealPlanEditError.invalid }
    }
    public var snapshot: MealCompositionSnapshot { .init(title: name, components: components, sourceID: id, revisionID: revisionID) }
}

public struct SavedMealWeekTemplate: PlanningWorkspaceDocument, Sendable {
    public var id: String
    public var revisionID: String
    public var name: String
    public var days: [MealPlanDay]
    public var favorite: Bool
    public var updatedAt: Date
    public var isArchived: Bool
    public init(id: String = UUID().uuidString, name: String, days: [MealPlanDay]) {
        self.id = id; revisionID = UUID().uuidString; self.name = name; self.days = days
        favorite = false; updatedAt = Date(); isArchived = false
    }
    public func validate() throws {
        try validateStoredSnapshot()
        guard PlanningDocumentRules.validID(id), PlanningDocumentRules.validID(revisionID), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 200, days.count == 7, Set(days.map(\.id)).count == 7,
              days.allSatisfy({ $0.id == MealPlanEditingRules.dayID($0.date) }),
              !days.flatMap(\.meals).isEmpty,
              updatedAt.timeIntervalSince1970.isFinite else { throw MealPlanEditError.invalid }
        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first else { throw MealPlanEditError.invalid }
        for (offset, day) in sorted.enumerated() {
            guard Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: first.date), to: Calendar.current.startOfDay(for: day.date)).day == offset else { throw MealPlanEditError.invalid }
        }
        let mealIDs = Set(days.flatMap(\.meals).map(\.id))
        guard mealIDs.count == days.flatMap(\.meals).count else { throw MealPlanEditError.invalid }
        for batch in days.flatMap(\.meals).compactMap(\.cookingBatch) {
            guard Set(batch.allocations.map(\.mealID)).isSubset(of: mealIDs) else { throw MealCookingError.linkedBatch }
        }
        try MealPlanEditingRules.validate(MealPlanChange(title: "Validate template", before: days, after: days))
    }
    /// Stored civil day keys remain readable after travel. The original absolute
    /// timestamps are never reinterpreted as permission to write another calendar day.
    public func validateStoredSnapshot() throws {
        guard PlanningDocumentRules.validID(id), PlanningDocumentRules.validID(revisionID),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              days.count == 7, Set(days.map(\.id)).count == 7, !days.flatMap(\.meals).isEmpty,
              days.allSatisfy({ $0.date.timeIntervalSince1970.isFinite }), updatedAt.timeIntervalSince1970.isFinite else {
            throw MealPlanEditError.invalid
        }
        // Validating a separate current-calendar copy checks the complete graph and
        // meal quantities without changing a single byte of this stored template.
        _ = try MealWeekTemplateRules.draft(self, starting: Date(timeIntervalSince1970: 1_700_000_000))
    }
}

public struct PlanningDocumentProposal<Value: PlanningWorkspaceDocument>: Codable {
    public let userID: String
    public let operationID: UUID
    public let expected: Value?
    public let updated: Value
    public init(userID: String, operationID: UUID = UUID(), expected: Value?, updated: Value) {
        self.userID = userID; self.operationID = operationID; self.expected = expected; self.updated = updated
    }
    /// Receipt identity is independent of the calendar in which a frozen review is reopened.
    /// New writes still validate the complete document through `validate()`.
    public func validateEnvelope() throws {
        guard !userID.isEmpty, PlanningDocumentRules.validID(updated.id), PlanningDocumentRules.validID(updated.revisionID),
              expected == nil || expected?.id == updated.id else { throw MealPlanEditError.invalid }
        guard (try JSONEncoder().encode(self)).count < 350_000 else { throw MealPlanEditError.invalid }
    }
    public func validate() throws { try validateEnvelope(); try updated.validate() }
    public func fingerprint() throws -> String { try validateEnvelope(); return try PlanningDocumentRules.fingerprint(self) }
    public func applying(to actual: Value?) throws -> Value {
        try validate()
        guard try PlanningDocumentRules.fingerprint(expected) == PlanningDocumentRules.fingerprint(actual) else { throw MealPlanEditError.changed }
        return updated
    }
}
public typealias MealCompositionSaveProposal = PlanningDocumentProposal<SavedMealComposition>
public typealias MealWeekTemplateSaveProposal = PlanningDocumentProposal<SavedMealWeekTemplate>
public enum PlanningDocumentSaveResolution: String, Codable, Sendable { case pending, accepted, cancelled }
public struct PlanningDocumentCheckpoint<Value: PlanningWorkspaceDocument>: Codable {
    public var proposal: PlanningDocumentProposal<Value>
    public var submitted = false
    public var resolution = PlanningDocumentSaveResolution.pending
    public init(proposal: PlanningDocumentProposal<Value>, submitted: Bool = false, resolution: PlanningDocumentSaveResolution = .pending) {
        self.proposal = proposal; self.submitted = submitted; self.resolution = resolution
    }
}

/// Exact proposed payload survives unknown acknowledgements. Closing does not abandon a submitted save.
@MainActor public final class PlanningDocumentSaveSession<Value: PlanningWorkspaceDocument>: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public private(set) var checkpoint: PlanningDocumentCheckpoint<Value>?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isWorking = false
    public let userID: String?
    private let scope: String
    private let store: EditorDraftStore
    private var expectedFingerprint: String?
    private var unreadable = false
    public init(userID: String?, scope: String, proposal: PlanningDocumentProposal<Value>? = nil, store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.scope = scope; self.store = store
        guard active, let userID else { return }
        do {
            checkpoint = try store.load(PlanningDocumentCheckpoint<Value>.self, userID: userID, scope: scope)?.value
            if let checkpoint { try checkpoint.proposal.validateEnvelope(); guard checkpoint.proposal.userID == userID else { throw MealPlanEditError.accountChanged } }
            expectedFingerprint = try checkpoint.map(PlanFingerprint.make)
            if checkpoint == nil, let proposal { try proposal.validate(); try persist(.init(proposal: proposal)) }
        } catch { unreadable = true; errorMessage = "The previous review is kept on this device and could not be read." }
    }
    public var finished: Bool { checkpoint?.resolution != .pending && checkpoint != nil }
    public func save(_ action: (PlanningDocumentProposal<Value>) async throws -> Value) async {
        guard active, !isWorking, var value = checkpoint, value.resolution == .pending else { return }
        do {
            value.submitted = true; try persist(value); isWorking = true; defer { isWorking = false }
            _ = try await action(value.proposal)
            guard active else { throw MealPlanEditError.accountChanged }
            value.resolution = .accepted; try persist(value)
        } catch { errorMessage = "This exact review is kept. Check saved status or retry. " + error.localizedDescription }
    }
    public func resolve(cancelPending: Bool, _ action: (PlanningDocumentProposal<Value>, Bool) async throws -> PlanningDocumentSaveResolution) async {
        guard active, !isWorking, var value = checkpoint else { return }
        isWorking = true; defer { isWorking = false }
        do {
            let status = try await action(value.proposal, cancelPending)
            guard active else { throw MealPlanEditError.accountChanged }
            value.resolution = status; try persist(value)
            if status == .pending { errorMessage = "No accepted receipt yet. Retry this review or cancel its pending save." }
        } catch { errorMessage = "The review is kept until its status can be confirmed. " + error.localizedDescription }
    }
    public func finish() -> Bool {
        guard active, !isWorking, let userID, let value = checkpoint, !value.submitted || finished else { return false }
        do {
            guard try store.load(PlanningDocumentCheckpoint<Value>.self, userID: userID, scope: scope).map({ try PlanFingerprint.make($0.value) }) == expectedFingerprint else { throw MealPlanEditError.changed }
            try store.remove(userID: userID, scope: scope); checkpoint = nil; expectedFingerprint = nil; return true
        } catch { errorMessage = "A newer review was kept. Close and reopen it."; return false }
    }
    private var active: Bool { !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ value: PlanningDocumentCheckpoint<Value>) throws {
        guard active, let userID else { throw MealPlanEditError.accountChanged }
        let current = try store.load(PlanningDocumentCheckpoint<Value>.self, userID: userID, scope: scope)?.value
        guard try current.map(PlanFingerprint.make) == expectedFingerprint else { throw MealPlanEditError.changed }
        try store.save(value, userID: userID, scope: scope); checkpoint = value
        expectedFingerprint = try PlanFingerprint.make(value); errorMessage = nil
    }
}

public enum MealCompositionRules {
    public static func food(_ snapshot: MealCompositionSnapshot, entryID: String = UUID().uuidString) throws -> FoodItem {
        try SavedMealComposition(name: snapshot.title, components: snapshot.components).validate()
        var n = Nutrition.total(for: snapshot.components)
        let optionalFields: [(WritableKeyPath<Nutrition, Double?>, KeyPath<FoodItem, Double?>)] = [
            (\.saturatedFat, \.saturatedFat), (\.polyunsaturatedFat, \.polyunsaturatedFat), (\.monounsaturatedFat, \.monounsaturatedFat),
            (\.fiber, \.fiber), (\.calcium, \.calcium), (\.iron, \.iron), (\.potassium, \.potassium), (\.sodium, \.sodium),
            (\.vitaminA, \.vitaminA), (\.vitaminC, \.vitaminC), (\.vitaminD, \.vitaminD), (\.vitaminB12, \.vitaminB12),
            (\.folate, \.folate), (\.magnesium, \.magnesium), (\.phosphorus, \.phosphorus), (\.zinc, \.zinc), (\.copper, \.copper),
            (\.manganese, \.manganese), (\.selenium, \.selenium), (\.vitaminB1, \.vitaminB1), (\.vitaminB2, \.vitaminB2),
            (\.vitaminB3, \.vitaminB3), (\.vitaminB5, \.vitaminB5), (\.vitaminB6, \.vitaminB6), (\.vitaminE, \.vitaminE), (\.vitaminK, \.vitaminK)
        ]
        for (total, source) in optionalFields where snapshot.components.contains(where: { $0[keyPath: source] == nil }) { n[keyPath: total] = nil }
        var food = FoodItem(id: entryID, name: snapshot.title, calories: n.calories, protein: n.protein, carbs: n.carbs, fats: n.fats,
            saturatedFat: n.saturatedFat, polyunsaturatedFat: n.polyunsaturatedFat, monounsaturatedFat: n.monounsaturatedFat, fiber: n.fiber,
            servingSize: "1 composed meal", servingWeight: snapshot.components.allSatisfy({ $0.servingWeight > 0 }) ? snapshot.components.reduce(0) { $0 + $1.servingWeight } : 0,
            calcium: n.calcium, iron: n.iron, potassium: n.potassium, sodium: n.sodium, vitaminA: n.vitaminA, vitaminC: n.vitaminC,
            vitaminD: n.vitaminD, vitaminB12: n.vitaminB12, folate: n.folate, magnesium: n.magnesium, phosphorus: n.phosphorus,
            zinc: n.zinc, copper: n.copper, manganese: n.manganese, selenium: n.selenium, vitaminB1: n.vitaminB1, vitaminB2: n.vitaminB2,
            vitaminB3: n.vitaminB3, vitaminB5: n.vitaminB5, vitaminB6: n.vitaminB6, vitaminE: n.vitaminE, vitaminK: n.vitaminK)
        food.mealComposition = snapshot
        food.sourceMetadata = FoodSourceMetadata(sourceType: .custom, confidence: .estimated, reviewStatus: .userConfirmed,
            sourceName: "Reviewed meal composition", sourceID: snapshot.sourceID, evidenceLineage: .derivedEntry,
            notes: "Each component retains its original evidence. Nutrients missing from any component remain unknown in the aggregate.")
        return food
    }
    public static func ingredientText(_ food: FoodItem) -> String {
        food.servingWeight > 0 ? "\(food.servingWeight.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))) g \(food.name)" : "\(food.servingSize) \(food.name)"
    }
}

public enum MealPlanHistoryRules {
    /// Invert only identities touched by the selected operation, retaining unrelated later meals.
    public static func inverse(_ operation: MealPlanChange, current: [MealPlanDay]) throws -> MealPlanChange {
        var before: [MealPlanDay] = [], after: [MealPlanDay] = []
        for original in operation.before {
            guard let accepted = operation.after.first(where: { $0.id == original.id }),
                  let actual = current.first(where: { $0.id == original.id }) else { throw MealPlanEditError.changed }
            let ids = Set(original.meals.map(\.id)).union(accepted.meals.map(\.id)).filter { id in
                (try? PlanningDocumentRules.fingerprint(original.meals.first { $0.id == id })) != (try? PlanningDocumentRules.fingerprint(accepted.meals.first { $0.id == id }))
            }
            var restored = actual
            for id in ids {
                let expected = accepted.meals.first { $0.id == id }, live = actual.meals.first { $0.id == id }
                guard try PlanningDocumentRules.fingerprint(expected) == PlanningDocumentRules.fingerprint(live) else { throw MealPlanEditError.changed }
                restored.meals.removeAll { $0.id == id }
                if let old = original.meals.first(where: { $0.id == id }) { restored.meals.append(old) }
            }
            restored.meals = MealPlanEditingRules.sorted(restored.meals); before.append(actual); after.append(restored)
        }
        guard try PlanningDocumentRules.fingerprint(before) != PlanningDocumentRules.fingerprint(after) else { throw MealPlanEditError.changed }
        let result = MealPlanChange(title: "Undo \(operation.title)", before: before, after: after)
        try MealPlanEditingRules.validate(result); return result
    }
}

public enum MealWeekTemplateRules {
    public static func draft(_ template: SavedMealWeekTemplate, starting date: Date, excluding: Set<String> = [], householdScale: Double = 1) throws -> MealPlanWeekDraft {
        guard PlanningDocumentRules.validID(template.id), PlanningDocumentRules.validID(template.revisionID),
              !template.name.isEmpty, template.days.count == 7, householdScale.isFinite, (0.25...8).contains(householdScale) else { throw MealPlanEditError.invalid }
        let calendar = Calendar.current
        let source = template.days.sorted { $0.id < $1.id }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.calendar = utc
        parser.timeZone = .gmt; parser.dateFormat = "yyyy-MM-dd"; parser.isLenient = false
        let civilDates = try source.map { day -> Date in
            guard let value = parser.date(from: day.id), parser.string(from: value) == day.id, day.meals.count <= 40 else { throw MealPlanEditError.calendarChanged }; return value
        }
        for (index, value) in civilDates.enumerated() {
            guard utc.dateComponents([.day], from: civilDates[0], to: value).day == index else { throw MealPlanEditError.invalid }
        }
        let allMeals = source.flatMap(\.meals), selected = allMeals.filter { !excluding.contains($0.id) }
        guard Set(allMeals.map(\.id)).count == allMeals.count else { throw MealPlanEditError.changed }
        let keptIDs = Set(selected.map(\.id))
        for batch in selected.compactMap(\.cookingBatch) {
            guard Set(batch.allocations.map(\.mealID)).isSubset(of: keptIDs) else { throw MealCookingError.linkedBatch }
        }
        let targets = try (0..<7).map { offset -> Date in
            guard let target = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { throw MealPlanEditError.invalid }; return target
        }
        var result: [MealPlanDay] = []
        for (offset, old) in source.enumerated() {
            var day = MealPlanEditingRules.emptyDay(targets[offset])
            day.meals = try old.meals.filter { !excluding.contains($0.id) }.map { original in
                var meal = original
                meal.preparedStock = nil // A reusable week cannot promise an earlier week’s physical leftovers.
                if var batch = meal.cookingBatch {
                    // Frozen day keys and referenced meal identities establish the mapping;
                    // never infer a legacy source zone from an absolute midnight timestamp.
                    guard let cookingIndex = source.firstIndex(where: { $0.date == batch.cookingDate })
                        ?? source.firstIndex(where: { $0.meals.contains { $0.id == batch.sourceMealID } }) else { throw MealPlanEditError.calendarChanged }
                    batch.cookingDate = targets[cookingIndex]; batch.totalPortions *= householdScale
                    if !keptIDs.contains(batch.sourceMealID) {
                        guard let anchor = batch.allocations.sorted(by: { $0.date < $1.date }).first(where: { keptIDs.contains($0.mealID) }) else { throw MealCookingError.changed }
                        batch.sourceMealID = anchor.mealID
                    }
                    batch.allocations = try batch.allocations.map { allocation in
                        guard let index = source.firstIndex(where: { $0.meals.contains { $0.id == allocation.mealID } }) else { throw MealCookingError.changed }
                        return MealCookingAllocation(mealID: allocation.mealID, date: targets[index], portions: allocation.portions)
                    }
                    guard batch.totalPortions + 0.000001 >= batch.allocatedPortions else { throw MealCookingError.overallocated }
                    meal.cookingBatch = batch
                }
                return meal
            }
            result.append(day)
        }
        try MealPlanEditingRules.validate(.init(title: "Template date review", before: result.map { MealPlanEditingRules.emptyDay($0.date) }, after: result))
        return .init(days: result, title: "Reuse \(template.name)", preserveCookingBatches: true)
    }
}

public enum PlannedMealMeasurementRules {
    public static func hasKnownMass(_ base: FoodItem) -> Bool {
        guard base.servingWeight.isFinite, base.servingWeight > 0 else { return false }
        if base.recipePortionSnapshot?.cookedGrams != nil || base.servingWeight != 1 { return true }
        let text = "\(base.servingSize) \(base.servingUnit ?? "")".lowercased()
        return text.range(of: #"\b(g|grams?|kg|kilograms?|oz|ounces?|lb|lbs|pounds?)\b"#, options: .regularExpression) != nil
    }
    public static func multiplier(amount: Double, unit: String, base: FoodItem) throws -> Double {
        guard amount.isFinite, amount > 0 else { throw MealPlanEditError.invalid }
        let multiplier: Double
        if unit == "original" { multiplier = amount } else if hasKnownMass(base), let grams = InventoryQuantityRules.convert(amount, from: unit, to: "g") { multiplier = grams / base.servingWeight } else if let count = base.quantityValue, count > 0, base.servingUnit?.caseInsensitiveCompare(unit) == .orderedSame { multiplier = amount / count } else { throw MealPlanEditError.invalid }
        guard (0.25...8).contains(multiplier) else { throw MealPlanEditError.invalid }; return multiplier
    }
}

public struct PantryPhotoObservationDraft: Codable, Identifiable {
    public let id: UUID
    public let userID: String
    public var date: Date
    public var mealName: String
    public var ingredients: [String]
    public var confirmed = false
    public var recipeIdeas: [Recipe]?
    public init(userID: String, date: Date, mealName: String, ingredients: [String]) {
        id = UUID(); self.userID = userID; self.date = date; self.mealName = mealName; self.ingredients = ingredients
    }
    public func validate() throws {
        guard !userID.isEmpty, !mealName.isEmpty, date.timeIntervalSince1970.isFinite, (1...40).contains(ingredients.count),
              ingredients.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 }) else { throw MealPlanEditError.invalid }
    }
}

public struct MealAlternativeCandidate: Identifiable {
    public let id = UUID()
    public var meal: PlannedMeal
    public var issues: [MealPlanConstraintIssue]
    public var calorieDifference: Double
    public var canUse: Bool { !issues.contains(where: \.blocking) }
}
public enum MealAlternativeRules {
    public static func candidates(recipes: [Recipe], day: MealPlanDay, replacing original: PlannedMeal, constraints: MealPlanConstraints, week: [MealPlanDay]? = nil) -> [MealAlternativeCandidate] {
        guard original.cookingBatch?.allocations.count ?? 0 <= 1 else { return [] }
        var result: [MealAlternativeCandidate] = []
        for recipe in recipes.prefix(80) where RecipeLibraryRules.isVisible(recipe) && recipe.name != original.foodItem?.name {
            for amount in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
                guard let food = try? RecipePortionRules.foodItem(for: recipe, selection: .init(unit: .servings, amount: 1)),
                      let ingredients = try? RecipePortionRules.ingredients(for: recipe, selection: .init(unit: .servings, amount: 1)) else { continue }
                var meal = PlannedMeal(id: original.id, mealType: original.mealType, recipeID: recipe.id, foodItem: food,
                    ingredients: ingredients, instructions: recipe.instructions.joined(separator: "\n"), portionMultiplier: amount)
                if let profile = recipe.planningProfile, profile.isCurrent(for: recipe) { meal.planningEvidence = try? .init(profile: profile, meal: meal) }
                if let quantity = original.cookingBatch?.totalPortions {
                    guard let configured = try? MealPlanCookingRules.configuring(meal, date: day.date, cookingPortions: max(quantity, amount)) else { continue }; meal = configured
                }
                let reviewed = review(meal: meal, day: day, replacing: original, constraints: constraints, week: week)
                result.append(reviewed)
            }
        }
        let sorted = result.sorted { ($0.canUse ? 0 : 1, abs($0.calorieDifference)) < ($1.canUse ? 0 : 1, abs($1.calorieDifference)) }
        var names = Set<String>()
        return sorted.filter { names.insert($0.meal.foodItem?.name ?? $0.id.uuidString).inserted }.prefix(6).map { $0 }
    }
    public static func review(meal: PlannedMeal, day: MealPlanDay, replacing original: PlannedMeal, constraints: MealPlanConstraints, week: [MealPlanDay]? = nil) -> MealAlternativeCandidate {
        var updated = day; updated.meals = day.meals.map { $0.id == original.id ? meal : $0 }
        var c = constraints
        var source = [updated]
        if constraints.weeklyBudget != nil, let week {
            source = week.map { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) ? updated : $0 }
        } else { c.weeklyBudget = nil }
        var issues = MealPlanConstraintRules.report(days: source, constraints: c).issues.filter {
            $0.id != "week" && ($0.dayID == nil || $0.dayID == MealPlanEditingRules.dayID(day.date))
        }
        if constraints.weeklyBudget != nil && week?.count != 7 { issues.append(.init(id: "week-cost-review", message: "Load all seven days before checking the weekly budget.", blocking: true)) }
        return .init(meal: meal, issues: issues, calorieDifference: updated.meals.compactMap(\.plannedFood).reduce(0) { $0 + $1.calories } - constraints.calories)
    }
}

public extension MealPlanHistoryRules {
    static func removing(mealIDs: Set<String>, from days: [MealPlanDay], title: String) throws -> MealPlanChange {
        guard !mealIDs.isEmpty, Set(days.map(\.id)).count == days.count else { throw MealPlanEditError.invalid }
        var working = days
        let removals = days.flatMap(\.meals).filter { mealIDs.contains($0.id) }.sorted { left, right in
            let a = left.cookingBatch?.sourceMealID == left.id, b = right.cookingBatch?.sourceMealID == right.id
            return a == b ? left.id < right.id : !a
        }
        guard Set(removals.map(\.id)) == mealIDs else { throw MealPlanEditError.changed }
        for original in removals {
            guard let index = working.firstIndex(where: { $0.meals.contains { $0.id == original.id } }),
                  let meal = working[index].meals.first(where: { $0.id == original.id }) else { throw MealPlanEditError.changed }
            if meal.cookingBatch != nil {
                let change = try MealPlanCookingRules.removing(meal: meal, source: working[index], relatedDays: working)
                working = change.after
            } else { working[index].meals.removeAll { $0.id == meal.id } }
        }
        let change = MealPlanChange(title: title, before: days, after: working)
        try MealPlanEditingRules.validate(change); return change
    }
}
