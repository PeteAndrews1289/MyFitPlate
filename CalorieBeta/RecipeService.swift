import Foundation
import FirebaseFirestore
import FirebaseAuth

class RecipeService: ObservableObject {
    private let db = Firestore.firestore()
    private var recipesListener: ListenerRegistration?
    private let foodAPIService = FatSecretFoodAPIService()

    @Published var userRecipes: [UserRecipe] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    weak var achievementService: AchievementService?

    private func recipesCollectionRef(for userID: String) -> CollectionReference {
        return db.collection("users").document(userID).collection("recipes")
    }

    @MainActor
    func fetchUserRecipes() {
        guard let userID = Auth.auth().currentUser?.uid else {
            errorMessage = "User not logged in."
            userRecipes = []
            return
        }

        isLoading = true
        errorMessage = nil
        recipesListener?.remove()

        recipesListener = recipesCollectionRef(for: userID)
            .order(by: "name", descending: false)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.errorMessage = "Error fetching recipes: \(error.localizedDescription)"
                    self.userRecipes = []
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    self.userRecipes = []
                    return
                }

                self.userRecipes = documents.compactMap { document in
                    try? document.data(as: UserRecipe.self)
                }
            }
    }

    func saveRecipe(_ recipe: UserRecipe, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "App", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }

        var recipeToSave = recipe
        recipeToSave.userID = userID
        recipeToSave.calculateTotals()
        recipeToSave.updatedAt = Timestamp(date: Date())
        
        let collectionRef = recipesCollectionRef(for: userID)

        do {
            if let id = recipeToSave.id, !id.isEmpty {
                try collectionRef.document(id).setData(from: recipeToSave, merge: true) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                        Task { @MainActor in
                            self.achievementService?.checkRecipeCountAchievements(userID: userID)
                        }
                    }
                }
            } else {
                var newRecipe = recipeToSave
                newRecipe.createdAt = Timestamp(date: Date())
                _ = try collectionRef.addDocument(from: newRecipe) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                        Task { @MainActor in
                            self.achievementService?.checkRecipeCountAchievements(userID: userID)
                        }
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func deleteRecipe(_ recipe: UserRecipe, completion: @escaping (Error?) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "App", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        guard let recipeID = recipe.id else {
            completion(NSError(domain: "App", code: 400, userInfo: [NSLocalizedDescriptionKey: "Recipe has no ID"]))
            return
        }
        recipesCollectionRef(for: userID).document(recipeID).delete(completion: completion)
    }
    
    func migrateUserRecipesToIncludeMicronutrients(completion: @escaping (String) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion("Error: User not logged in.")
            return
        }

        let recipesRef = recipesCollectionRef(for: userID)
        recipesRef.getDocuments { [weak self] snapshot, error in
            guard let self = self, let documents = snapshot?.documents, error == nil else {
                completion("Error fetching recipes: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            let recipesToMigrate = documents.compactMap { try? $0.data(as: UserRecipe.self) }
            if recipesToMigrate.isEmpty {
                completion("No recipes to migrate.")
                return
            }
            
            let group = DispatchGroup()
            var updatedCount = 0
            
            for var recipe in recipesToMigrate {
                group.enter()
                Task {
                    var updatedIngredients: [RecipeIngredient] = []
                    for ingredient in recipe.ingredients {
                        if let foodId = ingredient.foodId {
                            let detailsResult = await self.fetchIngredientDetails(foodId: foodId)
                            if let newIngredientData = detailsResult {
                                var updatedIngredient = ingredient
                                updatedIngredient.fiber = newIngredientData.fiber
                                updatedIngredient.calcium = newIngredientData.calcium
                                updatedIngredients.append(updatedIngredient)
                            } else {
                                updatedIngredients.append(ingredient)
                            }
                        } else {
                            updatedIngredients.append(ingredient)
                        }
                    }
                    
                    recipe.ingredients = updatedIngredients
                    recipe.calculateTotals()
                    
                    self.saveRecipe(recipe) { result in
                        if case .success = result {
                            updatedCount += 1
                        }
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                completion("Migration complete. Updated \(updatedCount) of \(recipesToMigrate.count) recipes.")
            }
        }
    }
    
    private func fetchIngredientDetails(foodId: String) async -> ServingSizeOption? {
        return await withCheckedContinuation { continuation in
            foodAPIService.fetchFoodDetails(foodId: foodId) { result in
                switch result {
                case .success(let (_, servings)):
                    continuation.resume(returning: servings.first)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func stopListening() {
        recipesListener?.remove()
        recipesListener = nil
        userRecipes = []
    }
}
