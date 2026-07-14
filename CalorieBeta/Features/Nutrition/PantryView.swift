import MyFitPlateCore
import SwiftUI

struct PantryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pantryService: PantryService
    @FocusState private var addFieldIsFocused: Bool
    @State private var newItemName = ""
    @State private var showingRecipeGeneration = false
    @State private var showingReceiptScanner = false

    private var groupedItems: [String: [PantryItem]] {
        Dictionary(grouping: pantryService.pantryItems, by: \.category)
    }

    private var isReceiptScannerEnabled: Bool {
        DIContainer.shared.featureFlagService?.isFeatureEnabled(.receiptScanner)
            ?? FeatureFlag.receiptScanner.defaultValue
    }

    var body: some View {
        AppSheetScaffold(
            title: "Smart Pantry",
            subtitle: "Ingredients available for planning and recipe ideas",
            dismiss: { dismiss() }
        ) {
            pantryContent
        }
        .safeAreaInset(edge: .bottom) {
            addItemBar
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brand)
        .onAppear(perform: startListening)
        .sheet(isPresented: $showingRecipeGeneration) {
            PantryRecipeGenerationView(pantryService: pantryService)
        }
        .sheet(isPresented: $showingReceiptScanner) {
            if isReceiptScannerEnabled {
                ReceiptScannerView()
            }
        }
    }

    private var pantryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                if pantryService.isLoading && pantryService.pantryItems.isEmpty {
                    loadingState
                } else if pantryService.pantryItems.isEmpty {
                    emptyState
                } else {
                    pantrySummary
                    recipeAction
                    categoryList
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppPalette.canvas)
    }

    private var pantrySummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Ingredients",
                value: pantryService.pantryItems.count.formatted(),
                accent: AppPalette.brand
            ),
            AppMetricItem(
                label: "Categories",
                value: groupedItems.count.formatted(),
                accent: .orange
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("pantry_summary")
    }

    private var recipeAction: some View {
        Button {
            showingRecipeGeneration = true
        } label: {
            AppListRow(
                icon: "sparkles",
                iconColor: AppPalette.brand,
                title: "Create From Pantry",
                subtitle: "Draft recipes from the ingredients listed here",
                hidesTextFromAccessibility: true
            ) {
                Image(systemName: "chevron.right")
                    .appTextRole(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .appSurface(.quiet, padding: 0)
        .accessibilityLabel("Create From Pantry")
        .accessibilityHint("Draft recipes from the ingredients listed here")
        .accessibilityIdentifier("pantry_recipe_button")
    }

    private var categoryList: some View {
        LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
            ForEach(groupedItems.keys.sorted(), id: \.self) { category in
                let items = groupedItems[category] ?? []
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AppSectionHeader(
                        title: category,
                        subtitle: "\(items.count.formatted()) \(items.count == 1 ? "ingredient" : "ingredients")"
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PantryItemRow(
                                item: item,
                                icon: categoryIcon(for: category),
                                iconColor: categoryColor(for: category),
                                onDelete: { delete(item) }
                            )

                            if index < items.count - 1 {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .appSurface(.quiet, padding: 0)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: AppSpacing.group) {
            ProgressView()
                .controlSize(.large)
                .tint(AppPalette.brand)
            Text("Loading Pantry")
                .appTextRole(.control)
            Text("Checking your saved ingredients.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "cabinet.fill")
                .appFont(size: 34, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 64, height: 64)
                .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.surface))
                .accessibilityHidden(true)

            Text("Your Pantry Is Empty")
                .appTextRole(.sectionTitle)

            Text("Add an ingredient below to make it available for meal planning.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.emphasized)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pantry_empty_state")
    }

    private var addItemBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: AppSpacing.compact) {
                if isReceiptScannerEnabled {
                    Button {
                        addFieldIsFocused = false
                        showingReceiptScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .accessibilityLabel("Scan Receipt")
                    .accessibilityHint("Review grocery items detected from a receipt")
                    .accessibilityIdentifier("pantry_scan_receipt_button")
                }

                TextField("Add ingredient", text: $newItemName)
                    .appTextRole(.body)
                    .submitLabel(.done)
                    .focused($addFieldIsFocused)
                    .onSubmit(addItem)
                    .padding(.horizontal, AppSpacing.row)
                    .frame(minHeight: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityIdentifier("pantry_add_field")

                Button(action: addItem) {
                    Image(systemName: "plus")
                }
                .buttonStyle(AppIconButtonStyle(.brand))
                .disabled(trimmedNewItemName.isEmpty)
                .accessibilityLabel("Add Ingredient")
                .accessibilityIdentifier("pantry_add_button")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.row)
        }
        .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
    }

    private var trimmedNewItemName: String {
        newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startListening() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        pantryService.startListening(userID: userID)
    }

    private func addItem() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let trimmed = trimmedNewItemName
        guard !trimmed.isEmpty else { return }

        let item = PantryItem(
            name: trimmed,
            quantity: 1,
            unit: "item",
            category: IngredientCategoryMapper.groceryCategory(for: trimmed)
        )
        pantryService.addOrUpdateItem(item, userID: userID)
        newItemName = ""
    }

    private func delete(_ item: PantryItem) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        pantryService.deleteItem(item, userID: userID)
    }

    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case let value where value.contains("produce"): "leaf.fill"
        case let value where value.contains("protein") || value.contains("meat"): "fork.knife"
        case let value where value.contains("dairy"): "drop.fill"
        case let value where value.contains("grain") || value.contains("bakery"): "takeoutbag.and.cup.and.straw.fill"
        case let value where value.contains("frozen"): "snowflake"
        default: "cabinet.fill"
        }
    }

    private func categoryColor(for category: String) -> Color {
        switch category.lowercased() {
        case let value where value.contains("produce"): .green
        case let value where value.contains("protein") || value.contains("meat"): .red
        case let value where value.contains("dairy"): .blue
        case let value where value.contains("grain") || value.contains("bakery"): .orange
        case let value where value.contains("frozen"): .cyan
        default: AppPalette.brand
        }
    }
}

