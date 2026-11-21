import XCTest
@testable import MyFitPlateCore

@MainActor
final class RecipeRevisionSaveSessionTests: XCTestCase {
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: RecipeService!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: NutritionRepositoryProtocol?
    private var directory: URL!
    private var store: EditorDraftStore!
    private let owner = "recipe-revision-owner"

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService
        previousRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        service = RecipeService(); service.activateAccount(owner)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = EditorDraftStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        DIContainer.shared.authService = previousAuth
        DIContainer.shared.nutritionRepository = previousRepository
        super.tearDown()
    }

    private func proposal(id: String = "soup", operationID: UUID = UUID()) throws -> RecipeRevisionSaveProposal {
        var recipe = Recipe(id: id, name: "Bean soup", ingredients: ["400 g beans"], instructions: ["Heat"],
            nutrition: Nutrition(calories: 800, protein: 40, carbs: 120, fats: 8), servings: 4,
            nutritionBasis: .wholeRecipe, nutritionOrigin: .aiEstimate, cookedWeightGrams: 800)
        recipe.revisionID = try RecipePortionRules.revisionID(for: recipe)
        return RecipeRevisionSaveProposal(userID: owner, operationID: operationID, expected: nil, updated: recipe)
    }

    private func session(_ userID: String? = nil) -> RecipeRevisionSaveSession {
        RecipeRevisionSaveSession(userID: userID ?? owner, store: store)
    }

    private func assertSubmit(_ live: RecipeRevisionSaveSession, expected: Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let actual = await live.submit(using: service)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func assertResolve(_ live: RecipeRevisionSaveSession, cancel: Bool, expected: Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let actual = await live.resolve(using: service, cancelIfUnaccepted: cancel)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func testPrepareAndRestartKeepExactProposalIdentityAndPortions() throws {
        let proposal = try proposal()
        XCTAssertTrue(session().prepare(proposal))
        let restored = session()
        XCTAssertEqual(restored.proposal?.operationID, proposal.operationID)
        XCTAssertEqual(try PlanFingerprint.make(restored.proposal), try PlanFingerprint.make(proposal as RecipeRevisionSaveProposal?))
        XCTAssertEqual(restored.proposal?.updated.servings, 4)
        XCTAssertEqual(restored.proposal?.updated.cookedWeightGrams, 800)
        XCTAssertTrue(repository.savedRecipes.isEmpty)
    }

    func testFrozenProposalCannotBeReplacedByAnotherPayload() throws {
        let live = session(), first = try proposal(), second = try proposal(id: "another-recipe", operationID: first.operationID)
        XCTAssertTrue(live.prepare(first))
        XCTAssertFalse(live.prepare(second))
        XCTAssertEqual(session().proposal?.updated.id, "soup")
        XCTAssertEqual(session().proposal?.operationID, first.operationID)
    }

    func testFailedTransportRetainsThenRestartRetryCreatesOneRecipe() async throws {
        let first = session(), proposal = try proposal()
        XCTAssertTrue(first.prepare(proposal))
        repository.recipeRevisionError = URLError(.notConnectedToInternet)
        await assertSubmit(first, expected: false)
        XCTAssertEqual(first.proposal?.operationID, proposal.operationID)
        XCTAssertNotNil(first.errorMessage)
        repository.recipeRevisionError = nil
        let restored = session()
        await assertSubmit(restored, expected: true)
        XCTAssertTrue(restored.isFinished)
        XCTAssertNil(session().proposal)
        XCTAssertEqual(repository.savedRecipes.count, 1)
        XCTAssertEqual(repository.mockRecipes.first?.servings, 4)
    }

    func testLostAcknowledgementStatusPreservesLaterEditAndClearsOnlyItsProposal() async throws {
        let live = session(), proposal = try proposal()
        XCTAssertTrue(live.prepare(proposal))
        repository.recipeRevisionFailureAfterCommit = URLError(.networkConnectionLost)
        await assertSubmit(live, expected: false)
        var later = try XCTUnwrap(repository.mockRecipes.first)
        later.servings = 5; later.revisionID = try RecipePortionRules.revisionID(for: later)
        repository.mockRecipes = [later]
        let restored = session()
        await assertResolve(restored, cancel: false, expected: true)
        XCTAssertTrue(restored.wasAccepted)
        XCTAssertEqual(restored.acceptedRecipe?.servings, 5)
        XCTAssertEqual(repository.mockRecipes.first?.servings, 5)
        XCTAssertEqual(repository.savedRecipes.count, 1)
        XCTAssertNil(session().proposal)
    }

    func testAcceptedThenDeletedRecipeIsNotRecreatedByStatusOrCancellation() async throws {
        let live = session(), proposal = try proposal()
        XCTAssertTrue(live.prepare(proposal))
        repository.recipeRevisionFailureAfterCommit = URLError(.networkConnectionLost)
        await assertSubmit(live, expected: false)
        try await repository.deleteRecipe(userID: owner, recipeID: "soup")
        let restored = session()
        await assertResolve(restored, cancel: true, expected: true)
        XCTAssertTrue(restored.wasAccepted)
        XCTAssertNil(restored.acceptedRecipe)
        XCTAssertTrue(repository.mockRecipes.isEmpty)
        XCTAssertEqual(repository.savedRecipes.count, 1)
    }

    func testMissingReceiptCannotDiscardUntilPermanentCancellationFence() async throws {
        let live = session(), proposal = try proposal()
        XCTAssertTrue(live.prepare(proposal))
        await assertResolve(live, cancel: false, expected: false)
        XCTAssertNotNil(session().proposal)
        await assertResolve(live, cancel: true, expected: true)
        XCTAssertNil(session().proposal)
        do {
            _ = try await repository.saveRecipeRevision(userID: owner, expected: proposal.expected,
                updated: proposal.updated, operationID: proposal.operationID)
            XCTFail("A late submission must be fenced")
        } catch { XCTAssertEqual(error as? RecipeRevisionError, .cancelled) }
        XCTAssertTrue(repository.savedRecipes.isEmpty)
    }

    func testAnotherAccountsProposalIsNotShownOrSubmitted() async throws {
        let live = session()
        XCTAssertTrue(live.prepare(try proposal()))
        auth.currentUserID = "other-owner"
        XCTAssertNil(session(owner).proposal)
        await assertSubmit(live, expected: false)
        await assertResolve(live, cancel: true, expected: false)
        XCTAssertNil(session("other-owner").proposal)
        XCTAssertTrue(repository.savedRecipes.isEmpty)
        auth.currentUserID = owner
        XCTAssertNotNil(session().proposal)
    }

    func testCorruptPendingBytesArePreservedAndCannotBeOverwritten() throws {
        XCTAssertTrue(session().prepare(try proposal()))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        let file = try XCTUnwrap(files.compactMap { $0 as? URL }.first {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        })
        let unreadable = Data("{broken recipe recovery".utf8)
        try unreadable.write(to: file)
        let restored = session()
        XCTAssertTrue(restored.isUnreadable)
        XCTAssertFalse(restored.prepare(try proposal(id: "other")))
        XCTAssertEqual(try Data(contentsOf: file), unreadable)
    }

    func testAcceptedCleanupNeverRemovesANewerPendingProposal() async throws {
        let live = session(), first = try proposal()
        XCTAssertTrue(live.prepare(first))
        repository.recipeRevisionFailureAfterCommit = URLError(.networkConnectionLost)
        await assertSubmit(live, expected: false)
        let newer = try proposal(id: "other")
        try store.save(newer, userID: owner, scope: RecipeRevisionSaveSession.scope)
        await assertResolve(live, cancel: false, expected: false)
        XCTAssertEqual(session().proposal?.operationID, newer.operationID)
        XCTAssertEqual(repository.savedRecipes.count, 1)
    }
}
