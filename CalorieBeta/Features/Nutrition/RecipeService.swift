import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics
import SwiftSoup

@MainActor
class RecipeService: ObservableObject {
    private let db = Firestore.firestore()

    @Published var userRecipes: [Recipe] = []
    @Published var isLoading = false

    // MARK: - AI Recipe Generation (Refactored)
    func createRecipeFromAI(description: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        let prompt = """
        Analyze the recipe description: "\(description)".
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        // Use the centralized service
        let result = await AIService.shared.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0 // We handle logic retries below
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                Analytics.logEvent("ai_recipe_generated", parameters: nil)
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

    func createRecipeFromText(text: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        let prompt = """
        Extract the recipe from the following text: "\(text)".
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium). If nutritional info is not provided in the text, estimate it based on the ingredients for 1 serving.
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await AIService.shared.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                Analytics.logEvent("ai_recipe_text_imported", parameters: nil)
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

    func createRecipeFromPantry(itemsString: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        isLoading = true

        let prompt = """
        Generate a healthy, macro-conscious recipe STRICTLY using ONLY the following ingredients: "\(itemsString)".
        Do NOT assume the user has salt, pepper, oil, water, or any other household staples unless explicitly listed above.
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings containing exactly what was used), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await AIService.shared.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try parseRecipeFromAIResponse(jsonString)
                Analytics.logEvent("ai_recipe_pantry_generated", parameters: nil)
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

    func createRecipesFromPantry(itemsString: String, userID: String, retryCount: Int = 1) async -> [Recipe] {
        isLoading = true

        let prompt = """
        Generate 3 distinct, healthy, macro-conscious recipes STRICTLY using ONLY the following ingredients: "\(itemsString)".
        Do NOT assume the user has salt, pepper, oil, water, or any other household staples unless explicitly listed above.
        Return a JSON object with a single key "recipes" whose value is an array of exactly 3 recipe objects. Each recipe object has keys: "name" (string), "ingredients" (array of strings containing exactly what was used), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await AIService.shared.performRequest(
            messages: messages,
            temperature: 0.6,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipes = try parseRecipesFromAIResponse(jsonString)
                Analytics.logEvent("ai_recipe_pantry_generated", parameters: ["count": recipes.count])
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

    func createRecipeFromURL(url: String, userID: String, retryCount: Int = 1) async -> Recipe? {
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

        let prompt = """
        I scraped the following text from a recipe blog:
        ---
        \(scrapedText)
        ---
        Extract the recipe from this text.
        Return a structured JSON object with keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sodium).
        If nutrition data is missing, carefully estimate it based on the ingredients for 1 serving.
        """

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await AIService.shared.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                Analytics.logEvent("url_recipe_imported", parameters: nil)
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

    func fetchUserRecipes() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        let userRecipesCollection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes)
        do {
            let snapshot = try await userRecipesCollection.getDocuments()
            self.userRecipes = snapshot.documents.compactMap { document -> Recipe? in
                try? document.data(as: Recipe.self)
            }
        } catch {
            AppLog.recipes.error("Failed to fetch user recipes: \(error.localizedDescription, privacy: .public)")
        }
        isLoading = false
    }

    @discardableResult
    func saveRecipe(_ recipe: Recipe, for userID: String) async throws -> Recipe {
        let userRecipesCollection = db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes)
        var recipeToSave = recipe
        if let id = recipeToSave.id {
            try userRecipesCollection.document(id).setData(from: recipeToSave)
        } else {
            let newDocRef = userRecipesCollection.document()
            recipeToSave.id = newDocRef.documentID
            try newDocRef.setData(from: recipeToSave)
            Analytics.logEvent("recipe_created", parameters: nil)
        }

        if let recipeID = recipeToSave.id,
           let index = userRecipes.firstIndex(where: { $0.id == recipeID }) {
            userRecipes[index] = recipeToSave
        } else {
            userRecipes.append(recipeToSave)
        }

        return recipeToSave
    }

    func deleteRecipe(recipe: Recipe) async {
        guard let userID = Auth.auth().currentUser?.uid, let recipeID = recipe.id else { return }
        do {
            try await db.collection(FirestoreCollection.users).document(userID).collection(FirestoreCollection.recipes).document(recipeID).delete()
            if let index = userRecipes.firstIndex(where: { $0.id == recipeID }) { userRecipes.remove(at: index) }
        } catch {
            AppLog.recipes.error("Failed to delete recipe: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recipeToFoodItem(recipe: Recipe) -> FoodItem {
        let nutrition = recipe.nutrition
        return FoodItem(id: recipe.id ?? UUID().uuidString, name: recipe.name, calories: nutrition.calories, protein: nutrition.protein, carbs: nutrition.carbs, fats: nutrition.fats, saturatedFat: nutrition.saturatedFat, polyunsaturatedFat: nutrition.polyunsaturatedFat, monounsaturatedFat: nutrition.monounsaturatedFat, fiber: nutrition.fiber, servingSize: "1 serving", servingWeight: 0, timestamp: nil, calcium: nutrition.calcium, iron: nutrition.iron, potassium: nutrition.potassium, sodium: nutrition.sodium, vitaminA: nutrition.vitaminA, vitaminC: nutrition.vitaminC, vitaminD: nutrition.vitaminD, vitaminB12: nutrition.vitaminB12, folate: nutrition.folate, quantityValue: 1.0, servingUnit: "serving")
    }

    private struct AIRecipeResponse: Codable {
        let name: String
        let ingredients: [String]
        let instructions: [String]
        let nutrition: Nutrition
    }

    private func parseRecipeFromAIResponse(_ jsonString: String) throws -> Recipe {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "RecipeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data."])
        }
        let response = try JSONDecoder().decode(AIRecipeResponse.self, from: jsonData)
        return Recipe(name: response.name, ingredients: response.ingredients, detailedIngredients: nil, instructions: response.instructions, nutrition: response.nutrition, servings: 1.0)
    }

    private struct AIPantryRecipesResponse: Codable {
        let recipes: [AIRecipeResponse]
    }

    private func parseRecipesFromAIResponse(_ jsonString: String) throws -> [Recipe] {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "RecipeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data."])
        }
        let response = try JSONDecoder().decode(AIPantryRecipesResponse.self, from: jsonData)
        return response.recipes.map {
            Recipe(name: $0.name, ingredients: $0.ingredients, detailedIngredients: nil, instructions: $0.instructions, nutrition: $0.nutrition, servings: 1.0)
        }
    }
}
