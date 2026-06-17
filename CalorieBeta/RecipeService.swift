import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

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
        Return a structured JSON object with keys: "name", "ingredients" (array), "instructions" (array), "nutrition" (object with calories, protein, carbs, fats, saturatedFat, fiber, sugars, sodium).
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
                var recipe = try parseRecipeFromAIResponse(jsonString)
                try await saveRecipe(recipe, for: userID)
                Analytics.logEvent("ai_recipe_generated", parameters: ["recipe_name": recipe.name])
                userRecipes.append(recipe)
                isLoading = false
                return recipe
            } catch {
                print("❌ Recipe Parsing Error: \(error)")
                if retryCount > 0 {
                    print("🔄 Retrying recipe generation...")
                    return await createRecipeFromAI(description: description, userID: userID, retryCount: retryCount - 1)
                }
                isLoading = false
                return nil
            }
        case .failure(let error):
            print("❌ AI Service Error: \(error.localizedDescription)")
            isLoading = false
            return nil
        }
    }
    
    // ... [CRUD Operations - Keep Existing] ...
    
    func fetchUserRecipes() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        let userRecipesCollection = db.collection("users").document(userID).collection("recipes")
        do {
            let snapshot = try await userRecipesCollection.getDocuments()
            self.userRecipes = snapshot.documents.compactMap { document -> Recipe? in
                try? document.data(as: Recipe.self)
            }
        } catch { print("Error fetching user recipes: \(error)") }
        isLoading = false
    }

    func saveRecipe(_ recipe: Recipe, for userID: String) async throws {
        let userRecipesCollection = db.collection("users").document(userID).collection("recipes")
        var recipeToSave = recipe
        if let id = recipeToSave.id {
            try userRecipesCollection.document(id).setData(from: recipeToSave)
        } else {
            let newDocRef = userRecipesCollection.document()
            recipeToSave.id = newDocRef.documentID
            try newDocRef.setData(from: recipeToSave)
            Analytics.logEvent("recipe_created", parameters: ["recipe_name": recipe.name])
        }
    }
    
    func deleteRecipe(recipe: Recipe) async {
        guard let userID = Auth.auth().currentUser?.uid, let recipeID = recipe.id else { return }
        do {
            try await db.collection("users").document(userID).collection("recipes").document(recipeID).delete()
            if let index = userRecipes.firstIndex(where: { $0.id == recipeID }) { userRecipes.remove(at: index) }
        } catch { print("Error deleting recipe: \(error)") }
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
        return Recipe(name: response.name, ingredients: response.ingredients, instructions: response.instructions, nutrition: response.nutrition)
    }
}
