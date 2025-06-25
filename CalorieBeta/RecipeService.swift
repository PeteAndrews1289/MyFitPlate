import Foundation
import FirebaseFirestore
import FirebaseAuth

class RecipeService: ObservableObject {
    private let db = Firestore.firestore()
    private var recipesListener: ListenerRegistration?

    @Published var userRecipes: [UserRecipe] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Firestore collection reference for user-specific recipes
    private func recipesCollectionRef(for userID: String) -> CollectionReference {
        return db.collection("users").document(userID).collection("recipes")
    }

    // MARK: - CRUD Operations

    // Fetch recipes for the current user
    @MainActor
    func fetchUserRecipes() {
        guard let userID = Auth.auth().currentUser?.uid else {
            errorMessage = "User not logged in."
            userRecipes = []
            return
        }

        isLoading = true
        errorMessage = nil
        recipesListener?.remove() // Remove previous listener

        recipesListener = recipesCollectionRef(for: userID)
            .order(by: "name", descending: false) // Order alphabetically
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                isLoading = false

                if let error = error {
                    self.errorMessage = "Error fetching recipes: \(error.localizedDescription)"
                    print("❌ Error fetching recipes: \(error.localizedDescription)")
                    self.userRecipes = []
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    self.errorMessage = "No recipe documents found."
                    self.userRecipes = []
                    return
                }

                self.userRecipes = documents.compactMap { document -> UserRecipe? in
                    do {
                        let recipe = try document.data(as: UserRecipe.self)
                        print("✅ Successfully decoded recipe: \(recipe.name)")
                        return recipe
                    } catch let error {
                        print("❌ Error decoding recipe document \(document.documentID): \(error)")
                        // Added detailed debug information
                        if let decodingError = error as? DecodingError {
                            switch decodingError {
                            case .keyNotFound(let key, let context):
                                print("    - Key '\(key.stringValue)' not found. Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                                print("    - Debug Description: \(context.debugDescription)")
                            case .valueNotFound(let type, let context):
                                print("    - Value of type '\(type)' not found. Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                                print("    - Debug Description: \(context.debugDescription)")
                            case .typeMismatch(let type, let context):
                                print("    - Type mismatch for type '\(type)'. Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                                print("    - Debug Description: \(context.debugDescription)")
                            case .dataCorrupted(let context):
                                print("    - Data corrupted. Path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                                print("    - Debug Description: \(context.debugDescription)")
                            @unknown default:
                                print("    - An unknown decoding error occurred.")
                            }
                        }
                        return nil
                    }
                }
                 print("✅ Fetched \(self.userRecipes.count) user recipes.")
            }
    }

    // Save a new recipe or update an existing one
    func saveRecipe(_ recipe: UserRecipe, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "App", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }

        var recipeToSave = recipe
        recipeToSave.userID = userID // Ensure userID is set
        recipeToSave.calculateTotals() // Recalculate totals before saving
        recipeToSave.updatedAt = Timestamp(date: Date()) // Update timestamp
        
        print("\n--- RecipeService: Attempting to save recipe ---")
        dump(recipeToSave)

        let collectionRef = recipesCollectionRef(for: userID)

        do {
            if let id = recipeToSave.id, !id.isEmpty {
                // Update existing recipe
                 print("RecipeService: Updating recipe \(id)")
                try collectionRef.document(id).setData(from: recipeToSave, merge: true) { error in
                    if let error = error { completion(.failure(error)) } else { completion(.success(())) }
                }
            } else {
                // Add new recipe (Firestore generates ID)
                 print("RecipeService: Adding new recipe")
                var newRecipe = recipeToSave
                newRecipe.createdAt = Timestamp(date: Date()) // Set created time
                _ = try collectionRef.addDocument(from: newRecipe) { error in
                    if let error = error { completion(.failure(error)) } else { completion(.success(())) }
                }
            }
        } catch {
            print("❌ Error encoding or saving recipe: \(error)")
            completion(.failure(error))
        }
    }

    // Delete a recipe
    func deleteRecipe(_ recipe: UserRecipe, completion: @escaping (Error?) -> Void) {
        guard let userID = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "App", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        guard let recipeID = recipe.id else {
            completion(NSError(domain: "App", code: 400, userInfo: [NSLocalizedDescriptionKey: "Recipe has no ID"]))
            return
        }
        print("RecipeService: Deleting recipe \(recipeID)")
        recipesCollectionRef(for: userID).document(recipeID).delete { error in
            completion(error)
        }
    }

    // Call this when the user logs out or the service is no longer needed
    func stopListening() {
        recipesListener?.remove()
        recipesListener = nil
        userRecipes = []
        print("RecipeService: Stopped listening for recipe updates.")
    }
}
