import XCTest
@testable import MyFitPlateCore

private actor RecipePublicationGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer?.resume(); observer = nil
        }
    }
    func entered() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}

@MainActor
final class RecipePublicationTests: XCTestCase {
    private var auth: MockAuthService!
    private var repository: MockNutritionRepository!
    private var service: RecipeService!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: NutritionRepositoryProtocol?
    private let owner = "recipe-publication-owner"

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepository = DIContainer.shared.nutritionRepository
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockNutritionRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.nutritionRepository = repository
        service = RecipeService(); service.activateAccount(owner)
    }
    override func tearDown() {
        DIContainer.shared.authService = previousAuth; DIContainer.shared.nutritionRepository = previousRepository
        super.tearDown()
    }

    private func recipe(_ id: String = "soup", servings: Double = 4) throws -> Recipe {
        var result = Recipe(id: id, name: id, ingredients: ["Beans"], instructions: ["Heat"],
            nutrition: Nutrition(calories: 800), servings: servings, nutritionBasis: .wholeRecipe)
        result.revisionID = try RecipePortionRules.revisionID(for: result)
        return result
    }

    func testOlderFetchCannotReplaceNewlySavedYield() async throws {
        let original = try recipe(), updated = try recipe(servings: 5)
        repository.mockRecipes = [original]; service.userRecipes = [original]
        let gate = RecipePublicationGate<[Recipe]>()
        repository.fetchRecipesHandler = { _ in await gate.wait() }
        let fetch = Task { await service.fetchUserRecipes() }
        await gate.entered()
        _ = try await service.saveRecipeRevision(updated, for: owner, expected: original, operationID: UUID())
        await gate.release([original]); await fetch.value
        XCTAssertEqual(service.userRecipes.first?.servings, 5)
        XCTAssertEqual(repository.mockRecipes.first?.servings, 5)
    }

    func testOlderSaveCallbackCannotReplaceANewerAcceptedVersion() async throws {
        let original = try recipe(), second = try recipe(servings: 5), latest = try recipe(servings: 6)
        repository.mockRecipes = [original]; service.userRecipes = [original]
        let gate = RecipePublicationGate<Recipe>()
        repository.recipeRevisionReturnHandler = { recipe in recipe.servings == 5 ? await gate.wait() : recipe }
        let oldSave = Task { try await service.saveRecipeRevision(second, for: owner, expected: original, operationID: UUID()) }
        await gate.entered()
        _ = try await service.saveRecipeRevision(latest, for: owner, expected: second, operationID: UUID())
        await gate.release(second); _ = try await oldSave.value
        XCTAssertEqual(service.userRecipes.first?.servings, 6)
        XCTAssertEqual(repository.mockRecipes.first?.servings, 6)
        XCTAssertEqual(repository.savedRecipes.count, 2)
    }

    func testOlderSaveCallbackCannotReinsertDeletedLibraryRow() async throws {
        let original = try recipe(), updated = try recipe(servings: 5)
        repository.mockRecipes = [original]; service.userRecipes = [original]
        let gate = RecipePublicationGate<Recipe>()
        repository.recipeRevisionReturnHandler = { _ in await gate.wait() }
        let oldSave = Task { try await service.saveRecipeRevision(updated, for: owner, expected: original, operationID: UUID()) }
        await gate.entered()
        await service.deleteRecipe(recipe: updated)
        await gate.release(updated); _ = try await oldSave.value
        XCTAssertTrue(service.userRecipes.isEmpty)
        XCTAssertTrue(repository.mockRecipes.isEmpty)
    }

    func testWritesToDifferentRecipesBothPublishDespiteOppositeCallbackOrder() async throws {
        let first = try recipe("first"), second = try recipe("second")
        let firstUpdated = try recipe("first", servings: 5), secondUpdated = try recipe("second", servings: 6)
        repository.mockRecipes = [first, second]; service.userRecipes = [first, second]
        let gate = RecipePublicationGate<Recipe>()
        repository.recipeRevisionReturnHandler = { recipe in recipe.id == "first" ? await gate.wait() : recipe }
        let delayed = Task { try await service.saveRecipeRevision(firstUpdated, for: owner, expected: first, operationID: UUID()) }
        await gate.entered()
        _ = try await service.saveRecipeRevision(secondUpdated, for: owner, expected: second, operationID: UUID())
        await gate.release(firstUpdated); _ = try await delayed.value
        XCTAssertEqual(service.userRecipes.count, 2)
        XCTAssertEqual(service.userRecipes.first { $0.id == "first" }?.servings, 5)
        XCTAssertEqual(service.userRecipes.first { $0.id == "second" }?.servings, 6)
    }
}
