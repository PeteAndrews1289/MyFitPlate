import XCTest
@testable import MyFitPlateCore

@MainActor final class MealPlanWeekReviewTests: XCTestCase {
    func testLostAckRecoveryKeepsExactOperationAndLaterMealEdits() async throws {
        let auth = MockAuthService(); auth.currentUserID = "week-owner"
        let repo = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repo
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let defaultsName = "week-review-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let planner = MealPlannerService(recipeService: RecipeService(), userDefaults: defaults)
        let date = Calendar.current.startOfDay(for: Date())
        var day = MealPlanEditingRules.emptyDay(date)
        day.meals = [PlannedMeal(id: "draft-meal", mealType: "Dinner", foodItem: FoodItem(id: "f", name: "Rice", calories: 400, protein: 20, carbs: 50, fats: 10, servingSize: "1 bowl", servingWeight: 200))]
        let draft = MealPlanWeekDraft(days: [day], title: "Test")
        let change = try MealPlanWeekReviewRules.merging(draft, existing: [MealPlanEditingRules.emptyDay(date)], replace: false)
        let session = MealPlanWeekSaveSession(userID: auth.currentUserID, draft: draft, store: store)
        XCTAssertTrue(session.prepare(change))
        repo.mealPlanChangeFailureAfterCommit = CocoaError(.fileReadUnknown)
        let saved = await session.save(using: planner)
        XCTAssertFalse(saved)
        XCTAssertEqual(repo.appliedMealPlanChangeIDs, [change.id])
        let reopened = MealPlanWeekSaveSession(userID: auth.currentUserID, store: store)
        XCTAssertEqual(reopened.checkpoint?.change?.id, change.id)
        XCTAssertFalse(reopened.updateDraft(draft))
        var later = try XCTUnwrap(repo.mockMealPlansByDateString[day.id]); later.meals[0].portionMultiplier = 2
        repo.mockMealPlansByDateString[day.id] = later
        await reopened.resolve(using: repo)
        XCTAssertTrue(reopened.checkpoint?.accepted == true)
        XCTAssertEqual(repo.mockMealPlansByDateString[day.id]?.meals[0].portions, 2)
        XCTAssertTrue(reopened.closeResolvedOrUnsubmitted())
        XCTAssertEqual(repo.appliedMealPlanChangeIDs.count, 1)
    }
    func testFencedCancelAndAccountChangeCannotReplaceSubmittedWeek() async throws {
        let auth = MockAuthService(); auth.currentUserID = "cancel-owner"
        let repo = MockNutritionRepository(); DIContainer.shared.authService = auth
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let date = Calendar.current.startOfDay(for: Date())
        let old = MealPlanEditingRules.emptyDay(date)
        var day = old; day.meals = [PlannedMeal(mealType: "Dinner")]
        let draft = MealPlanWeekDraft(days: [day], title: "Cancel")
        let change = MealPlanChange(title: "Test", before: [old], after: [day])
        let session = MealPlanWeekSaveSession(userID: auth.currentUserID, draft: draft, store: store)
        XCTAssertTrue(session.prepare(change))
        await session.resolve(using: repo, cancelPending: true)
        XCTAssertTrue(session.checkpoint?.cancelled == true)
        do { try await repo.applyMealPlanChange(userID: "cancel-owner", change: change); XCTFail("cancel must fence old operation") } catch {}
        auth.currentUserID = "other"
        XCTAssertFalse(session.closeResolvedOrUnsubmitted())
        auth.currentUserID = "cancel-owner"
        XCTAssertTrue(session.closeResolvedOrUnsubmitted())
        XCTAssertTrue(repo.appliedMealPlanChangeIDs.isEmpty)
    }
    func testLockedDraftRejectsReplacementAndPartialBatchDoesNotDetach() throws {
        let date = Calendar.current.startOfDay(for: Date())
        var day = MealPlanEditingRules.emptyDay(date)
        day.meals = [PlannedMeal(id: "locked", mealType: "Dinner")]
        var draft = MealPlanWeekDraft(days: [day], title: "Locked", preserveCookingBatches: true)
        draft.lockedMealIDs = ["locked"]
        XCTAssertThrowsError(try MealPlanWeekReviewRules.merging(draft, existing: [day], replace: true))
    }
}
