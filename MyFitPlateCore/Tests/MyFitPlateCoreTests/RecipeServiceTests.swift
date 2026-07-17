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
        service.activateAccount("user_123")
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
        let recipe = Recipe(
            id: "r1",
            name: "Test Recipe",
            ingredients: [],
            detailedIngredients: [],
            instructions: [],
            nutrition: Nutrition(
                calories: 500,
                protein: 30,
                carbs: 40,
                fats: 20,
                magnesium: 75,
                vitaminB6: 0.8
            ),
            servings: 2
        )
        
        let foodItem = service.recipeToFoodItem(recipe: recipe)
        
        XCTAssertEqual(foodItem.id, "r1")
        XCTAssertEqual(foodItem.name, "Test Recipe")
        XCTAssertEqual(foodItem.calories, 500)
        XCTAssertEqual(foodItem.protein, 30)
        XCTAssertEqual(foodItem.carbs, 40)
        XCTAssertEqual(foodItem.fats, 20)
        XCTAssertEqual(foodItem.magnesium, 75)
        XCTAssertEqual(foodItem.vitaminB6, 0.8)
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

    func testRecipeImportURLPolicyAllowsPublicHTTPS() {
        XCTAssertEqual(
            RecipeImportURLPolicy.allowedURL(from: "  https://recipes.example.com/pasta  ")?.absoluteString,
            "https://recipes.example.com/pasta"
        )
        XCTAssertEqual(
            RecipeImportURLPolicy.allowedURL(from: "https://recipes.example.com./pasta")?.absoluteString,
            "https://recipes.example.com/pasta"
        )
        XCTAssertNotNil(RecipeImportURLPolicy.allowedURL(from: "https://8.8.8.8/recipe"))
        XCTAssertNotNil(RecipeImportURLPolicy.allowedURL(from: "https://[2606:4700:4700::1111]/recipe"))
    }

    func testRecipeImportURLPolicyRejectsUnsafeDestinations() {
        let rejected = [
            "http://recipes.example.com/pasta",
            "file:///private/etc/hosts",
            "https://user:password@recipes.example.com/pasta",
            "https://localhost/recipe",
            "https://localhost./recipe",
            "https://localhost.localdomain./recipe",
            "https://printer/recipe",
            "https://recipes.local/recipe",
            "https://recipes.local./recipe",
            "https://router.home.arpa./recipe",
            "https://127.0.0.1/recipe",
            "https://10.0.0.1/recipe",
            "https://100.64.0.1/recipe",
            "https://169.254.1.1/recipe",
            "https://172.16.0.1/recipe",
            "https://192.0.0.1/recipe",
            "https://192.168.1.1/recipe",
            "https://192.0.2.1/recipe",
            "https://198.18.0.1/recipe",
            "https://198.19.255.254/recipe",
            "https://198.51.100.1/recipe",
            "https://203.0.113.1/recipe",
            "https://224.0.0.1/recipe",
            "https://0177.0.0.1/recipe",
            "https://0x7f.0.0.1/recipe",
            "https://[::1]/recipe",
            "https://[0:0:0:0:0:0:0:1]/recipe",
            "https://[::]/recipe",
            "https://[::127.0.0.1]/recipe",
            "https://[2002:7f00:1::]/recipe",
            "https://[64:ff9b::7f00:1]/recipe",
            "https://[fd00::1]/recipe",
            "https://[fe80::1]/recipe",
            "https://[fec0::1]/recipe",
            "https://[ff02::1]/recipe",
            "https://[::ffff:127.0.0.1]/recipe",
            "not a URL"
        ]

        for value in rejected {
            XCTAssertNil(RecipeImportURLPolicy.allowedURL(from: value), value)
        }
    }

    func testRecipeImportRedirectPolicyRevalidatesEveryDestination() throws {
        let publicRequest = URLRequest(url: try XCTUnwrap(URL(string: "https://recipes.example.com/final")))
        XCTAssertNotNil(RecipeImportURLPolicy.allowedRedirectRequest(publicRequest))

        let localRequest = URLRequest(url: try XCTUnwrap(URL(string: "https://127.0.0.1/admin")))
        XCTAssertNil(RecipeImportURLPolicy.allowedRedirectRequest(localRequest))

        let downgradedRequest = URLRequest(url: try XCTUnwrap(URL(string: "http://recipes.example.com/final")))
        XCTAssertNil(RecipeImportURLPolicy.allowedRedirectRequest(downgradedRequest))
    }

    func testRecipePageTextExtractorIncludesJSONLDAndVisibleRecipeText() throws {
        let html = """
        <html><body>
        <script type="application/ld+json">{"@type":"Recipe","name":"Oat Bowl"}</script>
        <h1>Oat Bowl</h1><p>Combine oats, milk, berries, and cinnamon in a bowl.</p>
        </body></html>
        """

        let text = try XCTUnwrap(RecipePageTextExtractor.extract(from: html))
        XCTAssertTrue(text.contains("\"@type\":\"Recipe\""))
        XCTAssertTrue(text.contains("Combine oats"))
    }

    func testRecipePageTextExtractorFallsBackToVisibleBodyText() throws {
        let html = """
        <html><body><div>Roast the chicken with lemon, garlic, potatoes, and herbs until fully cooked.</div></body></html>
        """

        let text = try XCTUnwrap(RecipePageTextExtractor.extract(from: html))
        XCTAssertTrue(text.contains("Roast the chicken"))
    }

    func testRecipePageTextExtractorRejectsPagesWithoutUsefulRecipeContent() throws {
        XCTAssertNil(try RecipePageTextExtractor.extract(from: "<html><body>Home</body></html>"))
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

    func testDelayedAIRecipeCannotSaveOrAppearAfterAccountSwitch() async {
        mockAI.responseDelayNanoseconds = 100_000_000
        mockAI.mockResult = .success("""
        {
            "name": "Private old recipe",
            "ingredients": [],
            "instructions": [],
            "nutrition": {"calories": 500, "protein": 30, "carbs": 40, "fats": 20}
        }
        """)

        let task = Task {
            await service.createRecipeFromAI(description: "Old account idea", userID: "user_123")
        }
        await Task.yield()
        mockAuth.currentUserID = "user_456"
        service.activateAccount("user_456")

        let recipe = await task.value
        XCTAssertNil(recipe)
        XCTAssertTrue(mockRepo.savedRecipes.isEmpty)
        XCTAssertTrue(service.userRecipes.isEmpty)
        XCTAssertFalse(service.isLoading)
    }
}
