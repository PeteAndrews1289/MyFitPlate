import XCTest
@testable import MyFitPlateCore

@MainActor
final class RecipeServiceTests: XCTestCase {
    var service: RecipeService!
    var mockRepo: MockNutritionRepository!
    var mockAuth: MockAuthService!
    var mockAI: MockAIService!
    
    override func setUp() {
        super.setUp()
        service = RecipeService()
        mockRepo = MockNutritionRepository()
        mockAuth = MockAuthService()
        mockAI = MockAIService()
        
        mockAuth.currentUserID = "user_123"
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.authService = mockAuth
        DIContainer.shared.aiService = mockAI
    }
    
    override func tearDown() {
        service = nil
        mockRepo = nil
        mockAuth = nil
        mockAI = nil
        super.tearDown()
    }
    
    func testFetchUserRecipes() async {
        let sampleRecipe = Recipe(id: "r1", name: "Salad", ingredients: [], detailedIngredients: [], instructions: [], nutrition: Nutrition(calories: 100, protein: 5, carbs: 10, fats: 2), servings: 1)
        mockRepo.mockRecipes = [sampleRecipe]
        
        XCTAssertTrue(service.userRecipes.isEmpty)
        await service.fetchUserRecipes()
        
        XCTAssertEqual(service.userRecipes.count, 1)
        XCTAssertEqual(service.userRecipes.first?.name, "Salad")
    }
    
    func testSaveRecipeAddsToLocalArray() async throws {
        let newRecipe = Recipe(id: "r2", name: "Chicken", ingredients: [], detailedIngredients: [], instructions: [], nutrition: Nutrition(calories: 300, protein: 40, carbs: 0, fats: 10), servings: 2)
        
        let saved = try await service.saveRecipe(newRecipe, for: "user_123")
        
        XCTAssertEqual(mockRepo.savedRecipes.count, 1)
        XCTAssertEqual(service.userRecipes.count, 1)
        XCTAssertEqual(saved.id, "r2")
    }
    
    func testSaveRecipeUpdatesExistingRecipe() async throws {
        let existingRecipe = Recipe(id: "r1", name: "Old", ingredients: [], detailedIngredients: [], instructions: [], nutrition: Nutrition(calories: 100, protein: 5, carbs: 10, fats: 2), servings: 1)
        service.userRecipes = [existingRecipe]
        
        let updatedRecipe = Recipe(id: "r1", name: "New", ingredients: [], detailedIngredients: [], instructions: [], nutrition: Nutrition(calories: 100, protein: 5, carbs: 10, fats: 2), servings: 1)
        
        try await service.saveRecipe(updatedRecipe, for: "user_123")
        
        XCTAssertEqual(service.userRecipes.count, 1)
        XCTAssertEqual(service.userRecipes.first?.name, "New")
    }
    
    func testDeleteRecipe() async {
        let existingRecipe = Recipe(id: "r1", name: "Old", ingredients: [], detailedIngredients: [], instructions: [], nutrition: Nutrition(calories: 100, protein: 5, carbs: 10, fats: 2), servings: 1)
        service.userRecipes = [existingRecipe]
        
        await service.deleteRecipe(recipe: existingRecipe)
        
        XCTAssertTrue(service.userRecipes.isEmpty)
        XCTAssertEqual(mockRepo.deletedRecipeIDs.count, 1)
        XCTAssertEqual(mockRepo.deletedRecipeIDs.first, "r1")
    }
    
    func testRecipeToFoodItemConversion() {
        let recipe = Recipe(id: "r1", name: "Test Recipe", ingredients: [], detailedIngredients: [], instructions: [], nutrition: Nutrition(calories: 500, protein: 30, carbs: 40, fats: 20), servings: 2)
        
        let foodItem = service.recipeToFoodItem(recipe: recipe)
        
        XCTAssertEqual(foodItem.id, "r1")
        XCTAssertEqual(foodItem.name, "Test Recipe")
        XCTAssertEqual(foodItem.calories, 500)
        XCTAssertEqual(foodItem.protein, 30)
        XCTAssertEqual(foodItem.carbs, 40)
        XCTAssertEqual(foodItem.fats, 20)
        XCTAssertEqual(foodItem.quantityValue, 1.0)
        XCTAssertEqual(foodItem.servingUnit, "serving")
    }
    
