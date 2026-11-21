import MyFitPlateCore
import XCTest
@testable import MyFitPlate

@MainActor
final class WaveOneFoodLoggingTests: XCTestCase {
    private var previousAuth: AuthServiceProtocol?
    private var previousNutrition: NutritionRepositoryProtocol?
    private var previousAnalytics: AnalyticsManagerProtocol?
    private var previousCrash: CrashManagerProtocol?
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: DailyLogService!
    private var model: FoodSearchViewModel!
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite = ""
    private var owner = ""

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService
        previousNutrition = DIContainer.shared.nutritionRepository
        previousAnalytics = DIContainer.shared.analyticsManager
        previousCrash = DIContainer.shared.crashManager
        owner = "wave-one-food-\(UUID().uuidString)"
        suite = "wave-one-food-defaults-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository(); repository.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repository
        DIContainer.shared.analyticsManager = MockAnalyticsManager()
        DIContainer.shared.crashManager = MockCrashManager()
        service = DailyLogService(undoStore: EditorDraftStore(directory: directory)); service.activateAccount(owner)
        model = makeModel()
    }

    override func tearDown() {
        service.activateAccount(nil)
        model = nil; service = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = previousAuth
        DIContainer.shared.nutritionRepository = previousNutrition
        DIContainer.shared.analyticsManager = previousAnalytics
        DIContainer.shared.crashManager = previousCrash
        super.tearDown()
    }

    private func makeModel() -> FoodSearchViewModel {
        let value = FoodSearchViewModel(selectedMeal: "Lunch", defaults: defaults,
                                        draftStore: EditorDraftStore(directory: directory))
        value.setup(dailyLogService: service)
        value.fetchData()
        value.isBuildingMeal = true
        return value
    }

    private var food: FoodItem {
        FoodItem(id: "provider-oats", name: "Oats", calories: 200, protein: 8, servingSize: "1 cup",
                 sourceMetadata: FoodSourceMetadata(sourceType: .aiChat, confidence: .estimated,
                    reviewStatus: .unreviewed, sourceID: "source-oats"), calcium: 100,
                 quantityValue: 1, servingUnit: "cup")
    }

    func testDirectPortionReviewPreservesNaturalAmountAndDoesNotRebaseAPIServings() {
        let grams = FoodItem(id: "usda-apple", name: "Apple", calories: 52, servingSize: "100 g", servingWeight: 100, calcium: 6)
        let preview = model.portionReviewFood(grams, source: "search_result")
        XCTAssertEqual(preview.quantityValue, 100)
        XCTAssertEqual(preview.servingUnit, "g")
        XCTAssertEqual(preview.calories, grams.calories)
        XCTAssertEqual(preview.calcium, grams.calcium)
        XCTAssertNil(grams.quantityValue, "Preparing a review must not mutate the source row")
        let base = ServingNutritionCalculator.baseServing(from: preview)
        XCTAssertEqual(base.calories * (preview.quantityValue ?? 0), grams.calories, accuracy: 0.0001)
        for (label, amount) in [("1.5 cups", 1.5), ("1 1/2 cups", 1.5), ("1/2 cup", 0.5), ("2 x cup", 2.0)] {
            var natural = grams; natural.servingSize = label
            let portion = model.portionReviewFood(natural, source: "recent_tap")
            XCTAssertEqual(portion.quantityValue, amount, label)
            XCTAssertEqual(ServingNutritionCalculator.baseServing(from: portion).calories * amount, grams.calories, accuracy: 0.0001, label)
        }
        var typed = grams; typed.servingUnit = "serving"
        XCTAssertNil(model.portionReviewFood(typed, source: "recent_tap").quantityValue,
                     "A conflicting typed unit cannot be reinterpreted from a natural label")
        var api = grams; api.id = "12345"
        XCTAssertNil(model.portionReviewFood(api, source: "search_result").quantityValue,
                     "Raw API-serving lookup retains its existing serving selection convention")
    }

    func testReviewedPortionKeepsCapturedDestinationAndProvenanceWithoutLogging() throws {
        let day = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())))
        service.activelyViewedDate = Date()
        model.selectedMeal = "Dinner"
        XCTAssertTrue(model.acceptReviewedMealFood(food, sourceID: food.id, userID: owner,
            draftID: nil, date: day, mealName: "Lunch"))
        let saved = try XCTUnwrap(model.mealDraft)
        XCTAssertEqual(saved.date, day)
        XCTAssertEqual(saved.mealName, "Lunch")
        XCTAssertEqual(saved.entries.first?.sourceID, food.id)
        XCTAssertEqual(saved.foods.first?.calcium, 100)
        XCTAssertEqual(saved.foods.first?.sourceMetadata?.confidence, .estimated)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
        XCTAssertTrue(repository.savedDailyLogs.isEmpty)
    }

    func testReviewedSelectedFoodRetainsConsumptionIdentityAndReplacesItsAmountOnce() throws {
        model.addToMealDraft(food)
        let before = try XCTUnwrap(model.mealDraft)
        var reviewed = try XCTUnwrap(FoodRepeatRules.adjusting(food, by: 1.5))
        reviewed.id = "portion-editor-presentation"
        XCTAssertTrue(model.acceptReviewedMealFood(reviewed, sourceID: food.id, userID: owner,
            draftID: before.id, date: Date(), mealName: "Dinner"))
        let after = try XCTUnwrap(model.mealDraft)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.entries.map(\.id), before.entries.map(\.id))
        XCTAssertEqual(after.entries.first?.sourceID, food.id)
        XCTAssertEqual(after.entries.first?.multiplier, 1)
        XCTAssertEqual(after.foods.first?.calories, 300)
        XCTAssertEqual(after.foods.first?.calcium, 150)
        XCTAssertEqual(after.date, before.date)
        XCTAssertEqual(after.mealName, before.mealName)
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
    }

    func testStaleReviewCannotCrossAccountsOrReplaceANewerDraft() throws {
        model.addToMealDraft(food)
        let original = try XCTUnwrap(model.mealDraft)
        auth.currentUserID = "other-owner"
        model.fetchData()
        XCTAssertFalse(model.acceptReviewedMealFood(food, sourceID: food.id, userID: owner,
            draftID: original.id, date: original.date, mealName: original.mealName))
        XCTAssertNil(model.mealDraft)
        auth.currentUserID = owner
        model.fetchData()
        XCTAssertEqual(model.mealDraft?.entries.map(\.id), original.entries.map(\.id))
        XCTAssertTrue(model.discardMealDraft())
        model.addToMealDraft(FoodItem(id: "new-food", name: "Milk", calories: 100))
        let newer = try XCTUnwrap(model.mealDraft)
        XCTAssertFalse(model.acceptReviewedMealFood(food, sourceID: food.id, userID: owner,
            draftID: original.id, date: original.date, mealName: original.mealName))
        XCTAssertEqual(model.mealDraft?.id, newer.id)
        XCTAssertEqual(model.mealDraft?.entries.map(\.sourceID), ["new-food"])
    }

    func testReviewOpenedBeforeAnotherSelectionCannotRetargetItsOriginalDestination() {
        model.addToMealDraft(FoodItem(id: "other-food", name: "Milk", calories: 100))
        XCTAssertFalse(model.acceptReviewedMealFood(food, sourceID: food.id, userID: owner,
            draftID: nil, date: Date(), mealName: "Dinner"))
        XCTAssertEqual(model.mealDraft?.mealName, "Lunch")
        XCTAssertEqual(model.mealDraft?.entries.map(\.sourceID), ["other-food"])
    }

    func testFailedMealSaveRemainsFrozenThroughPortionReviewAndRelaunch() async throws {
        let day = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())))
        XCTAssertTrue(model.acceptReviewedMealFood(food, sourceID: food.id, userID: owner,
            draftID: nil, date: day, mealName: "Lunch"))
        repository.updateLogSuccess = false
        let rejected = await withCheckedContinuation { continuation in model.logMealDraft { continuation.resume(returning: $0) } }
        XCTAssertFalse(rejected)
        let submitted = try XCTUnwrap(model.mealDraft)
        var altered = food; altered.calories = 999
        XCTAssertFalse(model.acceptReviewedMealFood(altered, sourceID: food.id, userID: owner,
            draftID: submitted.id, date: Date(), mealName: "Dinner"))
        service.activelyViewedDate = Date()
        model = makeModel()
        XCTAssertEqual(model.mealDraft?.foods.map(\.id), submitted.foods.map(\.id))
        repository.updateLogSuccess = true
        let accepted = await withCheckedContinuation { continuation in model.logMealDraft { continuation.resume(returning: $0) } }
        XCTAssertTrue(accepted)
        XCTAssertEqual(repository.lastUpdatedLog?.date, day)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.name, "Lunch")
        XCTAssertEqual(repository.lastUpdatedLog?.totalCalories(), 200)
    }

    func testRejectedLocalCheckpointDoesNotAcceptOrDiscardTheReviewedFood() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocked = directory.appendingPathComponent("blocked")
        try Data("keep this file".utf8).write(to: blocked)
        let value = FoodSearchViewModel(defaults: defaults, draftStore: EditorDraftStore(directory: blocked))
        value.setup(dailyLogService: service); value.fetchData()
        XCTAssertFalse(value.acceptReviewedMealFood(food, sourceID: food.id, userID: owner,
            draftID: nil, date: Date(), mealName: "Lunch"))
        XCTAssertNil(value.mealDraft)
        XCTAssertEqual(try String(contentsOf: blocked), "keep this file")
        XCTAssertTrue(repository.dailyLogUpdateUserIDs.isEmpty)
    }
}
