import Foundation
import SwiftSoup

@MainActor
public class RecipeService: ObservableObject {

    @Published public var userRecipes: [Recipe] = []
    @Published public var isLoading: Bool = false

    public init() {}

    // MARK: - AI Recipe Generation (Refactored)
    public func createRecipeFromAI(description: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        let prompt = RecipeRules.createRecipeFromAIPrompt(description: description)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        // Use the centralized service
        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0 // We handle logic retries below
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_generated", parameters: nil)
                isLoading = false
                return savedRecipe
            } catch {
                AppLog.recipes.error("Recipe parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying recipe generation.")
                    return await createRecipeFromAI(description: description, userID: userID, retryCount: retryCount - 1)
                }
                isLoading = false
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("Recipe AI request failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            return nil
        }
    }

    public func createRecipeFromText(text: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        let prompt = RecipeRules.createRecipeFromTextPrompt(text: text)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_text_imported", parameters: nil)
                isLoading = false
                return savedRecipe
            } catch {
                AppLog.recipes.error("Recipe text parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying recipe text generation.")
                    return await createRecipeFromText(text: text, userID: userID, retryCount: retryCount - 1)
                }
                isLoading = false
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("Recipe text AI request failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            return nil
        }
    }

    public func createRecipeFromPantry(itemsString: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        let prompt = RecipeRules.createRecipeFromPantryPrompt(itemsString: itemsString)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_pantry_generated", parameters: nil)
                isLoading = false
                return recipe
            } catch {
                AppLog.recipes.error("Pantry Recipe parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying pantry recipe generation.")
                    return await createRecipeFromPantry(itemsString: itemsString, userID: userID, retryCount: retryCount - 1)
                }
                isLoading = false
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("Pantry Recipe AI request failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            return nil
        }
    }

    public func createRecipesFromPantry(itemsString: String, userID: String, retryCount: Int = 1) async -> [Recipe] {
        isLoading = true

        let prompt = RecipeRules.createRecipesFromPantryPrompt(itemsString: itemsString)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.6,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipes = try RecipeRules.parseRecipesFromAIResponse(jsonString)
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_pantry_generated", parameters: ["count": recipes.count])
                isLoading = false
                return recipes
            } catch {
                AppLog.recipes.error("Pantry Recipes parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    return await createRecipesFromPantry(itemsString: itemsString, userID: userID, retryCount: retryCount - 1)
                }
                isLoading = false
                return []
            }
        case .failure(let error):
            AppLog.recipes.error("Pantry Recipes AI request failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            return []
        }
    }

    public func createRecipeFromURL(url: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        guard let urlObj = URL(string: url) else {
            AppLog.recipes.error("Invalid URL provided.")
            isLoading = false
            return nil
        }

        var scrapedText = ""
        do {
            let (data, response) = try await URLSession.shared.data(from: urlObj)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let htmlString = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }

            let document = try SwiftSoup.parse(htmlString)
            let paragraphs = try document.select("p").array().map { try $0.text() }
            let lists = try document.select("li").array().map { try $0.text() }
            let headers = try document.select("h1, h2, h3, h4").array().map { try $0.text() }

            let combined = headers + paragraphs + lists
            let fullText = combined.joined(separator: "\n")
            scrapedText = String(fullText.prefix(8000))
        } catch {
            AppLog.recipes.error("Failed to scrape URL: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            return nil
        }

        let prompt = RecipeRules.createRecipeFromURLPrompt(scrapedText: scrapedText)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                DIContainer.shared.analyticsManager?.logEvent("url_recipe_imported", parameters: nil)
                isLoading = false
                return savedRecipe
            } catch {
                AppLog.recipes.error("Recipe parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying URL recipe import.")
                    return await createRecipeFromURL(url: url, userID: userID, retryCount: retryCount - 1)
                }
                isLoading = false
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("URL Recipe import request failed: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            return nil
        }
    }

    // ... [CRUD Operations - Keep Existing] ...

    public func fetchUserRecipes() async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        isLoading = true
        do {
            self.userRecipes = try await DIContainer.shared.nutritionRepository.fetchRecipes(userID: userID)
        } catch {
            AppLog.recipes.error("Failed to fetch user recipes: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    @discardableResult
    public func saveRecipe(_ recipe: Recipe, for userID: String) async throws -> Recipe {
        let savedRecipe = try await DIContainer.shared.nutritionRepository.saveRecipe(userID: userID, recipe: recipe)
        DIContainer.shared.analyticsManager?.logEvent("recipe_created", parameters: nil)

        if let recipeID = savedRecipe.id,
           let index = userRecipes.firstIndex(where: { $0.id == recipeID }) {
            userRecipes[index] = savedRecipe
        } else {
            userRecipes.append(savedRecipe)
        }

        return savedRecipe
    }

    public func deleteRecipe(recipe: Recipe) async {
        guard let userID = DIContainer.shared.authService.currentUserID, let recipeID = recipe.id else { return }
        do {
            try await DIContainer.shared.nutritionRepository.deleteRecipe(userID: userID, recipeID: recipeID)
            if let index = userRecipes.firstIndex(where: { $0.id == recipeID }) { userRecipes.remove(at: index) }
        } catch {
            AppLog.recipes.error("Failed to delete recipe: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func recipeToFoodItem(recipe: Recipe) -> FoodItem {
        let nutrition = recipe.nutrition
        var food = FoodItem(id: recipe.id ?? UUID().uuidString, name: recipe.name, calories: nutrition.calories, protein: nutrition.protein, carbs: nutrition.carbs, fats: nutrition.fats, saturatedFat: nutrition.saturatedFat, polyunsaturatedFat: nutrition.polyunsaturatedFat, monounsaturatedFat: nutrition.monounsaturatedFat, fiber: nutrition.fiber, servingSize: "1 serving", servingWeight: 0, timestamp: nil, sourceMetadata: FoodSourceMetadata(sourceType: .recipe, confidence: .userVerified, reviewStatus: .notRequired, sourceName: "Recipe", sourceID: recipe.id), calcium: nutrition.calcium, iron: nutrition.iron, potassium: nutrition.potassium, sodium: nutrition.sodium, vitaminA: nutrition.vitaminA, vitaminC: nutrition.vitaminC, vitaminD: nutrition.vitaminD, vitaminB12: nutrition.vitaminB12, folate: nutrition.folate)
        food.quantityValue = 1.0
        food.servingUnit = "serving"
        return food
    }

}
