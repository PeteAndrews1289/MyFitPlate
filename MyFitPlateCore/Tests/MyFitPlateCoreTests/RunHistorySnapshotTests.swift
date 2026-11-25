import XCTest
@testable import MyFitPlateCore

final class RunHistorySnapshotTests: XCTestCase {
    func testOfflineHistoryKeepsItsDateIdentityAndAccountAndDoesNotOverwriteUnreadableSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunHistorySnapshotStore(directory: directory)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(id: "owned", source: .recorded, startDate: date, endDate: date.addingTimeInterval(1000), distanceMeters: 3000, movingSeconds: 1000)
        try store.save([run], userID: "a", now: date)
        let cached = try XCTUnwrap(store.load(userID: "a"))
        XCTAssertEqual(cached.capturedAt, date)
        XCTAssertEqual(cached.runs, [run])
        XCTAssertFalse(cached.isTruncated)
        XCTAssertNil(try store.load(userID: "b"))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        let file = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        let corrupt = Data("keep unreadable snapshot".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.save([], userID: "a"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
}