    func testCreateRecipeFromAISuccess() async {
        let validJSON = """
        {
            "name": "AI Pizza",
            "ingredients": ["1 piece Dough"],
            "instructions": ["Bake it"],
            "nutrition": {"calories": 800, "protein": 30, "carbs": 100, "fats": 20}
        }
        """
        mockAI.mockResult = .success(validJSON)
        
        let recipe = await service.createRecipeFromAI(description: "Make a pizza", userID: "user_123")
        
        XCTAssertNotNil(recipe)
        XCTAssertEqual(recipe?.name, "AI Pizza")
        XCTAssertEqual(mockRepo.savedRecipes.count, 1)
        XCTAssertFalse(service.isLoading)
    }
    
    func testCreateRecipeFromAIFailsWithBadJSON() async {
        mockAI.mockResult = .success("invalid json")
        
        let recipe = await service.createRecipeFromAI(description: "Make a pizza", userID: "user_123", retryCount: 0)
        
        XCTAssertNil(recipe)
        XCTAssertEqual(mockRepo.savedRecipes.count, 0)
    }
    
    func testCreateRecipeFromTextSuccess() async {
        let validJSON = """
        {
            "name": "Text Recipe",
            "ingredients": ["2 large Eggs"],
            "instructions": ["Fry them"],
            "nutrition": {"calories": 140, "protein": 12, "carbs": 0, "fats": 10}
        }
        """
        mockAI.mockResult = .success(validJSON)
        
        let recipe = await service.createRecipeFromText(text: "2 fried eggs", userID: "user_123")
        
        XCTAssertNotNil(recipe)
        XCTAssertEqual(recipe?.name, "Text Recipe")
    }
    
    func testCreateRecipeFromPantrySuccess() async {
        let validJSON = """
        {
            "name": "Pantry Soup",
            "ingredients": ["1 can Beans"],
            "instructions": ["Heat"],
            "nutrition": {"calories": 300, "protein": 20, "carbs": 40, "fats": 2}
        }
        """
        mockAI.mockResult = .success(validJSON)
        
        let recipe = await service.createRecipeFromPantry(itemsString: "Beans", userID: "user_123")
        
        XCTAssertNotNil(recipe)
        XCTAssertEqual(recipe?.name, "Pantry Soup")
    }
    
    func testCreateRecipesFromPantrySuccess() async {
        let validJSON = """
        {
            "recipes": [
                {
                    "name": "Meal 1",
                    "ingredients": [],
                    "instructions": [],
                    "nutrition": {"calories": 100, "protein": 10, "carbs": 10, "fats": 1}
                },
                {
                    "name": "Meal 2",
                    "ingredients": [],
                    "instructions": [],
                    "nutrition": {"calories": 200, "protein": 20, "carbs": 20, "fats": 2}
                }
            ]
        }
        """
        mockAI.mockResult = .success(validJSON)
        
        let recipes = await service.createRecipesFromPantry(itemsString: "Stuff", userID: "user_123")
        
        XCTAssertEqual(recipes.count, 2)
        XCTAssertEqual(recipes[0].name, "Meal 1")
    }
    
    func testCreateRecipeFromURLInvalidURL() async {
        let recipe = await service.createRecipeFromURL(url: "not a url", userID: "user_123")
        XCTAssertNil(recipe)
    }
    
    // We can't easily mock URLSession inline without swizzling or using URLProtocol,
    // so we'll just test the AI failure path when retries are 0, or skip the URL network test if URLProtocol isn't setup.
    // However, the error handling when URL fetch fails handles `.badServerResponse` or standard errors.
    
    func testCreateRecipeFromURLFailsOnNetwork() async {
        // Will attempt to fetch a dummy URL, fail natively, and return nil
        let recipe = await service.createRecipeFromURL(url: "https://localhost:1/bad", userID: "user_123")
        XCTAssertNil(recipe)
    }

