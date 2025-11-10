import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class RecipeService: ObservableObject {
    private let db = Firestore.firestore()
    private let apiKey = getAPIKey()
    
    @Published var userRecipes: [Recipe] = []
    @Published var isLoading = false

    func createRecipeFromAI(description: String, userID: String) async -> Recipe? {
        isLoading = true
        let prompt = """
        Analyze the recipe description below. Return a structured JSON object with the recipe's name, ingredients, instructions, and a detailed nutritional breakdown per serving.

        Description: "\(description)"

        The JSON object MUST have these exact keys: "name" (string), "ingredients" (array of strings), "instructions" (array of strings), and "nutrition" (an object).
        The "nutrition" object MUST contain: "calories", "protein", "carbs", "fats", "saturatedFat", "polyunsaturatedFat", "monounsaturatedFat", "fiber", "calcium", "iron", "potassium", "sodium", "vitaminA", "vitaminC", "vitaminD", "vitaminB12", and "folate". All nutritional values should be numbers.

        Example Response:
        {
          "name": "Healthy Chicken Salad",
          "ingredients": ["3 oz cooked chicken breast", "1 tbsp greek yogurt", "1 stalk celery, chopped", "1/4 apple, diced"],
          "instructions": ["Mix all ingredients in a bowl.", "Serve chilled."],
          "nutrition": {
            "calories": 250,
            "protein": 30,
            "carbs": 8,
            "fats": 10,
            "saturatedFat": 2.1,
            "polyunsaturatedFat": 3.0,
            "monounsaturatedFat": 4.5,
            "fiber": 2.0,
            "calcium": 45,
            "iron": 1.1,
            "potassium": 300,
            "sodium": 250,
            "vitaminA": 50,
            "vitaminC": 5,
            "vitaminD": 0.2,
            "vitaminB12": 0.3,
            "folate": 10
          }
        }
        """

        guard let aiResponse = await fetchAIResponse(prompt: prompt) else {
            isLoading = false
            return nil
        }

        do {
            var recipe = try parseRecipeFromAIResponse(aiResponse)
            try await saveRecipe(recipe, for: userID)
            userRecipes.append(recipe)
            isLoading = false
            return recipe
        } catch {
            print("Error creating or saving AI recipe: \(error)")
            isLoading = false
            return nil
        }
    }
    
    func fetchUserRecipes() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        let userRecipesCollection = db.collection("users").document(userID).collection("recipes")
        
        do {
            let snapshot = try await userRecipesCollection.getDocuments()
            self.userRecipes = snapshot.documents.compactMap { document -> Recipe? in
                try? document.data(as: Recipe.self)
            }
        } catch {
            print("Error fetching user recipes: \(error)")
        }
        
        isLoading = false
    }

    func saveRecipe(_ recipe: Recipe, for userID: String) async throws {
        let userRecipesCollection = db.collection("users").document(userID).collection("recipes")
        var recipeToSave = recipe
        
        // If the recipe already has an ID, use it, otherwise let Firestore generate one.
        if let id = recipeToSave.id {
            try userRecipesCollection.document(id).setData(from: recipeToSave)
        } else {
            let newDocRef = userRecipesCollection.document()
            recipeToSave.id = newDocRef.documentID
            try newDocRef.setData(from: recipeToSave)
        }
    }
    
    func deleteRecipe(recipe: Recipe) async {
        guard let userID = Auth.auth().currentUser?.uid, let recipeID = recipe.id else { return }
        
        do {
            try await db.collection("users").document(userID).collection("recipes").document(recipeID).delete()
            if let index = userRecipes.firstIndex(where: { $0.id == recipeID }) {
                userRecipes.remove(at: index)
            }
        } catch {
            print("Error deleting recipe: \(error)")
        }
    }
    
    func recipeToFoodItem(recipe: Recipe) -> FoodItem {
        let nutrition = recipe.nutrition
        return FoodItem(
            id: recipe.id ?? UUID().uuidString,
            name: recipe.name,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbs: nutrition.carbs,
            fats: nutrition.fats,
            saturatedFat: nutrition.saturatedFat,
            polyunsaturatedFat: nutrition.polyunsaturatedFat,
            monounsaturatedFat: nutrition.monounsaturatedFat,
            fiber: nutrition.fiber,
            servingSize: "1 serving",
            servingWeight: 0,
            calcium: nutrition.calcium,
            iron: nutrition.iron,
            potassium: nutrition.potassium,
            sodium: nutrition.sodium,
            vitaminA: nutrition.vitaminA,
            vitaminC: nutrition.vitaminC,
            vitaminD: nutrition.vitaminD,
            vitaminB12: nutrition.vitaminB12,
            folate: nutrition.folate
        )
    }

    private func fetchAIResponse(prompt: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [ "model": "gpt-4o-mini", "messages": [["role": "user", "content": prompt]], "max_tokens": 2048, "temperature": 0.3, "response_format": ["type": "json_object"] ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any], let content = message["content"] as? String {
                return content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch { }
        return nil
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
        
        return Recipe(
            name: response.name,
            ingredients: response.ingredients,
            instructions: response.instructions,
            nutrition: response.nutrition
        )
    }
}
