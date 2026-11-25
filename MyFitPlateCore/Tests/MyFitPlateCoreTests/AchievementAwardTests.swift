import XCTest
@testable import MyFitPlateCore

@MainActor
final class AchievementAwardTests: XCTestCase {
    private var directory: URL!
    private var store: AchievementAwardStore!
    private var originalAuth: AuthServiceProtocol?
    override func setUp() {
        originalAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "award-owner"; DIContainer.shared.authService = auth
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = AchievementAwardStore(store: EditorDraftStore(directory: directory))
    }
    override func tearDown() {
        DIContainer.shared.authService = originalAuth
        try? FileManager.default.removeItem(at: directory)
    }
    private func command(source: String = "food") throws -> AchievementAwardCommand {
        try AchievementAwardCommand(ownerID: "award-owner", definition: XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "first_log" }),
            evidence: AchievementAwardEvidence(kind: "food_entry", sourceID: "2026-11-04", sourceFingerprint: "accepted-\(source)",
                recordedAt: Date().addingTimeInterval(-60), explanation: "Accepted food", facts: ["foodID": source]))
    }
    func testOutboxRetainsFirstExactEvidenceAndRequiresCorrectAccountAcknowledgment() throws {
        let first = try command(), later = try command(source: "later")
        XCTAssertEqual(try store.stage(first, currentUserID: "award-owner"), first)
        XCTAssertEqual(try store.stage(later, currentUserID: "award-owner"), first)
        XCTAssertThrowsError(try store.acknowledge(first, currentUserID: "other"))
        XCTAssertThrowsError(try store.acknowledge(later, currentUserID: "award-owner"))
        XCTAssertEqual(try store.pending(userID: "award-owner"), [first])
        try store.acknowledge(first, currentUserID: "award-owner")
        XCTAssertTrue(try store.pending(userID: "award-owner").isEmpty)
    }
    func testLegacyOutboxMigrationAndRetirementAtomicallyPromoteConcurrentCandidate() throws {
        let first = try command(), later = try command(source: "new-valid-food")
        let drafts = EditorDraftStore(directory: directory)
        try drafts.save([first], userID: "award-owner", scope: "achievement-award-outbox-v1")
        XCTAssertEqual(try store.pending(userID: "award-owner"), [first])
        _ = try store.stage(later, currentUserID: "award-owner")
        try store.retireObsoleteEvidence(first, currentUserID: "award-owner")
        let reopened = AchievementAwardStore(store: drafts)
        XCTAssertEqual(try reopened.pending(userID: "award-owner"), [later])
        XCTAssertEqual(try reopened.retiredEvidence(userID: "award-owner").map(\.command), [first])
        try reopened.retireObsoleteEvidence(first, currentUserID: "award-owner")
        XCTAssertEqual(try reopened.pending(userID: "award-owner"), [later], "Repeated retirement cannot erase a successor")
        XCTAssertThrowsError(try reopened.acknowledge(first, currentUserID: "award-owner"))
    }

    func testLegacyUnlockedStatusPreservesBalanceAndCannotBeRelockedByLateProgress() async throws {
        let repo = MockAchievementRepository()
        repo.mockUserProfile = (points: 987, level: 4)
        let legacy = UserAchievementStatus(id: "first_log", achievementID: "first_log", isUnlocked: true, unlockedDate: Date(), currentProgress: 1)
        repo.mockUserStatuses = [legacy]
        let first = try await repo.acceptAward(command(), levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertFalse(first.awardedNow); XCTAssertEqual(first.totalPoints, 987)
        XCTAssertEqual(first.status.legacyAwardPreserved, true)
        try await repo.saveUserStatus(userID: "award-owner", status: UserAchievementStatus(id: "first_log", achievementID: "first_log", currentProgress: 0))
        let replay = try await repo.acceptAward(command(source: "other-event"), levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertTrue(replay.status.isUnlocked); XCTAssertEqual(replay.totalPoints, 987)
        XCTAssertEqual(repo.acceptedAwardCount, 0)
    }
    func testNewAwardAtomicallyPreservesFirstEvidenceOnReplayAndUnknownEvidenceIsRejected() async throws {
        let repo = MockAchievementRepository(), first = try command()
        let accepted = try await repo.acceptAward(first, levelThresholds: AchievementRules.defaultLevelThresholds)
        let replay = try await repo.acceptAward(command(source: "later"), levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertEqual(accepted.totalPoints, 10); XCTAssertEqual(replay.totalPoints, 10)
        XCTAssertEqual(replay.status.awardEvidence, first.evidence)
        XCTAssertEqual(repo.acceptedAwardCount, 1)
        let invalid = try AchievementAwardCommand(ownerID: "award-owner", definition: XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "first_log" }),
            evidence: AchievementAwardEvidence(kind: "opened_screen", sourceID: "screen", sourceFingerprint: "anything", recordedAt: Date(), explanation: "No accepted food"))
        XCTAssertThrowsError(try invalid.validate(currentUserID: "award-owner"))
    }
    func testCorruptAwardOutboxIsKeptInsteadOfResetAndReaward() throws {
        _ = try store.stage(command(), currentUserID: "award-owner")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        let file = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        let bytes = Data("corrupt award requests".utf8); try bytes.write(to: file)
        XCTAssertThrowsError(try store.stage(command(source: "new"), currentUserID: "award-owner"))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
