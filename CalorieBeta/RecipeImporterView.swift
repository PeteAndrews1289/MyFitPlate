import SwiftUI

struct RecipeImporterView: View {
    @StateObject private var importerService = RecipeImporterService()
    @EnvironmentObject var recipeService: RecipeService
    @Environment(\.dismiss) var dismiss

    @State private var urlString: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    @State private var importedRecipe: UserRecipe? = nil
    @State private var showCreateRecipeView: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Import a Recipe from a Website")
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Text("Paste the URL of a recipe page, and our AI will attempt to extract the details for you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("https://www.example.com/recipe", text: $urlString)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                Spacer()
                
                Button(action: importRecipe) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isLoading ? "Importing..." : "Import Recipe")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(urlString.isEmpty || isLoading)
                .padding(.horizontal)

            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateRecipeView, onDismiss: {
                dismiss()
            }) {
                if let recipe = importedRecipe {
                    CreateRecipeView(recipeService: recipeService, recipeToEdit: recipe)
                }
            }
        }
    }
    
    private func importRecipe() {
        print("--- IMPORT RECIPE BUTTON TAPPED ---")
        isLoading = true
        errorMessage = nil
        
        Task {
            print("--- Task started in importRecipe ---")
            print("URL being passed to service: '\(urlString)'")

            let result = await importerService.fetchAndParseRecipe(from: urlString)
            
            print("--- Service call finished. Result: ---")
            dump(result)

            isLoading = false
            
            switch result {
            case .success(let recipe):
                print("Success: Recipe named '\(recipe.name)' parsed.")
                self.importedRecipe = recipe
                self.showCreateRecipeView = true
                
            case .failure(let error):
                print("Failure: Error received: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
