import SwiftUI

struct CreateRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeService: RecipeService
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var bannerService: BannerService

    private let recipeToEdit: Recipe?
    private let onSaved: ((Recipe) -> Void)?

    @State private var recipeName = ""
    @State private var ingredients: [FoodItem] = []
    @State private var instructions = ""
    @State private var showingFoodSearch = false
    @State private var creationMode: CreationMode = .ai
    @State private var aiDescription = ""
    @State private var importText = ""
    @State private var importURL = ""
    @State private var isLoading = false

    init(recipeToEdit: Recipe? = nil, onSaved: ((Recipe) -> Void)? = nil) {
        self.recipeToEdit = recipeToEdit
        self.onSaved = onSaved
        if let recipe = recipeToEdit {
            _recipeName = State(initialValue: recipe.name)
            _ingredients = State(
                initialValue: recipe.detailedIngredients
                    ?? recipe.ingredients.map { FoodItem(name: $0) }
            )
            _instructions = State(initialValue: recipe.instructions.joined(separator: "\n"))
            _creationMode = State(initialValue: .manual)
        }
    }

    enum CreationMode: String, CaseIterable, Identifiable {
        case ai
        case text
        case url
        case manual

        var id: Self { self }

        var shortTitle: String {
            switch self {
            case .ai: "Maia"
            case .text: "Paste"
            case .url: "URL"
            case .manual: "Manual"
            }
        }

        var title: String {
            switch self {
            case .ai: "Generate with Maia"
            case .text: "Import Pasted Text"
            case .url: "Import from a URL"
            case .manual: "Build Manually"
            }
        }

        var subtitle: String {
            switch self {
            case .ai:
                "Describe the meal and let Maia draft its ingredients, steps, and nutrition."
            case .text:
                "Paste a recipe from any text source and let Maia structure it."
            case .url:
                "Use a public recipe page as the starting point."
            case .manual:
                "Add foods from search and write the preparation steps yourself."
            }
        }

        var systemImage: String {
            switch self {
            case .ai: "sparkles"
            case .text: "doc.on.clipboard"
            case .url: "link"
            case .manual: "hand.draw"
            }
        }
    }

    private var totalNutrition: Nutrition {
        if let recipeToEdit,
           recipeToEdit.detailedIngredients == nil,
           ingredients.allSatisfy({
               $0.calories == 0 && $0.protein == 0 && $0.carbs == 0 && $0.fats == 0
                   && $0.reportedMicronutrientCount == 0
           }) {
            return recipeToEdit.nutrition
        }
        return Nutrition.total(for: ingredients)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: recipeToEdit == nil ? "Creation Method" : "Saved Recipe",
                        title: creationMode.title,
                        subtitle: creationMode.subtitle
                    )

                    if recipeToEdit == nil {
                        CreateRecipeModePicker(selection: $creationMode)
                    }

                    modeContent
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle(recipeToEdit == nil ? "Create Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveRecipe) {
                    Label(actionTitle, systemImage: actionIcon)
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(isSaveDisabled || isLoading)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("create_recipe_action")
            }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(
                    dailyLog: $dailyLogService.currentDailyLog,
                    onFoodItemLogged: nil,
                    onFoodItemSelected: addIngredient,
                    searchContext: "recipe_ingredient"
                )
            }
            .overlay {
                if isLoading {
                    CreateRecipeProgressOverlay(mode: creationMode)
                }
            }
            .interactiveDismissDisabled(isLoading)
        }
        .accessibilityIdentifier("create_recipe")
    }

    @ViewBuilder
    private var modeContent: some View {
        switch creationMode {
        case .ai:
            recipeTextInputSection(
                title: "Recipe Brief",
                subtitle: "Include portions, ingredients, cuisine, and macro targets when they matter.",
                placeholder: "Example: High-protein chicken burrito bowls for two servings, around 600 calories each.",
                text: $aiDescription,
                identifier: "create_recipe_ai_input"
            )
        case .text:
            recipeTextInputSection(
                title: "Recipe Text",
                subtitle: "Paste the ingredients, instructions, and any available nutrition details.",
                placeholder: "Paste the recipe text here.",
                text: $importText,
                identifier: "create_recipe_text_input"
            )
        case .url:
            urlSection
        case .manual:
            manualSection
        }
    }

    private func recipeTextInputSection(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title, subtitle: subtitle)

            TextEditor(text: text)
                .appTextRole(.body)
                .frame(minHeight: 190)
                .padding(AppSpacing.row)
                .scrollContentBackground(.hidden)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .appTextRole(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, AppSpacing.group)
                            .padding(.vertical, AppSpacing.group)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .appSurface(.quiet)
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Recipe URL",
                subtitle: "Use a public recipe blog or website. Paywalled and sign-in-only pages may not import."
            )

            TextField("https://example.com/recipe", text: $importURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .appTextRole(.body)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 50)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel("Recipe URL")
                .accessibilityIdentifier("create_recipe_url_input")
        }
        .appSurface(.quiet)
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            recipeNameSection

            if !ingredients.isEmpty {
                CreateRecipeNutritionPreview(nutrition: totalNutrition)
            }

            ingredientSection
            instructionSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create_recipe_manual")
    }

    private var recipeNameSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Recipe Details",
                subtitle: "Choose a name you will recognize in search and meal planning."
            )

            TextField("Recipe name", text: $recipeName)
                .textInputAutocapitalization(.words)
                .appTextRole(.control)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 50)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityIdentifier("create_recipe_name")
        }
        .appSurface(.quiet)
    }

    private var ingredientSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Ingredients",
                subtitle: ingredients.isEmpty
                    ? "Add foods to calculate the recipe's nutrition."
                    : "\(ingredients.count.formatted()) ingredient\(ingredients.count == 1 ? "" : "s") included."
            ) {
                Button {
                    showingFoodSearch = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Add ingredient")
                .accessibilityIdentifier("create_recipe_add_ingredient")
            }

            if ingredients.isEmpty {
                Button {
                    showingFoodSearch = true
                } label: {
                    VStack(spacing: AppSpacing.compact) {
                        Image(systemName: "plus.circle")
                            .appTextRole(.sectionTitle)
                            .foregroundStyle(AppPalette.brand)
                        Text("Add Your First Ingredient")
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Text("Search foods you already use or find a new ingredient.")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.section)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appSurface(.quiet, padding: 0)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        CreateRecipeIngredientRow(
                            ingredient: ingredient,
                            onRemove: { removeIngredient(ingredient) }
                        )

                        if index < ingredients.count - 1 {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create_recipe_ingredients")
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Instructions",
                subtitle: "Put each step on a new line."
            )

            TextEditor(text: $instructions)
                .appTextRole(.body)
                .frame(minHeight: 180)
                .padding(AppSpacing.row)
                .scrollContentBackground(.hidden)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("1. Prepare the ingredients\n2. Cook and assemble\n3. Serve")
                            .appTextRole(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, AppSpacing.group)
                            .padding(.vertical, AppSpacing.group)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel("Recipe instructions")
                .accessibilityIdentifier("create_recipe_instructions")
        }
        .appSurface(.quiet)
    }

    private var actionTitle: String {
        switch creationMode {
        case .ai: "Generate Recipe"
        case .text, .url: "Import Recipe"
        case .manual: recipeToEdit == nil ? "Save Recipe" : "Save Changes"
        }
    }

    private var actionIcon: String {
        switch creationMode {
        case .ai: "sparkles"
        case .text, .url: "square.and.arrow.down"
        case .manual: "checkmark"
        }
    }

    private var isSaveDisabled: Bool {
        switch creationMode {
        case .ai:
            aiDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .text:
            importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url:
            importURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .manual:
            recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                ingredients.isEmpty ||
                instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func saveRecipe() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            bannerService.showBanner(
                title: "Sign In Required",
                message: "Sign in before saving a recipe.",
                iconName: "person.crop.circle.badge.exclamationmark",
                iconColor: .orange
            )
            return
        }

        HapticManager.instance.feedback(.medium)
        isLoading = true

        Task {
            var success = false
            switch creationMode {
            case .ai:
                let recipe = await recipeService.createRecipeFromAI(
                    description: aiDescription,
                    userID: userID
                )
                success = recipe != nil
            case .text:
                let recipe = await recipeService.createRecipeFromText(
                    text: importText,
                    userID: userID
                )
                success = recipe != nil
            case .url:
                let recipe = await recipeService.createRecipeFromURL(
                    url: importURL,
                    userID: userID
                )
                success = recipe != nil
            case .manual:
                success = await saveManualRecipe(for: userID)
            }

            isLoading = false
            if success {
                bannerService.showBanner(
                    title: recipeToEdit == nil ? "Recipe Saved" : "Recipe Updated",
                    message: recipeToEdit == nil
                        ? "Your recipe is now in the library."
                        : "Your changes have been saved.",
                    iconName: "checkmark.circle.fill",
                    iconColor: .accentPositive
                )
                dismiss()
            } else {
                bannerService.showBanner(
                    title: creationMode == .manual ? "Save Failed" : "Import Failed",
                    message: "Could not parse or save the recipe. Please try again.",
                    iconName: "exclamationmark.triangle.fill",
                    iconColor: .orange
                )
            }
        }
    }

    private func saveManualRecipe(for userID: String) async -> Bool {
        let ingredientNames = ingredients.map(\.name)
        let instructionSteps = instructions
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let computed = totalNutrition
        let nutrition = (recipeToEdit != nil && computed.calories == 0 && (recipeToEdit?.nutrition.calories ?? 0) > 0)
            ? recipeToEdit?.nutrition ?? computed
            : computed
        let recipe = Recipe(
            id: recipeToEdit?.id,
            name: recipeName.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredients: ingredientNames,
            detailedIngredients: ingredients,
            instructions: instructionSteps,
            nutrition: nutrition,
            servings: recipeToEdit?.servings ?? 1
        )

        do {
            let saved = try await recipeService.saveRecipe(recipe, for: userID)
            onSaved?(saved)
            return true
        } catch {
            return false
        }
    }
}

