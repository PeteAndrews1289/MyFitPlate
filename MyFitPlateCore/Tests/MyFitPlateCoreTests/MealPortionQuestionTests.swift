import XCTest
@testable import MyFitPlateCore

final class MealPortionQuestionTests: XCTestCase {
    private func food() -> FoodItem {
        var value = FoodItem(id: "rice", name: "Rice", calories: 600, protein: 30, carbs: 90, fats: 12,
            servingSize: "300 g", servingWeight: 300, iron: 8, sodium: 500)
            .withAIEstimateSource(.aiImage, sourceName: "Photo estimate")
        value.sourceMetadata?.portionAnchors = [.init(unit: .package, gramsPerUnit: 450, sourceID: "label", sourceName: "Package label")]
        return value
    }
    private func question(_ item: FoodItem, uncertainty: MealQuestionUncertainty = .portion) throws -> UsefulMealQuestion {
        try XCTUnwrap(UsefulMealQuestionRules.choose(items: [item], evidence: [
            .init(itemID: item.id, lowGrams: 150, highGrams: 450, anchors: item.sourceMetadata?.portionAnchors ?? [],
                  uncertainty: uncertainty, canUseMeasuredGrams: false)
        ], loggedCalories: nil, calorieGuide: nil))
    }

    func testAccuratePackageAnswerReducesErrorAndKeepsAllOriginalNutrients() throws {
        let item = food(), expectedTrueGrams = 225.0
        let preview = try XCTUnwrap(UsefulMealQuestionRules.preview(answer: .anchor(index: 0, count: 0.5), question: question(item), item: item))
        XCTAssertLessThan(abs(preview.food.servingWeight - expectedTrueGrams), abs(item.servingWeight - expectedTrueGrams))
        XCTAssertEqual(preview.food.calories, 450)
        XCTAssertEqual(preview.food.iron, 6); XCTAssertEqual(preview.food.sodium, 375)
        XCTAssertEqual(try PlanFingerprint.make(preview.receipt.originalFood), try PlanFingerprint.make(item))
        XCTAssertEqual(preview.receipt.revisedFood?.servingWeight, expectedTrueGrams)
        XCTAssertEqual(preview.food.portionQuestionReceipt, preview.receipt)
        XCTAssertEqual(preview.food.sourceMetadata?.confidence, .estimated)
        let restored = try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(preview.food))
        XCTAssertEqual(restored.portionQuestionReceipt?.answer, .anchor(index: 0, count: 0.5))
    }

    func testSkipLeavesExactOriginalPayloadAndDoesNotAttachFalseCorrection() throws {
        let item = food()
        let preview = try XCTUnwrap(UsefulMealQuestionRules.preview(answer: .skip, question: question(item), item: item))
        var originalFields = preview.food; originalFields.portionQuestionReceipt = nil
        XCTAssertEqual(try PlanFingerprint.make(originalFields), try PlanFingerprint.make(item))
        XCTAssertEqual(preview.food.portionQuestionReceipt?.answer, .skip)
        XCTAssertEqual(preview.food.sourceMetadata, item.sourceMetadata)
        XCTAssertEqual(preview.receipt.originalFoodData, preview.receipt.revisedFoodData)
    }

    func testStaleNutritionOrIdentityCannotReuseQuestion() throws {
        let item = food(), prompt = try question(item)
        var changed = item; changed.calories += 100
        XCTAssertEqual(changed, item, "FoodItem equality is identity-only; question must check the whole payload.")
        XCTAssertNil(UsefulMealQuestionRules.preview(answer: .anchor(index: 0, count: 1), question: prompt, item: changed))
        changed = item; changed.id = "other"
        XCTAssertNil(UsefulMealQuestionRules.preview(answer: .skip, question: prompt, item: changed))
    }

    func testAnswerableRangeWinsOverLargerUnknownPreparationAndNoMeasureSuppressesPrompt() throws {
        let measured = food()
        var unknown = food(); unknown.id = "mixed"; unknown.calories = 1_200
        let prompt = UsefulMealQuestionRules.choose(items: [measured, unknown], evidence: [
            .init(itemID: unknown.id, lowGrams: 100, highGrams: 600, uncertainty: .unresolvedPreparation),
            .init(itemID: measured.id, lowGrams: 150, highGrams: 450, anchors: measured.sourceMetadata?.portionAnchors ?? [], canUseMeasuredGrams: false)
        ], loggedCalories: nil, calorieGuide: nil)
        XCTAssertEqual(prompt?.itemID, measured.id)
        XCTAssertNil(UsefulMealQuestionRules.choose(items: [measured], evidence: [
            .init(itemID: measured.id, lowGrams: 150, highGrams: 450, canUseMeasuredGrams: false)
        ], loggedCalories: nil, calorieGuide: nil))
    }

    func testReferenceAnchorsRequireResolvedSourceAndExactServingDescription() {
        for (serving, expected) in [("1 cup (150 g)", MealPortionAnchor.Unit.cup), ("1 tbsp", .tablespoon), ("1 package", .package), ("1 tsp", .teaspoon), ("1 piece", .piece)] {
            let resolved = FoodItem(name: "Reference", calories: 200, servingSize: serving, servingWeight: 150)
                .withDatabaseSource(.usda, sourceName: "USDA", sourceID: "reference")
            XCTAssertEqual(MealPortionAnchorRules.referenceAnchors(for: resolved).first?.unit, expected)
            XCTAssertTrue(MealPortionAnchorRules.referenceAnchors(for: resolved.withAIEstimateSource(.aiImage, sourceName: "Photo")).isEmpty)
        }
        let mismatch = FoodItem(name: "Reference", servingSize: "1 cup (150 g)", servingWeight: 200)
            .withDatabaseSource(.usda, sourceName: "USDA")
        XCTAssertTrue(MealPortionAnchorRules.referenceAnchors(for: mismatch).isEmpty)
        for text in ["large bowl", "1 cup approximately", "2 cups", "1 serving", "half package"] {
            let value = FoodItem(name: "Unknown", servingSize: text, servingWeight: 150).withDatabaseSource(.usda, sourceName: "USDA")
            XCTAssertTrue(MealPortionAnchorRules.referenceAnchors(for: value).isEmpty)
        }
    }

    func testSeparateOilScalesOnlyThatComponentAndUnknownMixedPreparationIsNotAdded() throws {
        var oil = FoodItem(id: "oil", name: "Olive oil", calories: 180, protein: 0, carbs: 0, fats: 20,
            servingSize: "20 g", servingWeight: 20).withAIEstimateSource(.aiImage, sourceName: "Photo")
        oil.sourceMetadata?.portionAnchors = [.init(unit: .tablespoon, gramsPerUnit: 14, sourceID: "oil-reference", sourceName: "Resolved oil serving")]
        let prompt = try XCTUnwrap(UsefulMealQuestionRules.choose(items: [oil], evidence: [
            .init(itemID: oil.id, lowGrams: 10, highGrams: 40, anchors: oil.sourceMetadata?.portionAnchors ?? [], uncertainty: .separateCookingAddition, canUseMeasuredGrams: false)
        ], loggedCalories: nil, calorieGuide: nil))
        let changed = try XCTUnwrap(UsefulMealQuestionRules.preview(answer: .anchor(index: 0, count: 1), question: prompt, item: oil))
        XCTAssertEqual(changed.food.id, "oil"); XCTAssertEqual(changed.food.fats, 14); XCTAssertEqual(changed.food.calories, 126, accuracy: 0.001)
        XCTAssertNil(UsefulMealQuestionRules.choose(items: [oil], evidence: [
            .init(itemID: oil.id, lowGrams: 10, highGrams: 40, anchors: oil.sourceMetadata?.portionAnchors ?? [], uncertainty: .unresolvedPreparation)
        ], loggedCalories: nil, calorieGuide: nil))
    }

    func testOnlyExactSeparatelyNamedOilUsesCookingAdditionTransformation() {
        var oil = food(); oil.name = "Olive oil"
        XCTAssertEqual(MealQuestionUncertaintyRules.kind(for: oil, hasUnresolvedPreparation: true), .separateCookingAddition)
        var mixed = oil; mixed.name = "Fried rice with olive oil"
        XCTAssertEqual(MealQuestionUncertaintyRules.kind(for: mixed, hasUnresolvedPreparation: true), .portion)
        mixed.sourceMetadata?.portionAnchors = nil
        XCTAssertEqual(MealQuestionUncertaintyRules.kind(for: mixed, hasUnresolvedPreparation: true), .unresolvedPreparation)
        oil.sourceMetadata?.portionAnchors = nil
        XCTAssertEqual(MealQuestionUncertaintyRules.kind(for: oil, hasUnresolvedPreparation: true), .unresolvedPreparation)
    }

    func testInvalidAnswersAndExtremeScalingCannotProduceNutrition() throws {
        let item = food(), prompt = try question(item)
        for answer in [MealQuestionAnswer.anchor(index: -1, count: 1), .anchor(index: 9, count: 1), .anchor(index: 0, count: .nan),
                       .anchor(index: 0, count: 99), .measuredGrams(300)] {
            XCTAssertNil(UsefulMealQuestionRules.preview(answer: answer, question: prompt, item: item))
        }
        for grams in [0, -1, .nan, .infinity, 100_001, 1, 9_000] {
            XCTAssertNil(UsefulMealQuestionRules.applying(grams: grams, to: item))
        }
        var broken = item; broken.iron = .infinity
        XCTAssertNil(UsefulMealQuestionRules.applying(grams: 225, to: broken))
    }
}

