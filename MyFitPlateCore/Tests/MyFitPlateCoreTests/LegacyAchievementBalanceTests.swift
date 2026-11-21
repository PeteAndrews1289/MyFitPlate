import XCTest
@testable import MyFitPlateCore

@MainActor
final class LegacyAchievementBalanceTests: XCTestCase {
    private var originalAuth: AuthServiceProtocol?
    override func setUp() {
        originalAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "a"; DIContainer.shared.authService = auth
    }
    override func tearDown() { DIContainer.shared.authService = originalAuth }
    func testMigrationIsIdempotentAndDoesNotAddToAggregateOrRewriteOpeningBalance() async throws {
        let repository = MockAchievementRepository()
        repository.mockUserProfile = (points: 987, level: 4)
        let first = try await repository.preserveLegacyPointBalance(userID: "a")
        XCTAssertEqual(first.openingPoints, 987)
        let command = try AchievementAwardCommand(ownerID: "a",
            definition: XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "first_log" }),
            evidence: .init(kind: "food_entry", sourceID: "2026-11-04", sourceFingerprint: "food-1",
                recordedAt: Date(), explanation: "Saved meal", facts: ["foodID": "f1"]))
        let awarded = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertEqual(awarded.totalPoints, 997)
        let reopened = try await repository.preserveLegacyPointBalance(userID: "a")
        XCTAssertEqual(reopened, first)
        let replay = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds)
        XCTAssertEqual(replay.totalPoints, 997); XCTAssertFalse(replay.awardedNow)
        XCTAssertEqual(repository.acceptedAwardCount, 1)
    }
    func testFirstAwardCapturesOpeningBalanceEvenBeforeProfileScreenIsOpened() async throws {
        let repository = MockAchievementRepository(); repository.mockUserProfile = (points: 400, level: 2)
        let command = try AchievementAwardCommand(ownerID: "a",
            definition: XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "first_log" }),
            evidence: .init(kind: "food_entry", sourceID: "2026-11-04", sourceFingerprint: "food-2",
                recordedAt: Date(), explanation: "Saved meal", facts: ["foodID": "f2"]))
        _ = try await repository.acceptAward(command, levelThresholds: AchievementRules.defaultLevelThresholds)
        let receipt = try await repository.preserveLegacyPointBalance(userID: "a")
        XCTAssertEqual(receipt.openingPoints, 400)
        do { _ = try await repository.preserveLegacyPointBalance(userID: "b"); XCTFail("Wrong account accepted") }
        catch { XCTAssertEqual(error as? AchievementAwardError, .accountChanged) }
    }
    func testMismatchedReceiptAndInvalidBalancesAreNotSilentlyMigrated() throws {
        let first = LegacyAchievementBalanceReceipt(ownerID: "a", openingPoints: 800)
        XCTAssertThrowsError(try LegacyAchievementBalanceReceipt.preserving(first, ownerID: "b", profilePoints: 800))
        XCTAssertThrowsError(try LegacyAchievementBalanceReceipt.preserving(nil, ownerID: "a", profilePoints: -1))
        XCTAssertEqual(try LegacyAchievementBalanceReceipt.preserving(first, ownerID: "a", profilePoints: 900), first)
        XCTAssertTrue(first.explanation.contains("adds no points"))
    }
}
