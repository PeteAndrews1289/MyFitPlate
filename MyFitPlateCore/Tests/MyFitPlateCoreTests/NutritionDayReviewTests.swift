import XCTest
@testable import MyFitPlateCore

final class NutritionDayReviewTests: XCTestCase {
    private let owner = "day-review-owner"
    private func log() -> DailyLog {
        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(-172_800))
        return DailyLog(id: DiaryDayContext.dayKey(for: date), date: date,
            meals: [Meal(name: "Lunch", foodItems: [FoodItem(id: "rice", name: "Rice", calories: 200, protein: 5, carbs: 40, fats: 1)])])
    }
    private func reviewed(_ original: DailyLog, status: NutritionDayStatus = .complete) throws -> DailyLog {
        var value = original.rememberingMutationBase()
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: value.date, dayKey: value.id))
        value.nutritionDayReview = try .init(ownerID: owner, day: day, status: status, log: original)
        value.nutritionDayStatus = status
        return value
    }
    func testNewReceiptUsesExactSecondsWhileLegacyDecodeRetainsItsOriginalTimestamp() throws {
        let original = log()
        let day = try XCTUnwrap(DiaryDayContext(userID: owner, date: original.date, dayKey: original.id))
        let exact = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let subsecond = exact.addingTimeInterval(0.1234567)
        let receipt = try NutritionDayReview(ownerID: owner, day: day, status: .complete, log: original, at: subsecond)
        XCTAssertEqual(receipt.reviewedAt, exact)
        XCTAssertEqual(try JSONDecoder().decode(NutritionDayReview.self, from: JSONEncoder().encode(receipt)), receipt)
        var legacyData = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        legacyData["reviewedAt"] = subsecond.timeIntervalSinceReferenceDate
        let legacy = try JSONDecoder().decode(NutritionDayReview.self, from: JSONSerialization.data(withJSONObject: legacyData))
        XCTAssertEqual(legacy.reviewedAt, subsecond, "Decoding must not migrate or rewrite an existing assertion")
        XCTAssertNotEqual(legacy, receipt, "The equality used for checked saves remains exact")
        var first = original; first.nutritionDayStatus = .complete; first.nutritionDayReview = receipt
        var second = first; second.nutritionDayReview = legacy
        XCTAssertFalse(NutritionDayReviewRules.sameReviewedState(first, second))
    }
    func testReviewBindsExactIntakeWhileWaterAndActivityStayIndependent() throws {
        let original = log(), accepted = try reviewed(original)
        XCTAssertTrue(NutritionDayEvidence.isComplete(accepted))
        var water = accepted; water.waterTracker = WaterTracker(totalOunces: 12, goalOunces: 64, date: water.date)
        XCTAssertTrue(NutritionDayEvidence.isComplete(water))
        var edited = water; edited.meals[0].foodItems[0].calories = 350
        XCTAssertEqual(NutritionDayEvidence.status(of: edited), .unknown)
        XCTAssertFalse(NutritionDayEvidence.isComplete(edited))
        XCTAssertEqual(edited.nutritionDayReview, accepted.nutritionDayReview, "Keep the actual earlier assertion for explanation")
        XCTAssertEqual(edited.nutritionDayStatus, .complete)
    }
    func testStaleReviewCannotAttestConcurrentFoodOrOverwriteAnotherReview() throws {
        let original = log(), proposal = try reviewed(original)
        let mutation = try DailyLogMutation(userID: owner, log: proposal)
        var newerFood = original; newerFood.meals[0].foodItems.append(FoodItem(id: "later", name: "Later", calories: 100))
        XCTAssertThrowsError(try mutation.applying(to: newerFood, checkingFoodEdits: true))
        let otherReview = try reviewed(original, status: .partial)
        XCTAssertThrowsError(try mutation.applying(to: otherReview, checkingFoodEdits: true))
        var independent = original; independent.waterTracker = WaterTracker(totalOunces: 9, goalOunces: 64, date: independent.date)
        let saved = try mutation.applying(to: independent, checkingFoodEdits: true)
        XCTAssertEqual(saved.waterTracker?.totalOunces, 9)
        XCTAssertEqual(saved.nutritionDayReview, proposal.nutritionDayReview)
    }
    func testAcceptedReplayKeepsLaterFoodAndCannotReattestIt() throws {
        let original = log(), mutation = try DailyLogMutation(userID: owner, log: reviewed(original))
        var accepted = try mutation.applying(to: original, checkingFoodEdits: true)
        accepted.meals[0].foodItems[0].carbs = 70
        let replay = try mutation.applying(to: accepted, checkingFoodEdits: true)
        XCTAssertEqual(replay.meals[0].foodItems[0].carbs, 70)
        XCTAssertEqual(NutritionDayEvidence.status(of: replay), .unknown)
        XCTAssertEqual(replay.appliedMutationIDs?.filter { $0 == mutation.id }.count, 1)
    }
    func testReviewUndoRestoresEarlierAssertionOnlyIfItsEvidenceStillMatches() throws {
        let original = log(), after = try reviewed(original)
        let receipt = DiaryUndoReceipt(id: UUID(), userID: owner, before: original, after: after, expiresAt: Date().addingTimeInterval(30), isSubmitted: false)
        let inverse = try receipt.reversal()
        let undone = try inverse.applying(to: after, checkingFoodEdits: true)
        XCTAssertNil(undone.nutritionDayReview); XCTAssertNil(undone.nutritionDayStatus)
        var newer = after; newer.meals[0].foodItems[0].calories = 250
        XCTAssertThrowsError(try inverse.applying(to: newer, checkingFoodEdits: true))
    }
    func testUndoNewReviewCanRestoreExactEarlierStaleAssertionWithoutAttestingCurrentFood() throws {
        var old = try reviewed(log())
        old.meals[0].foodItems[0].calories = 260
        XCTAssertEqual(NutritionDayEvidence.status(of: old), .unknown)
        let new = try reviewed(old)
        let inverse = try DiaryUndoReceipt(id: UUID(), userID: owner, before: old, after: new, expiresAt: Date().addingTimeInterval(30), isSubmitted: false).reversal()
        XCTAssertEqual(inverse.dayReviewUndo, true)
        let restored = try inverse.applying(to: new, checkingFoodEdits: true)
        XCTAssertEqual(restored.nutritionDayReview, old.nutritionDayReview)
        XCTAssertEqual(restored.meals[0].foodItems[0].calories, 260)
        XCTAssertEqual(NutritionDayEvidence.status(of: restored), .unknown)
        var untyped = old; untyped.mutationBase = try JSONEncoder().encode(new)
        let ordinary = try DailyLogMutation(userID: owner, log: untyped)
        XCTAssertThrowsError(try ordinary.applying(to: new, checkingFoodEdits: true))
    }

    func testOnlyAReviewChangeNeedsCheckedCommitAndLegacyDeclarationsRemainReadable() throws {
        let original = log(), after = try reviewed(original)
        XCTAssertTrue(NutritionDayReviewRules.requiresCheckedCommit(after))
        var food = after.rememberingMutationBase(); food.meals[0].foodItems.append(FoodItem(id: "more", name: "Food", calories: 100))
        XCTAssertFalse(NutritionDayReviewRules.requiresCheckedCommit(food), "Ordinary logging retains its existing offline save route")
        var legacy = original; legacy.nutritionDayStatus = .complete
        let decoded = try JSONDecoder().decode(DailyLog.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.nutritionDayReview); XCTAssertTrue(NutritionDayEvidence.isComplete(decoded))
        let restored = try JSONDecoder().decode(DailyLog.self, from: JSONEncoder().encode(after))
        XCTAssertEqual(restored.nutritionDayReview, after.nutritionDayReview)
    }
    func testCanonicalDaySurvivesRemoteMidnightAndAdjacentEmptyDaysAreDifferent() throws {
        var remote = Calendar(identifier: .gregorian); remote.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        var local = Calendar(identifier: .gregorian); local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let remoteMidnight = try XCTUnwrap(remote.date(from: DateComponents(year: 2026, month: 11, day: 4)))
        let localToday = try XCTUnwrap(local.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12)))
        let original = DailyLog(id: "2026-11-04", date: remoteMidnight, meals: [])
        let previous = DailyLog(id: "2026-11-03", date: remoteMidnight, meals: [])
        XCTAssertFalse(NutritionDayReviewRules.sameReviewedState(original, previous))
        let page = NutritionDayReviewRules.page([original], through: localToday, count: 2, now: localToday, calendar: local)
        XCTAssertEqual(page[0].id, "2026-11-04"); XCTAssertEqual(page[0].date, remoteMidnight)
        XCTAssertEqual(local.component(.day, from: NutritionDayReviewRules.displayDate(page[0], calendar: local)), 4)
        XCTAssertEqual(page[1].id, "2026-11-03")
    }

    func testPagedSparseDaysIncludeEveryDayOnceAcrossDSTWithoutInventingIntake() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4)))
        let page = NutritionDayReviewRules.page([], through: end, count: 30, now: end, calendar: calendar)
        XCTAssertEqual(page.count, 30); XCTAssertEqual(Set(page.map(\.id)).count, 30)
        XCTAssertTrue(page.allSatisfy { !NutritionDayEvidence.isComplete($0, now: end, calendar: calendar) })
        let priorEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: -30, to: end))
        let previous = NutritionDayReviewRules.page([], through: priorEnd, count: 30, now: end, calendar: calendar)
        XCTAssertTrue(Set(page.map(\.id)).isDisjoint(with: Set(previous.map(\.id))))
    }
}
