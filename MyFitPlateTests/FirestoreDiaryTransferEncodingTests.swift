import FirebaseFirestore
import MyFitPlateCore
import XCTest

final class FirestoreDiaryTransferEncodingTests: XCTestCase {
    func testSkipAuditSurvivesDailyLogFirestoreEncodingWithoutChangingSourceReview() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let original = FoodItem(id: "skip-food", name: "Rice", calories: 600, protein: 20, carbs: 100, fats: 10,
            servingSize: "300 g", servingWeight: 300,
            sourceMetadata: .init(sourceType: .aiImage, confidence: .estimated, reviewStatus: .unreviewed, createdAt: date))
        let question = try XCTUnwrap(UsefulMealQuestionRules.choose(items: [original], evidence: [
            .init(itemID: original.id, lowGrams: 150, highGrams: 450)
        ], loggedCalories: nil, calorieGuide: nil))
        let skipped = try XCTUnwrap(UsefulMealQuestionRules.preview(answer: .skip, question: question, item: original, now: date.addingTimeInterval(0.123456)))
        let diary = DailyLog(date: date, meals: [Meal(name: "Lunch", foodItems: [skipped.food])])
        let payload = try Firestore.Encoder().encode(diary)
        let restored = try Firestore.Decoder().decode(DailyLog.self, from: payload)
        let food = try XCTUnwrap(restored.meals.first?.foodItems.first)
        XCTAssertEqual(food.id, original.id); XCTAssertEqual(food.calories, original.calories)
        XCTAssertEqual(food.sourceMetadata, original.sourceMetadata)
        let receipt = try XCTUnwrap(food.savedPortionQuestionReceipt)
        XCTAssertEqual(receipt.answer, .skip); XCTAssertEqual(receipt.originalFoodData, receipt.revisedFoodData)
        XCTAssertEqual(receipt, skipped.receipt)
        XCTAssertNotEqual(try PlanFingerprint.make(food), try PlanFingerprint.make(original), "The full payload fingerprint includes the new audit.")
    }

    func testAcceptedTransferReceiptRetainsFingerprintAndExactFoodPreconditionsThroughFirestoreCoding() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(DiaryDayContext(userID: "encoding-owner",
            date: Date(timeIntervalSince1970: 1_700_000_000.123456), timeZone: zone))
        let next = try XCTUnwrap(day.adding(days: 1))
        let food = FoodItem(id: "historical-food", name: "Oats", calories: 200, protein: 8, carbs: 30, fats: 5,
                            servingSize: "2 x cup", servingWeight: 200,
                            timestamp: Date(timeIntervalSince1970: 1_699_990_000.987654),
                            sourceMetadata: .userEntered(sourceName: "Original label"), calcium: 140,
                            quantityValue: 2, servingUnit: "cup")
        let source = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Breakfast", foodItems: [food])])
        let destination = DailyLog(id: next.dayKey, date: next.originalDate, meals: [])
        let draft = try DiaryTransferDraft(source: day, destination: next, sourceLog: source, mode: .move)
        let command = try draft.freeze()
        let accepted = try DiaryTransferRules.apply(command, source: source, destination: destination)
        let envelope = try DiaryTransferReceiptEnvelope(receipt: accepted.receipt)
        let receiptData = try Firestore.Encoder().encode(envelope)
        let storedEnvelope = try Firestore.Decoder().decode(DiaryTransferReceiptEnvelope.self, from: receiptData)
        XCTAssertEqual(storedEnvelope.payload, envelope.payload, "Firestore must preserve the opaque receipt bytes exactly")
        let restored = try storedEnvelope.receipt(matching: command)
        try restored.validate()
        XCTAssertEqual(restored.commandFingerprint, try command.fingerprint())
        XCTAssertEqual(restored.command.source.originalDate, day.originalDate)
        XCTAssertTrue(FoodEditPrecondition.sameSnapshot(try XCTUnwrap(restored.placements.first?.destinationFood), food))
        XCTAssertEqual(restored.placements.first?.destinationFood.timestamp, food.timestamp)
    }

    func testCopyReceiptRetainsFreshIdentityAndStructuredPortionThroughFirestoreCoding() throws {
        let day = try XCTUnwrap(DiaryDayContext(userID: "encoding-owner", date: Date(timeIntervalSince1970: 1_700_000_000)))
        let food = FoodItem(id: "original", name: "Rice", calories: 200, servingSize: "2 x cup", quantityValue: 2, servingUnit: "cup")
        let source = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Lunch", foodItems: [food])])
        var draft = try DiaryTransferDraft(source: day, destination: day, sourceLog: source, mode: .copy)
        draft.entries[0].multiplier = 0.5
        let command = try draft.freeze(now: Date(timeIntervalSince1970: 1_700_000_000.123456))
        let accepted = try DiaryTransferRules.apply(command,
                                                    source: source, destination: source)
        let envelope = try DiaryTransferReceiptEnvelope(receipt: accepted.receipt)
        let restoredEnvelope = try Firestore.Decoder().decode(DiaryTransferReceiptEnvelope.self, from: Firestore.Encoder().encode(envelope))
        let restored = try restoredEnvelope.receipt(matching: command)
        try restored.validate()
        let copy = try XCTUnwrap(restored.placements.first?.destinationFood)
        XCTAssertNotEqual(copy.id, food.id)
        XCTAssertEqual(copy.quantityValue, 1)
        XCTAssertEqual(copy.calories, 100)
        XCTAssertEqual(restored.commandFingerprint, accepted.receipt.commandFingerprint)
        XCTAssertEqual(copy.timestamp?.timeIntervalSince1970, 1_700_000_000)
        let writtenMeal = try Firestore.Decoder().decode(DailyLog.self, from: Firestore.Encoder().encode(accepted.destinationLog))
        let undone = try DiaryTransferRules.undo(restored, source: writtenMeal, destination: writtenMeal)
        XCTAssertEqual(undone.destinationLog.meals.flatMap(\.foodItems).map(\.id), [food.id])
    }

    func testCancellationEnvelopeKeepsVersionAndFingerprintAcrossFirestoreCoding() throws {
        let day = try XCTUnwrap(DiaryDayContext(userID: "encoding-owner", date: Date(timeIntervalSince1970: 1_700_000_000.123456)))
        let food = FoodItem(id: "original", name: "Rice", calories: 200)
        let source = DailyLog(id: day.dayKey, date: day.originalDate, meals: [Meal(name: "Lunch", foodItems: [food])])
        let command = try DiaryTransferDraft(source: day, destination: day, sourceLog: source, mode: .copy).freeze()
        let envelope = try DiaryTransferReceiptEnvelope(cancellation: DiaryTransferCancellation(command: command))
        let stored = try Firestore.Decoder().decode(DiaryTransferReceiptEnvelope.self, from: Firestore.Encoder().encode(envelope))
        XCTAssertEqual(stored.payload, envelope.payload)
        XCTAssertEqual(try stored.cancellation(matching: command).commandFingerprint, try command.fingerprint())
        XCTAssertThrowsError(try stored.receipt(matching: command))
    }
}