    func testCreateRecipeFromAIRetriesAndSucceeds() async {
        let validJSON = """
        {
            "name": "AI Pizza",
            "ingredients": ["1 piece Dough"],
            "instructions": ["Bake it"],
            "nutrition": {"calories": 800, "protein": 30, "carbs": 100, "fats": 20}
        }
        """
        mockAI.mockResults = [.success("invalid json"), .success(validJSON)]
        let recipe = await service.createRecipeFromAI(description: "Make a pizza", userID: "user_123", retryCount: 1)
        XCTAssertNotNil(recipe)
        XCTAssertEqual(recipe?.name, "AI Pizza")
    }

    func testCreateRecipeFromAIFailsAfterRetries() async {
        mockAI.mockResults = [.success("invalid json"), .success("invalid json 2")]
        let recipe = await service.createRecipeFromAI(description: "Make a pizza", userID: "user_123", retryCount: 1)
        XCTAssertNil(recipe)
    }

    func testCreateRecipeFromAIFailsOnNetworkError() async {
        mockAI.mockResult = .failure(.networkError(URLError(.notConnectedToInternet)))
        let recipe = await service.createRecipeFromAI(description: "Make a pizza", userID: "user_123")
        XCTAssertNil(recipe)
    }

    func testCreateRecipeFromTextRetriesAndSucceeds() async {
        let validJSON = """
        {
            "name": "Text Recipe",
            "ingredients": ["2 large Eggs"],
            "instructions": ["Fry them"],
            "nutrition": {"calories": 140, "protein": 12, "carbs": 0, "fats": 10}
        }
        """
        mockAI.mockResults = [.success("bad"), .success(validJSON)]
        let recipe = await service.createRecipeFromText(text: "eggs", userID: "user_123", retryCount: 1)
        XCTAssertNotNil(recipe)
    }

    func testCreateRecipeFromTextFailsOnNetwork() async {
        mockAI.mockResult = .failure(.networkError(URLError(.notConnectedToInternet)))
        let recipe = await service.createRecipeFromText(text: "eggs", userID: "user_123")
        XCTAssertNil(recipe)
    }

    func testCreateRecipeFromPantryRetriesAndSucceeds() async {
        let validJSON = """
        {
            "name": "Pantry Soup",
            "ingredients": ["1 can Beans"],
            "instructions": ["Heat"],
            "nutrition": {"calories": 300, "protein": 20, "carbs": 40, "fats": 2}
        }
        """
        mockAI.mockResults = [.success("bad"), .success(validJSON)]
        let recipe = await service.createRecipeFromPantry(itemsString: "Beans", userID: "user_123", retryCount: 1)
        XCTAssertNotNil(recipe)
    }
    
    func testCreateRecipeFromPantryFailsOnNetwork() async {
        mockAI.mockResult = .failure(.networkError(URLError(.notConnectedToInternet)))
        let recipe = await service.createRecipeFromPantry(itemsString: "Beans", userID: "user_123")
        XCTAssertNil(recipe)
    }

    func testCreateRecipesFromPantryRetriesAndSucceeds() async {
        let validJSON = """
        {
            "recipes": [
                {
                    "name": "Meal 1",
                    "ingredients": [],
                    "instructions": [],
                    "nutrition": {"calories": 100, "protein": 10, "carbs": 10, "fats": 1}
                }
            ]
        }
        """
        mockAI.mockResults = [.success("bad"), .success(validJSON)]
        let recipes = await service.createRecipesFromPantry(itemsString: "Beans", userID: "user_123", retryCount: 1)
        XCTAssertEqual(recipes.count, 1)
    }
    
    func testCreateRecipesFromPantryFailsOnNetwork() async {
        mockAI.mockResult = .failure(.networkError(URLError(.notConnectedToInternet)))
        let recipes = await service.createRecipesFromPantry(itemsString: "Beans", userID: "user_123")
        XCTAssertTrue(recipes.isEmpty)
    }
}