private struct CreateRecipeModePicker: View {
    @Binding var selection: CreateRecipeView.CreationMode

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(CreateRecipeView.CreationMode.allCases) { mode in
                        Button {
                            selection = mode
                        } label: {
                            Label(
                                mode.title,
                                systemImage: selection == mode ? "checkmark" : mode.systemImage
                            )
                        }
                    }
                } label: {
                    HStack(spacing: AppSpacing.row) {
                        Image(systemName: selection.systemImage)
                            .foregroundStyle(AppPalette.brand)
                        Text(selection.title)
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Spacer(minLength: AppSpacing.compact)
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(AppPalette.brand)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appSurface(.quiet)
                .accessibilityLabel("Creation method")
                .accessibilityValue(selection.title)
            } else {
                Picker("Creation method", selection: $selection) {
                    ForEach(CreateRecipeView.CreationMode.allCases) { mode in
                        Text(mode.shortTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .accessibilityIdentifier("create_recipe_mode")
    }
}

private struct CreateRecipeNutritionPreview: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Nutrition Preview",
                subtitle: "Current total from the ingredients below"
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Calories",
                    value: "\(Int(nutrition.calories.rounded()).formatted()) cal",
                    accent: .orange
                ),
                AppMetricItem(
                    label: "Protein",
                    value: "\(Int(nutrition.protein.rounded()).formatted()) g",
                    accent: .accentProtein
                ),
                AppMetricItem(
                    label: "Carbs",
                    value: "\(Int(nutrition.carbs.rounded()).formatted()) g",
                    accent: .accentCarbs
                ),
                AppMetricItem(
                    label: "Fat",
                    value: "\(Int(nutrition.fats.rounded()).formatted()) g",
                    accent: .accentFats
                )
            ])
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("create_recipe_nutrition")
    }
}

private struct CreateRecipeIngredientRow: View {
    let ingredient: FoodItem
    let onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(FoodEmojiMapper.getEmoji(for: ingredient.name))
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(nutritionSummary)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel("Remove \(ingredient.name)")
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
    }

    private var nutritionSummary: String {
        let calories = Int(ingredient.calories.rounded()).formatted()
        let protein = Int(ingredient.protein.rounded()).formatted()
        let carbs = Int(ingredient.carbs.rounded()).formatted()
        let fats = Int(ingredient.fats.rounded()).formatted()
        return "\(calories) cal · P \(protein) g · C \(carbs) g · F \(fats) g"
    }
}

private struct CreateRecipeProgressOverlay: View {
    let mode: CreateRecipeView.CreationMode

    private var title: String {
        switch mode {
        case .ai: "Generating Recipe"
        case .text, .url: "Importing Recipe"
        case .manual: "Saving Recipe"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.row) {
                ProgressView()
                    .tint(AppPalette.brand)
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text("This may take a moment.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
            .appSurface(.emphasized)
            .padding(AppSpacing.screenHorizontal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