@MainActor final class MealPortionQuestionPersistenceTests: XCTestCase {
    private var auth: MockAuthService!
    private var previousAuth: AuthServiceProtocol!
    private var repository: MockNutritionRepository!
    private var previousRepository: NutritionRepositoryProtocol!
    private var service: DailyLogService!
    private var directory: URL!
    private var disk: EditorDraftStore!
    private let owner = "portion-question-owner"
    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository(); repository.persistsDailyLogUpdates = true
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("portion-question-\(UUID())")
        disk = EditorDraftStore(directory: directory)
        service = DailyLogService(undoStore: disk); service.activateAccount(owner)
    }
    override func tearDown() {
        service.activateAccount(nil); service = nil
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    private func review() throws -> MealReviewSaveSession {
        let item = FoodItem(id: "original", name: "Rice", calories: 600, protein: 20, carbs: 100, fats: 10, servingWeight: 300)
        let day = Calendar.current.startOfDay(for: Date())
        let review = MealReviewSaveSession(items: [item], userID: owner, date: day, mealName: "Lunch", source: "portion-test", store: disk)
        if review.checkpoint.portionQuestion == nil {
            let prompt = try XCTUnwrap(UsefulMealQuestionRules.choose(items: review.items, evidence: [
                .init(itemID: item.id, lowGrams: 150, highGrams: 450)
            ], loggedCalories: nil, calorieGuide: nil))
            XCTAssertTrue(review.offerPortionQuestion(prompt))
        }
        return review
    }
    private func save(_ review: MealReviewSaveSession) async -> Bool {
        await withCheckedContinuation { continuation in review.save(using: service) { continuation.resume(returning: $0) } }
    }

    func testAcceptedAnswerSurvivesRelaunchAndSubmittedRetryKeepsOneExactReceipt() async throws {
        let session = try review(), before = session.checkpoint.draft.entries[0].id
        XCTAssertTrue(session.answerPortionQuestion(.measuredGrams(225)))
        XCTAssertFalse(session.answerPortionQuestion(.measuredGrams(450)))
        let restored = try review()
        XCTAssertEqual(restored.items.first?.servingWeight, 225)
        XCTAssertEqual(restored.checkpoint.portionQuestion?.receipt?.originalFood?.servingWeight, 300)
        XCTAssertEqual(restored.checkpoint.draft.entries[0].id, before)
        repository.updateLogSuccess = false
        let failed = await save(restored); XCTAssertFalse(failed)
        XCTAssertFalse(restored.answerPortionQuestion(.skip))
        repository.updateLogSuccess = true
        let retry = try review(), accepted = await save(retry)
        XCTAssertTrue(accepted, retry.errorMessage ?? "No error")
        XCTAssertEqual(repository.lastUpdatedLog?.meals.flatMap(\.foodItems).count, 1)
        XCTAssertEqual(repository.lastUpdatedLog?.meals.first?.foodItems.first?.portionQuestionReceipt?.answer, .measuredGrams(225))
    }

    func testDiskFailureRollsBackAnswerAndOriginalEstimateThenCanRetry() throws {
        let session = try review(), before = try PlanFingerprint.make(session.items)
        let backup = directory.appendingPathExtension("saved")
        defer { try? FileManager.default.removeItem(at: backup) }
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("not a directory".utf8).write(to: directory)
        XCTAssertFalse(session.answerPortionQuestion(.measuredGrams(225)))
        XCTAssertEqual(try PlanFingerprint.make(session.items), before)
        XCTAssertNil(session.checkpoint.portionQuestion?.receipt)
        try FileManager.default.removeItem(at: directory); try FileManager.default.moveItem(at: backup, to: directory)
        XCTAssertTrue(session.answerPortionQuestion(.measuredGrams(225)))
    }

    func testSkipIsDurableAndCrossAccountCannotAnswer() throws {
        let session = try review(), before = try PlanFingerprint.make(session.items)
        auth.currentUserID = "other"
        XCTAssertFalse(session.answerPortionQuestion(.measuredGrams(225)))
        XCTAssertEqual(try PlanFingerprint.make(session.items), before)
        auth.currentUserID = owner
        XCTAssertTrue(session.answerPortionQuestion(.skip))
        let restored = try review()
        XCTAssertEqual(restored.checkpoint.portionQuestion?.receipt?.answer, .skip)
        var originalItems = restored.items
        for index in originalItems.indices { originalItems[index].portionQuestionReceipt = nil }
        XCTAssertEqual(try PlanFingerprint.make(originalItems), before)
    }

    func testAcceptedSkipKeepsOriginalNutritionAndDurableAuditAfterDiaryReload() async throws {
        let session = try review(), original = try XCTUnwrap(session.items.first)
        XCTAssertTrue(session.answerPortionQuestion(.skip))
        let accepted = await save(session)
        XCTAssertTrue(accepted, session.errorMessage ?? "No error")
        let day = try XCTUnwrap(session.checkpoint.draft.dayContext)
        let persisted: DailyLog = try await withCheckedThrowingContinuation { continuation in
            repository.fetchLogInternal(userID: owner, date: day.originalDate) { continuation.resume(with: $0) }
        }
        let saved = try XCTUnwrap(persisted.meals.first?.foodItems.first)
        XCTAssertEqual(saved.calories, original.calories); XCTAssertEqual(saved.servingWeight, original.servingWeight)
        let receipt = try XCTUnwrap(saved.portionQuestionReceipt)
        XCTAssertEqual(receipt.answer, .skip)
        XCTAssertEqual(try PlanFingerprint.make(receipt.originalFood), try PlanFingerprint.make(original))
        XCTAssertEqual(receipt.originalFoodData, receipt.revisedFoodData)
        XCTAssertNil(MealReviewSaveSession.pendingReview(source: "portion-test", userID: owner, store: disk))
    }
}
