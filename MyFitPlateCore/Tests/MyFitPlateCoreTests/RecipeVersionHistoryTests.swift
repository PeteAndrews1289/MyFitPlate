import XCTest
@testable import MyFitPlateCore

@MainActor
final class RecipeVersionHistoryTests: XCTestCase {
    private let owner = "recipe-versions-owner"
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: NutritionRepositoryProtocol?
    private var repository: MockNutritionRepository!
    private var auth: MockAuthService!
    private var service: RecipeService!
    private var store: EditorDraftStore!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository(); repository.recipeVersionAccountID = owner
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        service = RecipeService(); service.activateAccount(owner)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository
        super.tearDown()
    }
    private func recipe(yield: Double = 4) throws -> Recipe {
        var value = Recipe(id: "rice", name: "Rice batch", ingredients: ["400 g rice"], instructions: ["Cook"],
            nutrition: Nutrition(calories: 1_600, protein: 40, carbs: 300, fats: 16), servings: yield,
            nutritionBasis: .wholeRecipe, nutritionOrigin: .ingredients, cookedWeightGrams: 800)
        value.revisionID = try RecipePortionRules.revisionID(for: value); return value
    }
    private func changed(_ value: Recipe, yield: Double) throws -> Recipe {
        var value = value; value.servings = yield; value.revisionID = try RecipePortionRules.revisionID(for: value); return value
    }
    private func setupProposal() async throws -> RecipeVersionRestoreProposal {
        let initial = try await repository.saveRecipeRevision(userID: owner, expected: nil, updated: recipe(), operationID: UUID())
        let newer = try await repository.saveRecipeRevision(userID: owner, expected: initial, updated: changed(initial, yield: 8), operationID: UUID())
        let versions = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        let selected = try XCTUnwrap(versions.first { $0.phase == .before })
        return RecipeVersionRestoreProposal(userID: owner, version: selected, expected: newer)
    }
    func testLegacyDoesNotInventHistoryAndCheckedEditPreservesBothVersions() async throws {
        repository.mockRecipes = [try recipe()]
        let absent = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        XCTAssertTrue(absent.isEmpty)
        let original = try XCTUnwrap(repository.mockRecipes.first)
        let operation = UUID()
        _ = try await repository.saveRecipeRevision(userID: owner, expected: original, updated: changed(original, yield: 8), operationID: operation)
        let versions = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(Set(versions.map(\.operationID)), [operation])
        XCTAssertEqual(versions.first { $0.phase == .before }?.snapshot.servings, 4)
        XCTAssertEqual(versions.first { $0.phase == .saved }?.snapshot.servings, 8)
    }
    func testRestoreKeepsRecipeIdentityOrganizationAndFrozenLoggedPortions() async throws {
        let proposal = try await setupProposal()
        let logged = try RecipePortionRules.foodItem(for: proposal.expected, selection: .init(unit: .servings, amount: 1))
        var current = proposal.expected
        current.libraryMetadata = RecipeLibraryMetadata(favorite: true, tags: ["Dinner"])
        repository.mockRecipes = [current]
        let reviewed = RecipeVersionRestoreProposal(userID: owner, version: proposal.version, expected: current)
        let restored = try await repository.restoreRecipeVersion(userID: owner, proposal: reviewed)
        XCTAssertEqual(restored.id, current.id); XCTAssertEqual(restored.servings, 4)
        XCTAssertEqual(restored.libraryMetadata, current.libraryMetadata)
        XCTAssertEqual(restored.revisionID, proposal.version.snapshot.revisionID)
        XCTAssertEqual(logged.recipePortionSnapshot?.yieldServings, 8)
        XCTAssertEqual(logged.calories, 200)
        let history = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        XCTAssertEqual(history.count, 5)
        XCTAssertEqual(history.filter { $0.operationID == reviewed.id && $0.phase == .restored }.count, 1)
    }
    func testStaleOpeningAndFabricatedHistoricalSnapshotFailWithoutWrites() async throws {
        let proposal = try await setupProposal()
        repository.mockRecipes = [try changed(proposal.expected, yield: 10)]
        do { _ = try await repository.restoreRecipeVersion(userID: owner, proposal: proposal); XCTFail("Concurrent edit must survive") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        repository.mockRecipes = [proposal.expected]
        let tampered = try RecipeVersionRecord(id: proposal.version.id, recipeID: "rice", operationID: proposal.version.operationID,
            phase: proposal.version.phase, recordedAt: proposal.version.recordedAt, snapshot: recipe(yield: 3))
        let different = RecipeVersionRestoreProposal(userID: owner, version: tampered, expected: proposal.expected)
        do { _ = try await repository.restoreRecipeVersion(userID: owner, proposal: different); XCTFail("Selected server snapshot must match") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        let history = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        XCTAssertEqual(history.count, 3); XCTAssertEqual(repository.mockRecipes.first?.servings, 8)
    }
    func testLostAcknowledgementRetryReadsLaterEditAndNeverAddsAnotherHistory() async throws {
        let proposal = try await setupProposal()
        repository.recipeRevisionFailureAfterCommit = URLError(.networkConnectionLost)
        do { _ = try await repository.restoreRecipeVersion(userID: owner, proposal: proposal); XCTFail("Simulated lost acknowledgement") } catch { }
        let later = try changed(proposal.expected, yield: 12); repository.mockRecipes = [later]
        let replay = try await repository.restoreRecipeVersion(userID: owner, proposal: proposal)
        XCTAssertEqual(replay.servings, 12)
        let history = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        XCTAssertEqual(history.count, 5)
        try await repository.deleteRecipe(userID: owner, recipeID: "rice")
        let status = try await repository.resolveRecipeVersionRestore(userID: owner, proposal: proposal, cancelIfUnaccepted: true)
        XCTAssertEqual(status, .accepted(nil))
        do { _ = try await repository.restoreRecipeVersion(userID: owner, proposal: proposal); XCTFail("Accepted retry must not recreate deleted recipe") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
        XCTAssertTrue(repository.mockRecipes.isEmpty)
    }
    func testCancellationFencesLateTransportAndPayloadReuse() async throws {
        let proposal = try await setupProposal()
        let pending = try await repository.resolveRecipeVersionRestore(userID: owner, proposal: proposal, cancelIfUnaccepted: false)
        XCTAssertEqual(pending, .pending)
        let cancelled = try await repository.resolveRecipeVersionRestore(userID: owner, proposal: proposal, cancelIfUnaccepted: true)
        XCTAssertEqual(cancelled, .cancelled)
        do { _ = try await repository.restoreRecipeVersion(userID: owner, proposal: proposal); XCTFail("Late transport fenced") } catch { XCTAssertEqual(error as? RecipeRevisionError, .cancelled) }
        let altered = RecipeVersionRestoreProposal(userID: owner, id: proposal.id, version: proposal.version, expected: try changed(proposal.expected, yield: 9))
        do { _ = try await repository.resolveRecipeVersionRestore(userID: owner, proposal: altered, cancelIfUnaccepted: false); XCTFail("Permanent immutable payload") } catch { XCTAssertEqual(error as? RecipeRevisionError, .changed) }
    }
    func testDurableSessionRetainsExactIntentAndResolvesLostAckAfterReopen() async throws {
        let proposal = try await setupProposal()
        let live = RecipeVersionRestoreSession(userID: owner, proposal: proposal, store: store)
        repository.recipeRevisionFailureAfterCommit = URLError(.networkConnectionLost)
        await live.save(using: service)
        XCTAssertNotNil(live.errorMessage); XCTAssertTrue(live.checkpoint?.submitted == true)
        let reopened = RecipeVersionRestoreSession(userID: owner, store: store)
        XCTAssertEqual(reopened.checkpoint?.proposal.id, proposal.id)
        XCTAssertEqual(try reopened.checkpoint?.proposal.fingerprint, try proposal.fingerprint)
        XCTAssertFalse(reopened.finish())
        await reopened.resolve(using: service, cancelIfUnaccepted: false)
        XCTAssertTrue(reopened.finished); XCTAssertNil(reopened.errorMessage)
        XCTAssertTrue(reopened.finish())
        XCTAssertNil(RecipeVersionRestoreSession(userID: owner, store: store).checkpoint)
    }
    func testAccountIsolationAndLocalCASPreserveNewerReview() async throws {
        let proposal = try await setupProposal()
        let live = RecipeVersionRestoreSession(userID: owner, proposal: proposal, store: store)
        let newer = RecipeVersionRestoreProposal(userID: owner, version: proposal.version, expected: proposal.expected)
        try store.save(RecipeVersionRestoreCheckpoint(proposal: newer), userID: owner, scope: RecipeVersionRestoreSession.scope)
        await live.save(using: service)
        XCTAssertNotNil(live.errorMessage)
        XCTAssertEqual(RecipeVersionRestoreSession(userID: owner, store: store).checkpoint?.proposal.id, newer.id)
        auth.currentUserID = "other-owner"
        XCTAssertNil(RecipeVersionRestoreSession(userID: owner, store: store).checkpoint)
        do { _ = try await repository.fetchRecipeVersionHistory(userID: "other-owner", recipeID: "rice", limit: 60); XCTFail("Owner gated") } catch { XCTAssertEqual(error as? RecipeRevisionError, .accountChanged) }
        XCTAssertEqual(repository.mockRecipes.first?.servings, 8)
    }
    func testRestoreAndEditUsingSameOperationUUIDCannotOverwriteEarlierVersion() async throws {
        let operation = UUID()
        let original = try await repository.saveRecipeRevision(userID: owner, expected: nil, updated: recipe(), operationID: operation)
        _ = try await repository.saveRecipeRevision(userID: owner, expected: original, updated: changed(original, yield: 8), operationID: UUID())
        let history = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        let selected = try XCTUnwrap(history.first { $0.operationID == operation })
        let proposal = RecipeVersionRestoreProposal(userID: owner, id: operation, version: selected, expected: try XCTUnwrap(repository.mockRecipes.first))
        _ = try await repository.restoreRecipeVersion(userID: owner, proposal: proposal)
        let after = try await repository.fetchRecipeVersionHistory(userID: owner, recipeID: "rice", limit: 60)
        XCTAssertEqual(after.count, 5)
        XCTAssertEqual(Set(after.map(\.id)).count, 5)
        XCTAssertEqual(try after.first(where: { $0.id == selected.id }).map(PlanFingerprint.make), try PlanFingerprint.make(selected))
    }
    func testUnreadableReviewBytesSurviveNewProposal() async throws {
        let proposal = try await setupProposal()
        _ = RecipeVersionRestoreSession(userID: owner, proposal: proposal, store: store)
        let paths = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        let file = try XCTUnwrap(paths.compactMap { $0 as? URL }.first { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true })
        let bytes = Data("{unreadable-version-review".utf8); try bytes.write(to: file)
        let session = RecipeVersionRestoreSession(userID: owner, proposal: proposal, store: store)
        XCTAssertNotNil(session.errorMessage); XCTAssertNil(session.checkpoint)
        XCTAssertFalse(session.finish()); XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
