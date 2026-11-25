import XCTest
@testable import MyFitPlateCore

final class RunReviewStoreTests: XCTestCase {
    private var folder: URL!
    private var store: RunReviewStore!
    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RunReviewStore(drafts: EditorDraftStore(directory: folder))
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testVisibilityUndoPreservesExactOriginalAndHealthAliasAcrossRelaunch() throws {
        let original = manual(), alias = original.reidentified(as: "health-alias")
        let review = try store.review(run: original, mutation: .hide, userID: "runner", operationID: "hide")
        let receipt = try store.commit(review, currentUserID: "runner")
        XCTAssertEqual(try store.commit(review, currentUserID: "runner"), receipt)
        store = RunReviewStore(drafts: EditorDraftStore(directory: folder))
        XCTAssertTrue(try store.projecting([alias], userID: "runner").isEmpty)
        XCTAssertEqual(try store.projecting([alias], userID: "other"), [alias])
        let undone = try store.undo(receipt, currentUserID: "runner")
        XCTAssertEqual(try store.undo(receipt, currentUserID: "runner"), undone)
        XCTAssertEqual(try store.projecting([alias], userID: "runner"), [alias])
        XCTAssertEqual(try store.originalEvidence(for: alias, userID: "runner"), alias)
    }

    func testNumericCorrectionCannotAcceptUnconfirmedOrMissingDiaryLink() throws {
        let original = manual()
        let review = try store.review(run: original,
            mutation: .correctManual(distanceMeters: 6_000, movingSeconds: 1_900, reason: "Treadmill display"), userID: "runner")
        XCTAssertThrowsError(try store.commit(review, currentUserID: "runner"))
        XCTAssertThrowsError(try store.commit(review, currentUserID: "runner", diaryAccepted: true))
        XCTAssertEqual(try store.projecting([original], userID: "runner"), [original])
        XCTAssertTrue(try store.latestReceipts(userID: "runner").isEmpty)
    }

    func testStaleReviewAndAccountChangeCannotOverwriteNewerReceipt() throws {
        let original = manual()
        let old = try store.review(run: original, mutation: .hide, userID: "runner", operationID: "old")
        let current = try store.commit(store.review(run: original, mutation: .hide, userID: "runner"), currentUserID: "runner")
        XCTAssertThrowsError(try store.commit(old, currentUserID: "runner"))
        XCTAssertThrowsError(try store.commit(old, currentUserID: "other"))
        var imported = original; imported.source = .imported(appName: "Watch")
        XCTAssertThrowsError(try store.review(run: imported, mutation: .correctManual(distanceMeters: 6_000, movingSeconds: 1_900, reason: "Guess"), userID: "runner"))
        _ = try store.undo(current, currentUserID: "runner")
        XCTAssertThrowsError(try store.undoReview(current, currentUserID: "runner"))
    }

    func testCorruptOverlayCannotBeOverwrittenByReview() throws {
        let original = manual()
        _ = try store.commit(store.review(run: original, mutation: .hide, userID: "runner"), currentUserID: "runner")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        let file = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        let corrupt = Data("broken receipt".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.review(run: original, mutation: .restoreOriginal, userID: "runner"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    private func manual() -> Run {
        ManualRunEntryRules.buildIndoorRun(startDate: Date(timeIntervalSince1970: 1_800_000_000),
            distanceMeters: 5_000, movingSeconds: 1_800, metric: true, activeCalories: 300)!
    }
}
