import SwiftUI

struct CreateRecipeView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var bannerService: BannerService
    
    @State private var recipeName = ""
    @State private var ingredients: [FoodItem] = []
    @State private var instructions = ""
    @State private var showingFoodSearch = false
    @State private var creationMode: CreationMode = .ai
    @State private var aiDescription = ""
    @State private var isLoading = false

    enum CreationMode: String, CaseIterable, Identifiable {
        case ai = "AI"
        case text = "Paste Text"
        case url = "Web URL"
        case manual = "Manual"
        var id: Self { self }
    }
    
    private var totalNutrition: Nutrition {
        ingredients.reduce(Nutrition.zero) { partialResult, item in
            return Nutrition(
                calories: partialResult.calories + item.calories,
                protein: partialResult.protein + item.protein,
                carbs: partialResult.carbs + item.carbs,
                fats: partialResult.fats + item.fats,
                saturatedFat: (partialResult.saturatedFat ?? 0) + (item.saturatedFat ?? 0),
                polyunsaturatedFat: (partialResult.polyunsaturatedFat ?? 0) + (item.polyunsaturatedFat ?? 0),
                monounsaturatedFat: (partialResult.monounsaturatedFat ?? 0) + (item.monounsaturatedFat ?? 0),
                fiber: (partialResult.fiber ?? 0) + (item.fiber ?? 0),
                calcium: (partialResult.calcium ?? 0) + (item.calcium ?? 0),
                iron: (partialResult.iron ?? 0) + (item.iron ?? 0),
                potassium: (partialResult.potassium ?? 0) + (item.potassium ?? 0),
                sodium: (partialResult.sodium ?? 0) + (item.sodium ?? 0),
                vitaminA: (partialResult.vitaminA ?? 0) + (item.vitaminA ?? 0),
                vitaminC: (partialResult.vitaminC ?? 0) + (item.vitaminC ?? 0),
                vitaminD: (partialResult.vitaminD ?? 0) + (item.vitaminD ?? 0),
                vitaminB12: (partialResult.vitaminB12 ?? 0) + (item.vitaminB12 ?? 0),
                folate: (partialResult.folate ?? 0) + (item.folate ?? 0)
            )
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            CreateRecipeHeroCard(mode: creationMode)
                            CreateRecipeModePicker(selection: $creationMode)

                            if creationMode == .ai {
                                aiSection
                            } else if creationMode == .text {
                                textSection
                            } else if creationMode == .url {
                                urlSection
                            } else {
                                manualSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    CreateRecipeActionBar(
                        title: creationMode == .ai ? "Generate Recipe" : (creationMode == .text ? "Import Recipe" : (creationMode == .url ? "Import Recipe" : "Save Recipe")),
                        isEnabled: !isSaveDisabled,
                        action: saveRecipe
                    )
                }
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .navigationTitle("Create Recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .sheet(isPresented: $showingFoodSearch) {
                    FoodSearchView(
                        dailyLog: $dailyLogService.currentDailyLog,
                        onFoodItemLogged: nil,
                        onFoodItemSelected: addIngredient,
                        searchContext: "recipe_ingredient"
                    )
                }
                
                if isLoading {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView(creationMode == .ai ? "Generating Recipe..." : (creationMode == .text || creationMode == .url ? "Importing Recipe..." : "Saving Recipe..."))
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding().background(Color.black.opacity(0.8)).cornerRadius(10)
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreateRecipeSectionHeader(title: "Describe Your Recipe", icon: "sparkles")

            Text("Tell Maia what you want to make, including portions, ingredients, cuisine, and macro goals if you have them.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $aiDescription)
                .frame(minHeight: 180)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Example: High-protein chicken burrito bowl for 2 servings, around 600 calories each...")
                            .appFont(size: 14, weight: .medium)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @State private var importText = ""

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreateRecipeSectionHeader(title: "Paste Recipe", icon: "doc.on.clipboard.fill")

            Text("Paste a recipe generated by ChatGPT, Claude, or any text source. Maia will extract the ingredients and instructions.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $importText)
                .frame(minHeight: 180)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Paste your recipe text here...")
                            .appFont(size: 14, weight: .medium)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @State private var importURL = ""

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CreateRecipeSectionHeader(title: "Import from URL", icon: "link")

            Text("Paste a link to a recipe blog or website. Maia will extract the ingredients and instructions for you.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://...", text: $importURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(14)
                .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var manualSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                CreateRecipeSectionHeader(title: "Recipe Details", icon: "text.book.closed.fill")

                TextField("Recipe name", text: $recipeName)
                    .appFont(size: 22, weight: .bold)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if !ingredients.isEmpty {
                CreateRecipeNutritionPreview(nutrition: totalNutrition)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    CreateRecipeSectionHeader(title: "Ingredients", icon: "basket.fill")
                    Spacer()
                    Button(action: { showingFoodSearch = true }) {
                        Image(systemName: "plus")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add ingredient")
                }

                if ingredients.isEmpty {
                    CreateRecipeInlineEmptyState(
                        icon: "plus.circle.fill",
                        title: "No ingredients yet",
                        message: "Search for foods to build nutrition automatically."
                    )
                } else {
                    VStack(spacing: 9) {
                        ForEach(ingredients) { ingredient in
                            CreateRecipeIngredientRow(
                                ingredient: ingredient,
                                onRemove: { removeIngredient(ingredient) }
                            )
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                CreateRecipeSectionHeader(title: "Instructions", icon: "text.badge.checkmark")

                TextEditor(text: $instructions)
                    .frame(minHeight: 170)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Put each step on a new line.")
                                .appFont(size: 14, weight: .medium)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(16)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func addIngredient(foodItem: FoodItem) {
        var ingredient = foodItem
        ingredient.id = UUID().uuidString
        ingredients.append(ingredient)
        showingFoodSearch = false
        HapticManager.instance.feedback(.light)
    }

    private func removeIngredient(_ ingredient: FoodItem) {
        ingredients.removeAll { $0.id == ingredient.id }
        HapticManager.instance.feedback(.light)
    }

    private var isSaveDisabled: Bool {
        if creationMode == .ai {
            return aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else if creationMode == .text {
            return importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else if creationMode == .url {
            return importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                ingredients.isEmpty ||
                instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func saveRecipe() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        HapticManager.instance.feedback(.medium)
        isLoading = true

        Task {
            var success = false
            if creationMode == .ai {
                let recipe = await recipeService.createRecipeFromAI(description: aiDescription, userID: userID)
                success = (recipe != nil)
            } else if creationMode == .text {
                let recipe = await recipeService.createRecipeFromText(text: importText, userID: userID)
                success = (recipe != nil)
            } else if creationMode == .url {
                let recipe = await recipeService.createRecipeFromURL(url: importURL, userID: userID)
                success = (recipe != nil)
            } else {
                let ingredientNames = ingredients.map { $0.name }
                let instructionSteps = instructions.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let recipe = Recipe(
                    name: recipeName.trimmingCharacters(in: .whitespacesAndNewlines),
                    ingredients: ingredientNames,
                    detailedIngredients: ingredients,
                    instructions: instructionSteps,
                    nutrition: totalNutrition,
                    servings: 1.0
                )
                do {
                    _ = try await recipeService.saveRecipe(recipe, for: userID)
                    success = true
                } catch {
                    success = false
                }
            }
            
            isLoading = false
            if success {
                bannerService.showBanner(title: "Recipe Saved", message: "Your recipe is now in the library", iconName: "checkmark.circle.fill", iconColor: .accentPositive)
                dismiss()
            } else {
                bannerService.showBanner(title: "Import Failed", message: "Could not parse or save the recipe. Please try again.", iconName: "exclamationmark.triangle.fill", iconColor: .orange)
            }
        }
    }
}

private struct CreateRecipeHeroCard: View {
    let mode: CreateRecipeView.CreationMode

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: mode == .ai ? "sparkles" : (mode == .text ? "doc.on.clipboard.fill" : (mode == .url ? "link" : "text.book.closed.fill")))
                .appFont(size: 25, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(mode == .ai ? "Generate with Maia" : (mode == .text ? "Paste Text" : (mode == .url ? "Import from URL" : "Build Manually")))
                    .appFont(size: 24, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text(mode == .ai ? "Describe the meal and let Maia draft ingredients, steps, and nutrition." : (mode == .text ? "Paste recipe text generated by ChatGPT or Claude and Maia will extract it." : (mode == .url ? "Paste a recipe URL and Maia will extract the rest." : "Add ingredients from food search and write your own steps.")))
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct CreateRecipeModePicker: View {
    @Binding var selection: CreateRecipeView.CreationMode

    var body: some View {
        HStack(spacing: 7) {
            ForEach(CreateRecipeView.CreationMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode == .ai ? "Maia" : (mode == .text ? "Paste" : (mode == .url ? "URL" : "Manual")), systemImage: mode == .ai ? "sparkles" : (mode == .text ? "doc.on.clipboard.fill" : (mode == .url ? "link" : "hand.draw.fill")))
                        .appFont(size: 13, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            selection == mode ? Color.brandPrimary.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .foregroundColor(selection == mode ? .brandPrimary : Color(UIColor.secondaryLabel))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct CreateRecipeSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)
        }
    }
}

private struct CreateRecipeNutritionPreview: View {
    let nutrition: Nutrition

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            CreateRecipeMetric(title: "Calories", value: "\(Int(nutrition.calories.rounded()))", unit: "cal", color: .orange)
            CreateRecipeMetric(title: "Protein", value: "\(Int(nutrition.protein.rounded()))", unit: "g", color: .accentProtein)
            CreateRecipeMetric(title: "Carbs", value: "\(Int(nutrition.carbs.rounded()))", unit: "g", color: .accentCarbs)
            CreateRecipeMetric(title: "Fat", value: "\(Int(nutrition.fats.rounded()))", unit: "g", color: .accentFats)
        }
    }
}

private struct CreateRecipeMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(color)
                    .lineLimit(1)

                Text(unit)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CreateRecipeIngredientRow: View {
    let ingredient: FoodItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(FoodEmojiMapper.getEmoji(for: ingredient.name))
                .appFont(size: 22)
                .frame(width: 42, height: 42)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text("Cal \(Int(ingredient.calories.rounded()))  P \(Int(ingredient.protein.rounded()))g  C \(Int(ingredient.carbs.rounded()))g  F \(Int(ingredient.fats.rounded()))g")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(ingredient.name)")
        }
        .padding(12)
        .background(Color.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CreateRecipeInlineEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 21, weight: .semibold)
                .foregroundColor(.brandPrimary)
            Text(title)
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(message)
                .appFont(size: 12, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.backgroundPrimary.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CreateRecipeActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isEnabled)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(Color.backgroundPrimary.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
            }
    }
}