private struct PantryItemRow: View {
    let item: PantryItem
    let icon: String
    let iconColor: Color
    let onDelete: () -> Void

    var body: some View {
        AppListRow(
            icon: icon,
            iconColor: iconColor,
            title: item.name,
            subtitle: quantityText
        ) {
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Ingredient", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Options for \(item.name)")
        }
        .accessibilityIdentifier("pantry_item_\(item.id.uuidString)")
    }

    private var quantityText: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        let quantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
        return "\(quantity) \(item.unit)"
    }
}

struct PantryRecipeGenerationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recipeService: RecipeService
    @ObservedObject var pantryService: PantryService

    @State private var generatedRecipes: [Recipe]
    @State private var isGenerating: Bool
    @State private var didRequestRecipes: Bool
    @State private var savingRecipeIndex: Int?
    @State private var savedRecipeIndices: Set<Int> = []
    @State private var generationError: String?
    @State private var saveError: String?

    init(pantryService: PantryService, initialRecipes: [Recipe] = []) {
        self.pantryService = pantryService
        _generatedRecipes = State(initialValue: initialRecipes)
        _isGenerating = State(initialValue: initialRecipes.isEmpty)
        _didRequestRecipes = State(initialValue: !initialRecipes.isEmpty)
    }

    var body: some View {
        AppSheetScaffold(
            title: "Pantry Recipes",
            subtitle: "AI-assisted drafts based on your current ingredients",
            dismiss: { dismiss() }
        ) {
            content
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brand)
        .onAppear {
            if !didRequestRecipes {
                generateRecipes()
            }
        }
        .alert("Recipe Not Saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isGenerating {
            statusState(
                icon: "sparkles",
                title: "Drafting Recipes",
                message: "Using the ingredient names and amounts in your pantry.",
                showsProgress: true
            )
        } else if let generationError {
            VStack(spacing: AppSpacing.group) {
                statusState(
                    icon: "exclamationmark.triangle.fill",
                    title: "Recipes Unavailable",
                    message: generationError,
                    showsProgress: false
                )

                Button("Try Again", action: generateRecipes)
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .accessibilityIdentifier("pantry_recipes_retry_button")
            }
        } else {
            recipeList
        }
    }

    private var recipeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Recipe Drafts",
                        value: generatedRecipes.count.formatted(),
                        accent: AppPalette.brand
                    ),
                    AppMetricItem(
                        label: "Pantry Ingredients",
                        value: pantryService.pantryItems.count.formatted(),
                        accent: .orange
                    )
                ])
                .appSurface(.emphasized)
                .accessibilityIdentifier("pantry_recipe_summary")

                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppPalette.brand)
                        .accessibilityHidden(true)
                    Text("Nutrition, quantities, and instructions are estimates. Review them before saving or logging a meal.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                ForEach(Array(generatedRecipes.enumerated()), id: \.offset) { index, recipe in
                    recipeCard(recipe, index: index)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppPalette.canvas)
    }

    private func recipeCard(_ recipe: Recipe, index: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: recipe.name,
                subtitle: "Generated from your pantry"
            )

            AppMetricStrip(items: [
                AppMetricItem(label: "Calories", value: "\(formatted(recipe.nutrition.calories)) cal", accent: .orange),
                AppMetricItem(label: "Protein", value: "\(formatted(recipe.nutrition.protein)) g", accent: AppPalette.brand),
                AppMetricItem(label: "Carbs", value: "\(formatted(recipe.nutrition.carbs)) g", accent: .blue),
                AppMetricItem(label: "Fat", value: "\(formatted(recipe.nutrition.fats)) g", accent: .yellow)
            ])

            Divider()

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("Ingredients")
                    .appTextRole(.control)
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        Image(systemName: "circle.fill")
                            .appFont(size: 6)
                            .foregroundStyle(AppPalette.brand)
                            .accessibilityHidden(true)
                        Text(ingredient)
                            .appTextRole(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("Directions")
                    .appTextRole(.control)
                ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        Text((index + 1).formatted())
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.brand)
                            .frame(width: 24, height: 24)
                            .background(AppPalette.brand.opacity(0.10), in: Circle())
                            .accessibilityHidden(true)
                        Text(instruction)
                            .appTextRole(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button {
                save(recipe, index: index)
            } label: {
                if savedRecipeIndices.contains(index) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                } else if savingRecipeIndex == index {
                    HStack(spacing: AppSpacing.compact) {
                        ProgressView()
                            .tint(.white)
                        Text("Saving")
                    }
                } else {
                    Label("Save Recipe", systemImage: "bookmark")
                }
            }
            .buttonStyle(AppActionButtonStyle(savedRecipeIndices.contains(index) ? .secondary : .primary))
            .disabled(savedRecipeIndices.contains(index) || savingRecipeIndex != nil)
            .accessibilityIdentifier("pantry_recipe_save_button")
        }
        .appSurface(.quiet)
    }

    private func statusState(
        icon: String,
        title: String,
        message: String,
        showsProgress: Bool
    ) -> some View {
        VStack(spacing: AppSpacing.group) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppPalette.brand)
            } else {
                Image(systemName: icon)
                    .appFont(size: 32, weight: .semibold)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }

            Text(title)
                .appTextRole(.sectionTitle)
            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.section)
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    private func generateRecipes() {
        didRequestRecipes = true
        isGenerating = true
        generationError = nil

        guard let userID = DIContainer.shared.authService.currentUserID else {
            isGenerating = false
            generationError = "Sign in again to generate pantry recipes."
            return
        }

        let items = pantryService.pantryItems
            .map { "\($0.quantity) \($0.unit) \($0.name)" }
            .joined(separator: ", ")

        guard !items.isEmpty else {
            isGenerating = false
            generationError = "Add at least one pantry ingredient first."
            return
        }

        Task {
            let recipes = await recipeService.createRecipesFromPantry(itemsString: items, userID: userID)
            await MainActor.run {
                isGenerating = false
                if recipes.isEmpty {
                    generationError = "No recipe drafts were returned. Please try again."
                } else {
                    generatedRecipes = recipes
                }
            }
        }
    }

    private func save(_ recipe: Recipe, index: Int) {
        guard savingRecipeIndex == nil, !savedRecipeIndices.contains(index) else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else {
            saveError = "Sign in again to save this recipe."
            return
        }

        savingRecipeIndex = index
        Task {
            do {
                _ = try await recipeService.saveRecipe(recipe, for: userID)
                await MainActor.run {
                    savedRecipeIndices.insert(index)
                    savingRecipeIndex = nil
                }
            } catch {
                await MainActor.run {
                    savingRecipeIndex = nil
                    saveError = "Your recipe draft is still here. Please try saving it again."
                }
            }
        }
    }
}

struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var pantryService: PantryService

    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var parsedItems: [PantryItem]
    @State private var errorMessage: String?

    private let aiModel = MLImageModel()

    init(initialItems: [PantryItem] = []) {
        _parsedItems = State(initialValue: initialItems)
    }

    var body: some View {
        AppSheetScaffold(
            title: parsedItems.isEmpty ? "Receipt Scanner" : "Review Receipt",
            subtitle: parsedItems.isEmpty
                ? "Create a pantry draft from a grocery receipt"
                : "Confirm every item before adding it to your pantry",
            dismiss: { dismiss() }
        ) {
            content
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brand)
        .onChange(of: capturedImage) { _, newValue in
            if let image = newValue {
                processImage(image)
            }
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(sourceType: .camera) { image in
                capturedImage = image
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isProcessing {
            processingState
        } else if !parsedItems.isEmpty {
            reviewState
        } else {
            scanState
        }
    }

    private var processingState: some View {
        VStack(spacing: AppSpacing.group) {
            ProgressView()
                .controlSize(.large)
                .tint(AppPalette.brand)
            Text("Reading Receipt")
                .appTextRole(.sectionTitle)
            Text("This may take a few seconds.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var scanState: some View {
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                Image(systemName: "doc.text.viewfinder")
                    .appFont(size: 38, weight: .semibold)
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 72, height: 72)
                    .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.hero))
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.compact) {
                    Text("Scan A Grocery Receipt")
                        .appTextRole(.sectionTitle)
                    Text("Receipt parsing is AI-assisted and may miss or misread items. You will review the draft before anything is saved.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(errorMessage)
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.quiet)
                }

                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("receipt_take_photo_button")
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background(AppPalette.canvas)
    }

    private var reviewState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.group) {
                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Items Detected",
                        value: parsedItems.count.formatted(),
                        accent: AppPalette.brand
                    ),
                    AppMetricItem(
                        label: "Ready To Add",
                        value: validItems.count.formatted(),
                        accent: .orange
                    )
                ])
                .appSurface(.emphasized)
                .accessibilityIdentifier("receipt_review_summary")

                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(AppPalette.brand)
                        .accessibilityHidden(true)
                    Text("Check names, amounts, units, and categories. Remove anything that does not belong.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                ForEach(Array(parsedItems.indices), id: \.self) { index in
                    receiptItemEditor(index: index)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppPalette.canvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    saveToPantry()
                } label: {
                    Label("Add \(validItems.count.formatted()) To Pantry", systemImage: "plus")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(validItems.isEmpty)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.row)
                .accessibilityIdentifier("receipt_add_to_pantry_button")
            }
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
        }
    }

    private func receiptItemEditor(index: Int) -> some View {
        let item = $parsedItems[index]

        return VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .center, spacing: AppSpacing.row) {
                Text("Item \((index + 1).formatted())")
                    .appTextRole(.control)
                Spacer()
                Button(role: .destructive) {
                    parsedItems.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(item.wrappedValue.name)")
            }

            labeledField("Name") {
                TextField("Item name", text: item.name)
                    .textInputAutocapitalization(.words)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.group) {
                    amountField(item)
                    unitField(item)
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    amountField(item)
                    unitField(item)
                }
            }

            labeledField("Category") {
                TextField("Category", text: item.category)
                    .textInputAutocapitalization(.words)
            }
        }
        .textFieldStyle(.roundedBorder)
        .appSurface(.quiet)
        .accessibilityIdentifier("receipt_review_item_\(index)")
    }

    private func amountField(_ item: Binding<PantryItem>) -> some View {
        labeledField("Amount") {
            TextField("Amount", value: item.quantity, format: .number)
                .keyboardType(.decimalPad)
        }
        .frame(maxWidth: .infinity)
    }

    private func unitField(_ item: Binding<PantryItem>) -> some View {
        labeledField("Unit") {
            TextField("Unit", text: item.unit)
                .textInputAutocapitalization(.never)
        }
        .frame(maxWidth: .infinity)
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            content()
                .appTextRole(.body)
        }
    }

    private var validItems: [PantryItem] {
        PantryReceiptReviewRules.reviewedItems(from: parsedItems)
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil

        aiModel.parseGroceryReceipt(from: image) { result in
            DispatchQueue.main.async {
                isProcessing = false
                switch result {
                case .success(let items):
                    if items.isEmpty {
                        errorMessage = "No grocery items were detected. Try a clearer photo with the full receipt visible."
                    } else {
                        parsedItems = items
                    }
                case .failure:
                    errorMessage = "The receipt could not be read. Try a clearer photo with even lighting."
                }
            }
        }
    }

    private func saveToPantry() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let reviewedItems = validItems
        guard !reviewedItems.isEmpty else { return }

        for item in reviewedItems {
            pantryService.addOrUpdateItem(item, userID: userID)
        }
        dismiss()
    }
}
