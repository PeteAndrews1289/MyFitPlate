import XCTest
@testable import MyFitPlateCore

final class MaiaStreamContinuityTests: XCTestCase {
    func testStreamKeepsDraftSeparateAndAcceptsLegacyFinalWithoutMetadata() throws {
        let id = UUID()
        var decoder = MaiaStreamDecoder(requestID: id)
        XCTAssertNil(try decoder.consume(line: ": keep-alive"))
        XCTAssertEqual(try decoder.consume(line: "data:{\"message\":{\"requestID\":\"\(id)\",\"delta\":\"Draft\"}}"), .delta("Draft"))
        XCTAssertEqual(try decoder.consume(line: "data:{\"result\":{\"content\":\"Completed\"}}"), .completed(.init(content: "Completed")))
        XCTAssertThrowsError(try decoder.consume(line: "data:{\"message\":{\"requestID\":\"\(id)\",\"delta\":\"Late\"}}"))
    }

    func testStreamRejectsOtherRequestAndServerErrorInsteadOfPublishingPartialAction() {
        var decoder = MaiaStreamDecoder(requestID: UUID())
        XCTAssertThrowsError(try decoder.consume(line: "data:{\"message\":{\"requestID\":\"\(UUID())\",\"delta\":\"Wrong answer\"}}"))
        XCTAssertThrowsError(try decoder.consume(line: "data:{\"error\":{\"message\":\"private internal error\"}}"))
    }

    func testSpeechChunksPreserveAmountsAndBoundEveryOnlineRequest() {
        let source = "Use 42.5 lb for 9 reps. Drink 16 oz. " + String(repeating: "Keep the same target. ", count: 200)
        let plan = MaiaSpeechPlan(source: source)
        XCTAssertGreaterThan(plan.sentences.count, 2)
        XCTAssertTrue(plan.sentences.allSatisfy { !$0.isEmpty && $0.utf16.count <= 1_800 })
        XCTAssertTrue(plan.text.contains("42.5 pounds"))
        XCTAssertTrue(plan.text.contains("16 ounces"))
        XCTAssertEqual(plan.sentences.joined(separator: " "), plan.text)
        XCTAssertFalse(MaiaSpeechPlan(source: "```json\n{\"type\":\"log_water\"}\n```").sentences.contains { !$0.isEmpty })
    }

    func testSpeechTablesKeepLabelsWithTheirValues() {
        let plan = MaiaSpeechPlan(source: "| Food | Protein |\n| --- | --- |\n| Yogurt | 25g |")
        XCTAssertEqual(plan.text, "Food: Yogurt, Protein: 25 grams.")
        XCTAssertFalse(plan.text.contains("|"))
    }

    func testBookmarkHasBoundedAgeAndValidSentenceWithoutAutoplayState() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let bookmark = MaiaSpeechBookmark(plan: .init(source: "First. Second."), sentenceIndex: 1, voiceIdentifier: "local", rate: 1.25, now: now)
        XCTAssertTrue(bookmark.canResume(now: now.addingTimeInterval(60)))
        XCTAssertFalse(bookmark.canResume(now: now.addingTimeInterval(8 * 86_400)))
        XCTAssertFalse(bookmark.canResume(now: now.addingTimeInterval(-1)))
    }
}
