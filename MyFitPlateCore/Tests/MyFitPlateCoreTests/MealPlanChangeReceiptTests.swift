import XCTest
@testable import MyFitPlateCore

@MainActor
final class MealPlanChangeReceiptTests: XCTestCase {
    private let userID = "receipt-user"
    private var date: Date { Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_792_000_000)) }

    private func day(_ offset: Int, meals: [PlannedMeal] = []) throws -> MealPlanDay {
        let date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: offset, to: date))
        var day = MealPlanEditingRules.emptyDay(date); day.meals = meals
        return day
    }

    private func change() throws -> MealPlanChange {
        let before = try day(0)
        let meal = PlannedMeal(id: "planned-rice", mealType: "Lunch", ingredients: ["100 g rice"], instructions: "Cook.")
        return MealPlanChange(title: "Lunch planned", before: [before], after: [try day(0, meals: [meal])])
    }

    private func expectFailure(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected rejection", file: file, line: line) } catch {}
    }

    func testReceiptRoundTripAndFullFrozenPayloadFingerprint() throws {
        let original = try change()
        let receipt = try MealPlanChangeReceipt(userID: userID, change: original, status: .accepted)
        let restored = try JSONDecoder().decode(MealPlanChangeReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertEqual(receipt, restored)
        try restored.validate(userID: userID, change: original)
        XCTAssertEqual(restored.resolution, .accepted)
        var renamed = original; renamed.title = "Different operation wording"
        XCTAssertThrowsError(try restored.validate(userID: userID, change: renamed))
        var adjusted = original; adjusted.after[0].meals[0].portionMultiplier = 2
        XCTAssertThrowsError(try restored.validate(userID: userID, change: adjusted))
        var changedBaseline = original; changedBaseline.before[0].meals = original.after[0].meals
        XCTAssertThrowsError(try restored.validate(userID: userID, change: changedBaseline))
        var changedDate = original; changedDate.after[0].date.addTimeInterval(0.0001)
        XCTAssertThrowsError(try restored.validate(userID: userID, change: changedDate))
        XCTAssertThrowsError(try restored.validate(userID: "other-user", change: original))
    }

    func testAcceptedReplayNeverOverwritesLaterEditsOrCreatesDeletedPlans() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        try await repository.applyMealPlanChange(userID: userID, change: original)
        var newer = original.after[0]; newer.meals[0].instructions = "Newer intentional edit."
        repository.mockMealPlansByDateString[newer.id] = newer
        try await repository.applyMealPlanChange(userID: userID, change: original)
        XCTAssertEqual(repository.mockMealPlansByDateString[newer.id]?.meals[0].instructions, "Newer intentional edit.")
        XCTAssertEqual(repository.appliedMealPlanChangeIDs, [original.id])
        repository.mockMealPlansByDateString.removeValue(forKey: newer.id)
        try await repository.applyMealPlanChange(userID: userID, change: original)
        XCTAssertNil(repository.mockMealPlansByDateString[newer.id])
        let status = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: false)
        XCTAssertEqual(status, .accepted)
    }

    func testLostAcknowledgementResolvesAfterLaterEditAndRetryIsReadOnly() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        repository.mealPlanChangeFailureAfterCommit = APIError.apiError("Acknowledgement lost")
        await expectFailure { try await repository.applyMealPlanChange(userID: self.userID, change: original) }
        var newer = original.after[0]; newer.meals[0].instructions = "Edited while acknowledgement was missing."
        repository.mockMealPlansByDateString[newer.id] = newer
        let status = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: false)
        XCTAssertEqual(status, .accepted)
        try await repository.applyMealPlanChange(userID: userID, change: original)
        XCTAssertEqual(repository.mockMealPlansByDateString[newer.id]?.meals[0].instructions, newer.meals[0].instructions)
        XCTAssertEqual(repository.appliedMealPlanChangeIDs, [original.id])
    }

    func testStatusAbsenceIsPendingAndDoesNotPreventLaterApply() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        let pending = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: false)
        XCTAssertEqual(pending, .pending)
        XCTAssertTrue(repository.mealPlanChangeReceipts.isEmpty)
        try await repository.applyMealPlanChange(userID: userID, change: original)
        let accepted = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: false)
        XCTAssertEqual(accepted, .accepted)
    }

    func testPermanentCancelFenceRejectsLateApplyAndHasNoPlanWrites() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        let cancelled = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: true)
        XCTAssertEqual(cancelled, .cancelled)
        await expectFailure { try await repository.applyMealPlanChange(userID: self.userID, change: original) }
        let again = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: false)
        XCTAssertEqual(again, .cancelled)
        XCTAssertTrue(repository.mockMealPlansByDateString.isEmpty)
        XCTAssertTrue(repository.batchSavedMealPlans.isEmpty)
    }

    func testCancelAfterAcceptanceReturnsAcceptedAndKeepsNewerState() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        try await repository.applyMealPlanChange(userID: userID, change: original)
        repository.mockMealPlansByDateString.removeAll()
        let status = try await repository.resolveMealPlanChange(userID: userID, change: original, cancelPending: true)
        XCTAssertEqual(status, .accepted)
        XCTAssertTrue(repository.mockMealPlansByDateString.isEmpty)
    }

    func testReusedIdentityWithChangedPayloadRejectedForApplyStatusAndCancel() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        try await repository.applyMealPlanChange(userID: userID, change: original)
        var altered = original; altered.after[0].meals[0].instructions = "Altered payload under same save ID."
        await expectFailure { try await repository.applyMealPlanChange(userID: self.userID, change: altered) }
        await expectFailure { _ = try await repository.resolveMealPlanChange(userID: self.userID, change: altered, cancelPending: false) }
        await expectFailure { _ = try await repository.resolveMealPlanChange(userID: self.userID, change: altered, cancelPending: true) }
        XCTAssertEqual(repository.mockMealPlansByDateString[original.after[0].id]?.meals[0].instructions, "Cook.")
        XCTAssertEqual(repository.appliedMealPlanChangeIDs, [original.id])
    }

    func testWrongAccountCannotSubmitOrResolveAndDoesNotCreateReceipt() async throws {
        let repository = MockNutritionRepository(); repository.mealPlanChangeAccountID = userID
        let original = try change()
        await expectFailure { try await repository.applyMealPlanChange(userID: "other-user", change: original) }
        await expectFailure { _ = try await repository.resolveMealPlanChange(userID: "other-user", change: original, cancelPending: true) }
        XCTAssertTrue(repository.mealPlanChangeReceipts.isEmpty)
        XCTAssertTrue(repository.batchSavedMealPlans.isEmpty)
    }

    func testInvalidReceiptOwnerCannotPartiallyMutateMockPlans() async throws {
        let repository = MockNutritionRepository()
        let original = try change()
        await expectFailure { try await repository.applyMealPlanChange(userID: "", change: original) }
        XCTAssertTrue(repository.mockMealPlansByDateString.isEmpty)
        XCTAssertTrue(repository.batchSavedMealPlans.isEmpty)
        XCTAssertTrue(repository.mealPlanChangeReceipts.isEmpty)
    }

    private func linkedDays() throws -> [MealPlanDay] {
        let first = try day(0); let second = try day(7)
        let batch = MealCookingBatch(sourceMealID: "source", cookingDate: first.date, name: "Rice batch", totalPortions: 4,
            ingredientsPerPortion: [], instructions: "Cook once.", allocations: [
                MealCookingAllocation(mealID: "source", date: first.date, portions: 1),
                MealCookingAllocation(mealID: "leftover", date: second.date, portions: 1)
            ])
        return [try day(0, meals: [PlannedMeal(id: "source", mealType: "Dinner", cookingBatch: batch)]),
                try day(7, meals: [PlannedMeal(id: "leftover", mealType: "Lunch", cookingBatch: batch)])]
    }

    func testDiscardRechecksActualCrossWeekBatchAndLeavesAllStorageIntact() async throws {
        let repository = MockNutritionRepository()
        let linked = try linkedDays()
        for day in linked { repository.mockMealPlansByDateString[day.id] = day }
        let manual = GroceryListItem(name: "Manual addition", quantity: 1, unit: "item", source: "manual")
        repository.mockFetchGroceryListResult = [manual]
        let before = try PlanFingerprint.make(repository.mockMealPlansByDateString)
        await expectFailure {
            try await repository.discardMealPlans(userID: self.userID, dateStrings: [linked[0].id], retainingGroceryItems: [])
        }
        XCTAssertEqual(try PlanFingerprint.make(repository.mockMealPlansByDateString), before)
        XCTAssertEqual(repository.mockFetchGroceryListResult, [manual])
        XCTAssertTrue(repository.discardedMealPlanDateStrings.isEmpty)
    }

    func testDiscardWholeLinkedScopeKeepsLatestManualAndOtherWeekGroceries() async throws {
        let repository = MockNutritionRepository()
        let linked = try linkedDays()
        for day in linked { repository.mockMealPlansByDateString[day.id] = day }
        let manual = GroceryListItem(name: "Latest manual", quantity: 3, unit: "item", source: "manual")
        let barcode = GroceryListItem(name: "Scanned item", quantity: 1, unit: "bottle", source: "barcode")
        let target = GroceryListItem(name: "Target generated", quantity: 1, unit: "g", source: "mealPlan", sourcePlanStart: linked[0].date)
        let other = GroceryListItem(name: "Other week", quantity: 5, unit: "g", source: "mealPlan", sourcePlanStart: try day(14).date)
        repository.mockFetchGroceryListResult = [manual, target, barcode, other]
        try await repository.discardMealPlans(userID: userID, dateStrings: linked.map(\.id), retainingGroceryItems: [])
        XCTAssertTrue(repository.mockMealPlansByDateString.isEmpty)
        XCTAssertEqual(repository.mockFetchGroceryListResult, [manual, barcode, other])
    }

    func testDiscardCannotResurrectManualRowFromStalePreflightChecklist() async throws {
        let repository = MockNutritionRepository()
        let stale = GroceryListItem(name: "Deleted manually elsewhere", quantity: 1, unit: "item", source: "manual")
        try await repository.discardMealPlans(userID: userID, dateStrings: [try day(0).id], retainingGroceryItems: [stale])
        XCTAssertTrue(repository.mockFetchGroceryListResult.isEmpty)
        XCTAssertTrue(repository.savedGroceryLists.isEmpty)
    }
}
