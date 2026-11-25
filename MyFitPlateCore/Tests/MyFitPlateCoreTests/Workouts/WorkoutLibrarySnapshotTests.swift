import XCTest
@testable import MyFitPlateCore

final class WorkoutLibrarySnapshotTests: XCTestCase {
    func testUnreadableRecordsKeepOnlyTheirLastGoodCopyAndServerDeletionsStayDeleted() {
        let older = ["good", "damaged", "deleted"].map { WorkoutProgram(id: $0, userID: "a", name: $0) }
        let fresh = WorkoutProgram(id: "good", userID: "a", name: "Updated")
        let merged = WorkoutLibrarySnapshot(values: [fresh], unreadableIDs: ["damaged", "unknown"])
            .retainingLastGood(older, id: \.id)
        XCTAssertEqual(merged.values.compactMap(\.id), ["good", "damaged"])
        XCTAssertEqual(merged.values.first?.name, "Updated")
        XCTAssertNotNil(merged.notice(noun: "plans"))
    }

    func testOfflineSubsetCannotEraseCachedPlansAndCacheRoundTripRetainsIssues() throws {
        let older = ["good", "offline"].map { WorkoutProgram(id: $0, userID: "a", name: $0) }
        let cached = WorkoutLibrarySnapshot(values: [older[0]], unreadableIDs: ["bad"], isFromCache: true)
            .retainingLastGood(older, id: \.id)
        let restored = try JSONDecoder().decode(WorkoutLibrarySnapshot<WorkoutProgram>.self, from: JSONEncoder().encode(cached))
        XCTAssertEqual(Set(restored.values.compactMap(\.id)), ["good", "offline"])
        XCTAssertEqual(restored.unreadableIDs, ["bad"])
        XCTAssertTrue(restored.isFromCache)
    }
}
