import MyFitPlateCore
import SwiftUI

struct PantryView: View {
    private enum StockFilter: String, CaseIterable {
        case all = "All stock", ingredients = "Ingredients", cooked = "Cooked stock", dates = "Dates to review"
    }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pantryService: PantryService
    @FocusState private var addFieldIsFocused: Bool
    @State private var newItemName = ""
    @State private var showingRecipeGeneration = false
    @State private var showingReceiptScanner = false
    @State private var stockEditor: StockEditorRequest?
    @State private var stockUse: StockUseRequest?
    @State private var stockReview: InventoryMutation?
    @State private var pendingStock: InventorySaveSession?
    @State private var showingStockHistory = false
    @State private var stockSearch = ""
    @State private var stockFilter: StockFilter = .all

    private var filteredStock: [PantryItem] {
        let query = stockSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return pantryService.pantryItems.filter { item in
            guard item.isArchived != true else { return false }
            guard query.isEmpty || [item.name, item.category, item.location ?? ""].contains(where: { $0.localizedCaseInsensitiveContains(query) }) else { return false }
            switch stockFilter {
            case .all: return true
            case .ingredients: return !item.isCookedBatch && item.preparation != "Cooked"
            case .cooked: return item.isCookedBatch || item.preparation == "Cooked"
            case .dates: return item.bestBefore.map { $0 <= horizon } ?? false
            }
        }
    }

    private var groupedItems: [String: [PantryItem]] {
        Dictionary(grouping: filteredStock, by: \.category)
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
        .tint(AppPalette.brandText)
        .onAppear { startListening(); refreshStockReview() }
        .sheet(item: $stockEditor, onDismiss: { refreshStockReview() }) { request in
            StockItemEditorView(item: request.item, name: request.name) { newItemName = ""; refreshStockReview() }
        }
        .sheet(item: $stockUse, onDismiss: { refreshStockReview() }) { request in
            StockConsumeReviewView(item: request.item, waste: request.waste)
        }
        .sheet(item: $stockReview, onDismiss: { refreshStockReview() }) { mutation in
            InventoryOperationReviewView(mutation: mutation) { refreshStockReview() }
        }
        .sheet(item: $pendingStock, onDismiss: { refreshStockReview() }) { session in
            InventoryOperationReviewView(session: session) { refreshStockReview() }
        }
        .sheet(isPresented: $showingStockHistory, onDismiss: { refreshStockReview() }) { StockHistoryView() }
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
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    TextField("Find stock", text: $stockSearch).textFieldStyle(.roundedBorder)
                        .appTextRole(.body).frame(minHeight: 44).accessibilityIdentifier("inventory_search")
                    HStack {
                        Picker("Show stock", selection: $stockFilter) {
                            ForEach(StockFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.menu).frame(minHeight: 44).accessibilityIdentifier("inventory_filter")
                        Spacer()
                        Menu("Pantry tools", systemImage: "ellipsis") {
                            Button("Stock history", systemImage: "clock.arrow.circlepath") { showingStockHistory = true }
                                .accessibilityIdentifier("inventory_history")
                            Button("Resume stock review", systemImage: "arrow.clockwise") {
                                let session = InventorySaveSession(userID: DIContainer.shared.authService.currentUserID)
                                if session.checkpoint != nil || session.errorMessage != nil { pendingStock = session }
                            }.accessibilityIdentifier("inventory_resume_review")
                        }.appTextRole(.secondary).tint(AppPalette.text).frame(minHeight: 44)
                            .accessibilityIdentifier("inventory_tools")
                    }
                    if stockFilter == .dates {
                        Text("Your entered label dates that have passed or fall within seven days. This is a reminder, not a freshness assessment.")
                            .appTextRole(.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let error = pantryService.errorMessage {
                    Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("inventory_load_error")
                }
                if pantryService.isLoading && pantryService.pantryItems.isEmpty {
                    loadingState
                } else if pantryService.pantryItems.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: AppSpacing.row) {
                        pantrySummary
                        Spacer(minLength: AppSpacing.compact)
                        recipeAction
                    }
                    if filteredStock.isEmpty {
                        Text("No stock matches this search and filter.").appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("inventory_search_empty")
                    } else { categoryList }
                }
                PlannedStockReservationsLink()
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.row)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory_pantry_scroll")
        .background(AppPalette.canvas)
    }

    private var pantrySummary: some View {
        Text("\(pantryService.pantryItems.filter { $0.isArchived != true }.count) stock lots · \(groupedItems.count) categories")
            .appTextRole(.secondary).foregroundStyle(.secondary)
            .accessibilityIdentifier("pantry_summary")
    }

    private var recipeAction: some View {
        Button { showingRecipeGeneration = true } label: {
            Label("Meal ideas", systemImage: "sparkles")
                .appTextRole(.secondary).frame(minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(AppPalette.text)
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
                                onDelete: { delete(item) },
                                onEdit: { stockEditor = StockEditorRequest(item: item) },
                                onUse: { stockUse = StockUseRequest(item: item, waste: false) },
                                onWaste: { stockUse = StockUseRequest(item: item, waste: true) }
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
                .tint(AppPalette.brandText)
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
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 64, height: 64)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface))
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
        guard DIContainer.shared.authService.currentUserID != nil, !trimmedNewItemName.isEmpty else { return }
        stockEditor = StockEditorRequest(name: trimmedNewItemName); addFieldIsFocused = false
    }

    private func delete(_ item: PantryItem) {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        var archived = item; archived.isArchived = true; archived.revisionID = UUID().uuidString
        stockReview = InventoryMutation(userID: owner, title: "Archive \(item.name)", reason: .correction, before: [item], after: [archived])
    }

    private func refreshStockReview() {
        // The permanent entry remains reachable even if a pending receipt is unreadable.
        startListening()
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
        case let value where value.contains("produce"): AppPalette.positive
        case let value where value.contains("protein") || value.contains("meat"): AppPalette.protein
        case let value where value.contains("dairy"): AppPalette.recovery
        case let value where value.contains("grain") || value.contains("bakery"): AppPalette.carbohydrate
        case let value where value.contains("frozen"): AppPalette.recovery
        default: AppPalette.brand
        }
    }
}

private struct StockEditorRequest: Identifiable {
    let id = UUID()
    var item: PantryItem?
    var name = ""
}

private struct PantryItemRow: View {
    let item: PantryItem
    let icon: String
    let iconColor: Color
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onUse: () -> Void
    let onWaste: () -> Void

    var body: some View {
        AppListRow(
            icon: icon,
            iconColor: iconColor,
            title: item.name,
            subtitle: quantityText
        ) {
            Menu {
                Button("Edit / confirm amount", systemImage: "pencil", action: onEdit)
                Button("Use or log portion", systemImage: "fork.knife", action: onUse)
                    .disabled(item.availableQuantity <= 0)
                Button("Write off / waste", systemImage: "trash", action: onWaste)
                    .disabled(item.availableQuantity <= 0)
                Button(role: .destructive, action: onDelete) {
                    Label("Archive stock", systemImage: "archivebox")
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
        let amount = item.quantityUnknown == true ? "Quantity unknown" : "\(quantity) \(item.unit)"
        let review = item.quantityVerified == true ? "" : " · confirm amount"
        let expiry = item.bestBefore.map { " · label \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        return amount + review + expiry
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
    @State private var ideaReview: PantryIdeaRequest?

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
        .tint(AppPalette.brandText)
        .sheet(item: $ideaReview) { request in
            PantryRecipeIdeaReviewView(recipe: request.recipe, stock: pantryService.pantryItems, date: request.date, meal: request.meal)
        }
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
                Text("\(generatedRecipes.count) recipe ideas · \(pantryService.pantryItems.count) pantry ingredients")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("pantry_recipe_summary")

                HStack(alignment: .top, spacing: AppSpacing.row) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppPalette.brandText)
                        .accessibilityHidden(true)
                    Text("Estimated recipes · review ingredients, amounts and nutrition before saving or logging.")
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
            AppSectionHeader(title: recipe.name,
                subtitle: recipe.nutritionBasis == nil ? "Estimated recipe · confirm serving basis" : recipe.nutritionBasisLabel)
            AppMetricStrip(items: [
                AppMetricItem(label: "Calories", value: "\(formatted(recipe.nutritionPerPortion.calories)) cal", accent: AppPalette.energy),
                AppMetricItem(label: "Protein", value: "\(formatted(recipe.nutritionPerPortion.protein)) g", accent: AppPalette.protein),
                AppMetricItem(label: "Carbs", value: "\(formatted(recipe.nutritionPerPortion.carbs)) g", accent: AppPalette.carbohydrate),
                AppMetricItem(label: "Fat", value: "\(formatted(recipe.nutritionPerPortion.fats)) g", accent: AppPalette.fat)
            ])
            Button {
                ideaReview = .init(recipe: recipe, date: Date(), meal: "Dinner")
            } label: { Label("Review this recipe", systemImage: "checklist") }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .accessibilityIdentifier("pantry_recipe_save_button")
            DisclosureGroup("Ingredients · \(recipe.ingredients.count)") {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        Text(ingredient).appTextRole(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, AppSpacing.compact)
            }.appTextRole(.secondary).tint(AppPalette.text)
            DisclosureGroup("Method · \(recipe.instructions.count) steps") {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            Text((index + 1).formatted()).appTextRole(.caption).foregroundStyle(.secondary)
                                .frame(width: 24, height: 24).accessibilityHidden(true)
                            Text(instruction).appTextRole(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(.top, AppSpacing.compact)
            }.appTextRole(.secondary).tint(AppPalette.text)
        }.appSurface(.quiet)
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
                    .tint(AppPalette.brandText)
            } else {
                Image(systemName: icon)
                    .appFont(size: 32, weight: .semibold)
                    .foregroundStyle(AppPalette.caution)
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
                guard DIContainer.shared.authService.currentUserID == userID else {
                    isGenerating = false
                    return
                }
                isGenerating = false
                if recipes.isEmpty {
                    generationError = "No recipe drafts were returned. Please try again."
                } else {
                    generatedRecipes = PantryRecipeFitRules.ranked(recipes, stock: pantryService.pantryItems)
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
                    guard DIContainer.shared.authService.currentUserID == userID else {
                        savingRecipeIndex = nil
                        return
                    }
                    savedRecipeIndices.insert(index)
                    savingRecipeIndex = nil
                }
            } catch {
                await MainActor.run {
                    guard DIContainer.shared.authService.currentUserID == userID else {
                        savingRecipeIndex = nil
                        return
                    }
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
    @State private var receiptStoreName: String
    @State private var receiptCurrency: String
    @State private var errorMessage: String?
    @State private var receiptDate = Date()
    @State private var receiptAnalysisID: UUID?
    @State private var reviewingReceiptProduct: PantryItem?
    @State private var expandedReceiptItemID: UUID?
    @State private var confirmingSeparateReceiptImport = false
    @StateObject private var receiptSession: PantryReceiptImportSession

    private let aiModel = MLImageModel()

    init(initialItems: [PantryItem] = []) {
        let session = PantryReceiptImportSession(userID: DIContainer.shared.authService.currentUserID, items: initialItems)
        _receiptSession = StateObject(wrappedValue: session)
        _parsedItems = State(initialValue: session.items)
        _expandedReceiptItemID = State(initialValue: session.items.first { PantryReceiptReviewRules.reviewedItems(from: [$0]).isEmpty }?.id)
        _receiptStoreName = State(initialValue: session.checkpoint.storeName ?? session.items.compactMap { $0.purchaseEvidence?.storeName }.first ?? "")
        _receiptCurrency = State(initialValue: session.checkpoint.currency ?? session.items.compactMap { $0.purchaseEvidence?.currency }.first ?? "")
        _receiptDate = State(initialValue: session.checkpoint.purchaseDate)
    }

    var body: some View {
        AppSheetScaffold(
            title: parsedItems.isEmpty ? "Receipt Scanner" : "Review Receipt",
            subtitle: parsedItems.isEmpty
                ? "Create a pantry draft from a grocery receipt"
                : nil,
            dismiss: { if !receiptSession.isSaving { dismiss() } }
        ) {
            content
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brandText)
        .interactiveDismissDisabled(receiptSession.isSaving)
        .onChange(of: parsedItems) { _, items in
            guard !receiptSession.isSubmitted else { return }
            if !receiptSession.update(items: items, purchaseDate: receiptDate) { parsedItems = receiptSession.items }
        }
        .onChange(of: parsedItems.map(\.id)) { _, ids in
            if expandedReceiptItemID.map(ids.contains) != true {
                expandedReceiptItemID = parsedItems.first { PantryReceiptReviewRules.reviewedItems(from: [$0]).isEmpty }?.id
            }
        }
        .onChange(of: receiptDate) { _, date in
            guard !receiptSession.isSubmitted else { return }
            if !receiptSession.update(items: parsedItems, purchaseDate: date) { receiptDate = receiptSession.checkpoint.purchaseDate }
        }
        .onChange(of: capturedImage) { _, newValue in
            if let image = newValue {
                processImage(image)
            }
        }
        .imageSourceDialog(isPresented: $showingCamera) { image in
            capturedImage = image
        }
        .sheet(item: $reviewingReceiptProduct) { original in
            ReceiptProductMatchReviewView(item: original) { reviewed in
                guard receiptSession.userID == DIContainer.shared.authService.currentUserID, !receiptSession.isSubmitted,
                      let index = parsedItems.firstIndex(where: { $0.id == original.id }), parsedItems[index] == original else {
                    errorMessage = "This receipt row changed. Its current values are kept; reopen product review."
                    return
                }
                parsedItems[index] = reviewed
            }
        }
        .onChange(of: receiptSession.checkpoint.id) { _, _ in
            parsedItems = receiptSession.items; receiptDate = receiptSession.checkpoint.purchaseDate
            receiptStoreName = receiptSession.checkpoint.storeName ?? ""; receiptCurrency = receiptSession.checkpoint.currency ?? ""
        }
        .onChange(of: receiptStoreName) { _, _ in saveReceiptContext() }
        .onChange(of: receiptCurrency) { _, _ in saveReceiptContext() }
        .confirmationDialog("Record a separate reviewed import?", isPresented: $confirmingSeparateReceiptImport, titleVisibility: .visible) {
            Button("Confirm separate import") {
                if receiptSession.isSubmitted { Task { await receiptSession.beginSeparateImport(using: DIContainer.shared.nutritionRepository) } } else { _ = receiptSession.confirmSeparateImport() }
            }
            Button("Keep current review", role: .cancel) {}
        } message: {
            Text("Confirm a separate purchase only if both receipts should count. A pending operation is first checked and permanently cancelled if unaccepted; accepted purchases are never replaced.")
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
        ImageProcessingView(kind: .receiptPhoto) {
            receiptAnalysisID = nil
            isProcessing = false
        }
    }

    private var scanState: some View {
        ScrollView {
            VStack(spacing: AppSpacing.section) {
                Image(systemName: "doc.text.viewfinder")
                    .appFont(size: 38, weight: .semibold)
                    .foregroundStyle(AppPalette.brandText)
                    .frame(width: 72, height: 72)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.hero))
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
                            .foregroundStyle(AppPalette.caution)
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
                Text(receiptSession.isSubmitted
                     ? "\(receiptSession.acceptedCount) of \(receiptSession.checkpoint.rows.count) added to pantry"
                     : "\(validItems.count) of \(parsedItems.count) ready")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("receipt_review_summary")

                if !receiptSession.historyAvailable {
                    Text("Previous receipt suggestions on this device are unavailable. The account's source locks still prevent the same imported receipt from replenishing stock twice.")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                }
                if !receiptSession.duplicateHistory.isEmpty && !receiptSession.hasConfirmedSeparateImport {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Possible duplicate receipt").appTextRole(.control)
                        Text("Compare this receipt with your earlier purchase.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(receiptSession.duplicateHistory) { record in
                            Text("\(record.purchaseDayKey ?? record.purchaseDate.formatted(date: .abbreviated, time: .omitted)) · \(record.items.count) items")
                                .appTextRole(.secondary)
                            Text(record.items.prefix(3).map(\.name).joined(separator: ", "))
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                        if !receiptSession.isSubmitted {
                            Button("Review separate import") { confirmingSeparateReceiptImport = true }.frame(minHeight: 44)
                                .accessibilityIdentifier("receipt_review_duplicate")
                        }
                    }.appSurface(.quiet).accessibilityIdentifier("receipt_duplicate_warning")
                }
                if receiptSession.hasConfirmedSeparateImport {
                    Text("This receipt will count as a separate purchase.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }

                if let message = receiptSession.errorMessage {
                    Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("receipt_save_error")
                }
                if receiptSession.restoredReview {
                    Text("Restored your receipt review and purchase date from this device.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if receiptSession.isSubmitted && !receiptSession.isComplete {
                    Text(receiptSession.checkpoint.usesWholeReceiptLedger == true
                        ? "These products are added together. Retry uses the same receipt."
                        : "Retry picks up with the remaining products.")
                        .appTextRole(.secondary).accessibilityIdentifier("receipt_save_status")
                    if receiptSession.checkpoint.ledgerMutation != nil && !receiptSession.isComplete {
                        Button("Check saved receipt status") { Task { await receiptSession.checkStatus(using: DIContainer.shared.nutritionRepository) } }
                            .frame(minHeight: 44).disabled(receiptSession.isSaving).accessibilityIdentifier("receipt_check_status")
                        Button("Review a separate import") { confirmingSeparateReceiptImport = true }
                            .frame(minHeight: 44).disabled(receiptSession.isSaving).accessibilityIdentifier("receipt_prepare_separate_import")
                    }
                }

                if let errorMessage {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppPalette.caution)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("New scan was not used")
                                .appTextRole(.control)
                            Text(errorMessage)
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.quiet)
                }

                VStack(spacing: 0) {
                    ForEach(Array(parsedItems.enumerated()), id: \.element.id) { index, product in
                        if receiptSession.isSubmitted {
                            receiptRowStatus(index: index)
                        } else {
                            receiptProductRow(product, index: index)
                        }
                        Divider()
                    }
                }
                receiptPurchaseDate
                DisclosureGroup {
                    receiptContextCard
                    if !receiptSession.isSubmitted {
                        Button("Discard receipt", role: .destructive) { if receiptSession.discard() { dismiss() } }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                } label: {
                    Text("Receipt details").accessibilityIdentifier("receipt_details")
                }
                .appTextRole(.control)
                .tint(AppPalette.brandText)
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
                    Label(receiptSession.isComplete ? "Done" : receiptSession.isSaving ? "Saving purchases…" : receiptSession.isSubmitted ? (receiptSession.checkpoint.usesWholeReceiptLedger == true ? "Retry exact receipt" : "Retry unresolved rows") : "Add \(validItems.count.formatted()) to pantry", systemImage: receiptSession.isComplete ? "checkmark" : "plus")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(receiptSession.isSaving || validItems.isEmpty || (!receiptSession.isSubmitted && validItems.count != parsedItems.count))
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.row)
                .accessibilityIdentifier("receipt_add_to_pantry_button")
            }
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
        }
    }

    private var receiptPurchaseDate: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            DatePicker("Purchase date", selection: $receiptDate, in: ...Date(), displayedComponents: .date)
                .appTextRole(.control)
                .disabled(receiptSession.isSubmitted)
                .environment(\.timeZone, receiptSession.checkpoint.purchaseDay?.timeZone ?? .current)
            if !PantryPurchaseEvidence(currency: receiptCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()).isValid {
                Text("Open Receipt details below and use a three-letter currency code, or leave it blank if unknown.").foregroundStyle(AppPalette.caution)
            }
        }
        .appSurface(.quiet)
    }

    private var receiptContextCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityLabel("Captured grocery receipt")
            }

            TextField("Store name (optional)", text: $receiptStoreName).textFieldStyle(.roundedBorder)
                .disabled(receiptSession.isSubmitted).accessibilityIdentifier("receipt_store_name")
            TextField("Currency code if known, e.g. USD", text: $receiptCurrency).textInputAutocapitalization(.characters)
                .autocorrectionDisabled().textFieldStyle(.roundedBorder).disabled(receiptSession.isSubmitted)
                .accessibilityIdentifier("receipt_currency")
            Text("Prices are optional printed line amounts, separate from bought counts, package size and nutrition. No currency conversion or stock-cost calculation is performed.")
                .appTextRole(.caption).foregroundStyle(.secondary)

            Button {
                showingCamera = true
            } label: {
                Label("Retake or Choose Another", systemImage: "arrow.triangle.2.circlepath.camera")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .disabled(receiptSession.isSubmitted)
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt_capture_context")
    }

    private func receiptProductRow(_ product: PantryItem, index: Int) -> some View {
        let reviewed = PantryReceiptReviewRules.reviewedItems(from: [product]).first
        let expanded = expandedReceiptItemID == product.id
        let item = Binding(get: { parsedItems.first { $0.id == product.id } ?? product }, set: { edited in
            guard !receiptSession.isSubmitted, let position = parsedItems.firstIndex(where: { $0.id == product.id }) else { return }
            parsedItems[position] = edited
        })
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedReceiptItemID = expanded ? nil : product.id
            } label: {
                HStack(spacing: AppSpacing.row) {
                    Text(product.name.trimmed.isEmpty ? "Unnamed item" : product.name)
                        .appTextRole(.control).foregroundStyle(AppPalette.text)
                    Spacer(minLength: AppSpacing.compact)
                    if let reviewed {
                        Text("\(reviewed.quantity.formatted()) \(reviewed.unit)").monospacedDigit()
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    } else {
                        Label("Review", systemImage: "exclamationmark.circle")
                            .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("receipt_product_\(index)")
            if expanded { receiptItemEditor(item, index: index) }
        }
    }

    private func receiptItemEditor(_ item: Binding<PantryItem>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
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
            if let original = item.wrappedValue.purchaseEvidence?.originalReceiptName {
                Text("Receipt text: \(original)").appTextRole(.caption).foregroundStyle(.secondary)
            }
            labeledField("Optional printed price for this full line") {
                TextField("Unknown", text: Binding(get: {
                    item.wrappedValue.purchaseEvidence?.printedLinePriceText ?? item.wrappedValue.purchaseEvidence?.printedLinePrice.map { String($0) } ?? ""
                }, set: { text in
                    var evidence = item.wrappedValue.purchaseEvidence ?? PantryPurchaseEvidence(originalReceiptName: item.wrappedValue.name,
                        receiptRowQuantity: item.wrappedValue.quantity, receiptRowUnit: item.wrappedValue.unit)
                    evidence.printedLinePriceText = text; item.wrappedValue.purchaseEvidence = evidence
                })).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("receipt_line_price_\(index)")
            }
            if item.wrappedValue.purchaseEvidence?.isValid == false {
                Text("Review the optional printed price. Clear it if unreadable; it never determines stock quantity.").foregroundStyle(AppPalette.caution)
            }
            if let product = item.wrappedValue.productSnapshot {
                Text("Product: \(product.name) · \(product.brand ?? "brand not reported")")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                Text(product.packageQuantity.flatMap { amount in product.packageUnit.map { "Package label: \(amount.formatted()) \($0)" } } ?? "Package size unconfirmed; nutrition serving is separate")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            Button(item.wrappedValue.productSnapshot == nil ? "Match this receipt row to a product" : "Review matched product") {
                reviewingReceiptProduct = item.wrappedValue
            }.frame(minHeight: 44).accessibilityIdentifier("receipt_match_product_\(item.wrappedValue.id)")
            Button(role: .destructive) {
                let id = item.wrappedValue.id
                parsedItems.removeAll { $0.id == id }
            } label: { Label("Remove item", systemImage: "trash") }
            .accessibilityLabel("Remove \(item.wrappedValue.name)")
        }
        .textFieldStyle(.roundedBorder)
        .padding(.bottom, AppSpacing.group)
        .accessibilityIdentifier("receipt_review_item_\(index)")
    }

    private func receiptRowStatus(index: Int) -> some View {
        let row = receiptSession.checkpoint.rows[index]
        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(row.item.name).appTextRole(.control)
            Text("\(row.item.quantity.formatted()) \(row.item.unit) · \(row.status.rawValue.capitalized)")
                .appTextRole(.secondary)
            if let error = row.error { Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution) }
            if let evidence = row.item.purchaseEvidence {
                Text("Printed line: \(evidence.reviewedPrice.map { String($0) } ?? "unknown") \(evidence.currency ?? "currency unknown") · \(evidence.storeName ?? "store not reported")")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .appSurface(.quiet)
        .accessibilityIdentifier("receipt_row_status_\(index)")
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
        guard PantryPurchaseEvidence(currency: receiptCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()).isValid else { return [] }
        return PantryReceiptReviewRules.reviewedItems(from: parsedItems)
    }
    private func saveReceiptContext() {
        guard !receiptSession.isSubmitted else { return }
        if receiptSession.updateContext(storeName: receiptStoreName, currency: receiptCurrency) { parsedItems = receiptSession.items }
    }

    private func processImage(_ image: UIImage) {
        guard !receiptSession.isSubmitted, receiptSession.userID == DIContainer.shared.authService.currentUserID else { return }
        let requestID = UUID()
        receiptAnalysisID = requestID
        isProcessing = true
        errorMessage = nil

        aiModel.parseGroceryReceipt(from: image) { result in
            DispatchQueue.main.async {
                guard receiptAnalysisID == requestID, receiptSession.userID == DIContainer.shared.authService.currentUserID else { return }
                receiptAnalysisID = nil
                isProcessing = false
                switch result {
                case .success(let items):
                    if items.isEmpty {
                        errorMessage = "No grocery items were detected. Try a clearer photo with the full receipt visible."
                    } else {
                        let digest = image.jpegData(compressionQuality: 0.9).map(PantryReceiptIdentityRules.digest)
                        if receiptSession.replaceSource(items: items, purchaseDate: receiptDate, digest: digest) {
                            parsedItems = receiptSession.items
                            receiptStoreName = receiptSession.checkpoint.storeName ?? ""; receiptCurrency = receiptSession.checkpoint.currency ?? ""
                        } else { errorMessage = "The previous receipt review is kept. The new scan could not replace its saved checkpoint." }
                    }
                case .failure:
                    errorMessage = "The receipt could not be read. Try a clearer photo with even lighting."
                }
            }
        }
    }

    private func saveToPantry() {
        if receiptSession.isComplete {
            if receiptSession.finish() { dismiss() }
            return
        }
        guard receiptSession.isSubmitted || receiptSession.update(items: parsedItems, purchaseDate: receiptDate) else { return }
        Task { await receiptSession.save(using: DIContainer.shared.nutritionRepository) }
    }
}

/// One recoverable stock operation, with permanent server status and cancellation.
struct InventoryOperationReviewView: View {
    @StateObject private var session: InventorySaveSession
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss
    let onResolved: () -> Void
    let onAccepted: ((InventoryMutation, TrainingFuelTarget?) -> Void)?
    @State private var notifiedAcceptedID: UUID?

    init(mutation: InventoryMutation? = nil, session existing: InventorySaveSession? = nil, trainingFuelTarget: TrainingFuelTarget? = nil, onAccepted: ((InventoryMutation, TrainingFuelTarget?) -> Void)? = nil, onResolved: @escaping () -> Void = {}) {
        let session = existing ?? InventorySaveSession(userID: DIContainer.shared.authService.currentUserID)
        if session.checkpoint == nil, let mutation { _ = session.prepare(mutation, trainingFuelTarget: trainingFuelTarget) }
        _session = StateObject(wrappedValue: session); self.onResolved = onResolved; self.onAccepted = onAccepted
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                reviewList
                saveFooter
            }
            .navigationTitle("Review stock").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(session.isWorking) } }
        }
        .onAppear { reportAccepted() }
        .onChange(of: session.checkpoint?.accepted) { _, _ in reportAccepted() }
        .interactiveDismissDisabled(session.isWorking)
        .disabled(session.isWorking)
    }

    private var reviewList: some View {
        List {
            if let value = session.checkpoint {
                if let target = value.trainingFuelTarget { TrainingFuelTargetContextView(target: target, onDismiss: value.submitted || session.isWorking ? nil : { _ = session.removeFuelContext() }) }
                Section {
                    Text(value.mutation.title).appTextRole(.sectionTitle)
                    Text(value.accepted ? "Saved to your account" : value.cancelled ? "Cancelled before saving" : value.submitted ? "Exact submitted review kept for recovery" : "Review before changing stock")
                        .accessibilityIdentifier("inventory_review_status")
                }
                Section("Stock changes") {
                    ForEach(value.mutation.after) { item in
                        let previous = value.mutation.before.first { $0.id == item.id }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).fontWeight(.semibold)
                            Text("\((previous?.quantity ?? 0).formatted(.number.precision(.fractionLength(0...3)))) → \(item.quantity.formatted(.number.precision(.fractionLength(0...3)))) \(item.unit)")
                            if item.quantityUnknown == true { Text("Quantity unknown; excluded from shopping coverage") }
                            if let date = item.bestBefore { Text("Entered date · \(date.formatted(date: .abbreviated, time: .omitted))") }
                        }
                    }
                }
                if let diary = value.mutation.diary {
                    Section(diary.desired == nil ? "Remove linked food entry" : "Food diary") {
                        Text("\(diary.day.displayDate.formatted(date: .complete, time: .omitted)) · \(diary.mealName)")
                        Text((diary.desired ?? diary.expected)?.name ?? "Linked portion")
                        Text("The stock and diary changes save together. Other foods and stock purchases stay in place.")
                    }
                }
                if value.mutation.grocery != nil {
                    Section("Shopping record") {
                        ForEach(value.mutation.grocery?.upserts ?? []) { item in
                            Text("\(item.name) · total bought \((item.purchasedQuantity ?? 0).formatted()) \(item.unit) · transferred \((item.transferredToPantryQuantity ?? 0).formatted()) \(item.unit)")
                        }
                        Text("Only the reviewed transfer creates pantry stock. Checking alone does not.")
                    }
                }
                if value.submitted, !value.accepted, !value.cancelled {
                    Section {
                        Button { Task { await session.resolve(using: DIContainer.shared.nutritionRepository, cancelPending: false, dailyLogService: dailyLogService) } } label: {
                            Text("Check saved status").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.accessibilityIdentifier("inventory_check_status")
                        Button { Task { await session.resolve(using: DIContainer.shared.nutritionRepository, cancelPending: true, dailyLogService: dailyLogService) } } label: {
                            Text("Cancel pending save").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.accessibilityIdentifier("inventory_cancel_pending")
                    } header: {
                        Text("Recover this save").accessibilityIdentifier("inventory_review_recovery")
                    }
                }
                if !value.submitted {
                    Button("Discard this review", role: .destructive) { if session.finish() { onResolved(); dismiss() } }
                }
            }
        }.appFormStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory_review_list")
    }

    private var saveFooter: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let message = session.errorMessage {
                Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityIdentifier("inventory_review_error")
            }
            Button(actionTitle) {
                if session.checkpoint?.accepted == true || session.checkpoint?.cancelled == true {
                    if session.finish() { onResolved(); dismiss() }
                } else { Task { await session.save(using: DIContainer.shared.nutritionRepository, dailyLogService: dailyLogService) } }
            }
            .buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isWorking || session.checkpoint == nil)
            .accessibilityIdentifier("inventory_review_confirm")
        }
        .padding().background(AppPalette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory_review_footer")
    }

    private func reportAccepted() {
        guard let value = session.checkpoint, value.accepted, notifiedAcceptedID != value.mutation.id else { return }
        notifiedAcceptedID = value.mutation.id; onAccepted?(value.mutation, value.trainingFuelTarget)
    }
    private var actionTitle: String {
        if session.isWorking { return "Saving…" }
        if session.checkpoint?.accepted == true || session.checkpoint?.cancelled == true { return "Done" }
        return session.checkpoint?.submitted == true ? "Retry exact stock save" : "Save reviewed changes"
    }
}

struct StockItemEditorView: View {
    private let ownerID: String?
    let original: PantryItem?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var item: PantryItem
    @State private var unknown: Bool
    @State private var hasDate: Bool
    @State private var enteredDate: Date
    @State private var review: InventoryMutation?
    @State private var error: String?

    init(item: PantryItem? = nil, name: String = "", newQuantityUnknown: Bool = false, onSaved: @escaping () -> Void = {}) {
        original = item; self.onSaved = onSaved; ownerID = DIContainer.shared.authService.currentUserID
        _item = State(initialValue: item ?? PantryItem(name: name, quantity: 1, unit: "item", category: IngredientCategoryMapper.groceryCategory(for: name)))
        _unknown = State(initialValue: item?.quantityUnknown ?? newQuantityUnknown)
        _hasDate = State(initialValue: item?.bestBefore != nil)
        _enteredDate = State(initialValue: item?.bestBefore ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient or stock lot") {
                    TextField("Name", text: $item.name).accessibilityIdentifier("inventory_item_name")
                    Toggle("Quantity unknown", isOn: $unknown).accessibilityIdentifier("inventory_quantity_unknown")
                    if !unknown {
                        TextField("Amount", value: $item.quantity, format: .number).keyboardType(.decimalPad).accessibilityIdentifier("inventory_item_quantity")
                        Picker("Unit", selection: $item.unit) {
                            ForEach(Array(Set(InventoryQuantityRules.units + [item.unit])).sorted(), id: \.self) { Text($0).tag($0) }
                        }.disabled(item.isCookedBatch).accessibilityIdentifier("inventory_item_unit")
                    }
                    if original?.quantityVerified != true, original != nil {
                        Text("Your original amount is kept above. Confirm the actual amount before saving; an old default of one item has not been treated as measured stock.")
                    }
                    TextField("Category", text: $item.category)
                    TextField("Storage location", text: Binding(get: { item.location ?? "" }, set: { item.location = $0.isEmpty ? nil : $0 }))
                    Picker("Preparation", selection: Binding(get: { item.preparation ?? "Unknown" }, set: { item.preparation = $0 })) {
                        ForEach(["Unknown", "As purchased", "Raw", "Cooked"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Optional date") {
                    Toggle("Enter best-before or use-by date", isOn: $hasDate)
                    if hasDate { DatePicker("Entered date", selection: $enteredDate, displayedComponents: .date) }
                    Text("This is your entered label date, not a calculated freshness or food-safety assessment.")
                }
            }.appFormStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inventory_item_editor")
            .navigationTitle(original == nil ? "Add stock" : "Edit stock").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let error {
                        Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .fixedSize(horizontal: false, vertical: true).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .accessibilityIdentifier("inventory_item_error")
                    }
                    Button("Confirm amount and review") { prepare() }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("inventory_item_review")
                }
                .padding().background(AppPalette.canvas)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inventory_item_footer")
            }
            .sheet(item: $review, onDismiss: { onSaved() }) { mutation in
                InventoryOperationReviewView(mutation: mutation) { onSaved(); dismiss() }
            }
        }
    }
    private func prepare() {
        guard let owner = ownerID, DIContainer.shared.authService.currentUserID == owner else { error = InventoryError.accountChanged.localizedDescription; return }
        var updated = item
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.quantityUnknown = unknown; updated.quantityVerified = !unknown
        updated.bestBefore = hasDate ? Calendar.current.startOfDay(for: enteredDate) : nil
        updated.revisionID = UUID().uuidString
        let mutation = InventoryMutation(userID: owner, title: original == nil ? "Add \(updated.name)" : "Correct \(updated.name)", reason: original == nil ? .purchase : .correction, before: original.map { [$0] } ?? [], after: [updated])
        do { try mutation.validate(); review = mutation } catch { self.error = error.localizedDescription }
    }
}

struct StockCookReviewView: View {
    private let ownerID: String?
    let batch: MealCookingBatch
    let originalMeal: PlannedMeal
    @Environment(\.dismiss) private var dismiss
    @State private var stock: [PantryItem] = []
    @State private var selected: [Int: String] = [:]
    @State private var hasDate = false
    @State private var enteredDate = Date()
    @State private var error: String?
    @State private var loading = true
    @State private var review: InventoryMutation?
    @StateObject private var reservations = InventoryReservationService()
    @State private var allowReservationReallocation = false
    init(batch: MealCookingBatch, originalMeal: PlannedMeal) {
        self.batch = batch; self.originalMeal = originalMeal; ownerID = DIContainer.shared.authService.currentUserID
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(batch.name).fontWeight(.semibold)
                    Text("Record \(batch.totalPortions.formatted()) original portions as cooked stock.")
                    Text("Only explicitly selected pantry lots are deducted. Ingredients marked untracked stay unchanged. This does not log anything as eaten.")
                }
                Section("Planned stock reservations") {
                    if let snapshot = reservations.snapshot {
                        CookingReservationSummary(snapshot: snapshot, batchID: batch.id)
                        Toggle("I reviewed using stock planned for other meals", isOn: $allowReservationReallocation)
                            .disabled(!reservations.isFresh)
                        Text("If confirmed, those other saved plans may show a shortage after this cooking operation. Their recipes and physical stock are never silently changed by viewing reservations.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = reservations.errorMessage { Text(message).foregroundStyle(AppPalette.caution) }
                    PlannedStockReservationsLink()
                    Button("Refresh planned allocations") { Task { await refreshCookingSources() } }.disabled(loading)
                }
                ForEach(Array(batch.ingredientsPerPortion.enumerated()), id: \.offset) { index, ingredient in
                    Section(ingredient.name) {
                        if ingredient.hasKnownAmount {
                            Text("Cooking requirement · \((ingredient.quantity * batch.totalPortions).formatted(.number.precision(.fractionLength(0...3)))) \(ingredient.unit)")
                        } else { Text("Amount unconfirmed · \(ingredient.originalText). This ingredient stays untracked until a measured recipe amount is entered.") }
                        Picker("Deduct from", selection: Binding(get: { selected[index] ?? "" }, set: { selected[index] = $0 })) {
                            Text("Untracked / purchased outside pantry").tag("")
                            ForEach(stock.filter { !$0.isCookedBatch && $0.quantityVerified == true && $0.quantityUnknown != true && $0.isArchived != true && ($0.preparation != "Cooked" || InventoryQuantityRules.ingredientIdentity(ingredient.name).contains("cooked")) && InventoryQuantityRules.convert(ingredient.quantity, from: ingredient.unit, to: $0.unit) != nil }) { item in
                                Text("\(item.name) · physical \(item.quantity.formatted()) \(item.unit) · for this batch \(reservations.snapshot?.available(in: item.id, for: "batch-" + batch.id).map { $0.formatted() } ?? "unconfirmed") \(item.unit)").tag(item.id.uuidString)
                            }
                        }.disabled(!ingredient.hasKnownAmount).accessibilityIdentifier("inventory_cook_lot_\(index)")
                    }
                }
                Section("Cooked stock") {
                    Toggle("Enter a label date", isOn: $hasDate)
                    if hasDate { DatePicker("Entered date", selection: $enteredDate, displayedComponents: .date) }
                }
                if loading { ProgressView("Loading confirmed pantry lots") }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inventory_cook_form")
            .navigationTitle("Record cooking").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let error {
                        Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .fixedSize(horizontal: false, vertical: true).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .accessibilityIdentifier("inventory_cook_error")
                    }
                    Button("Review cooked batch") {
                        Task { await prepareReviewedCooking() }
                    }.buttonStyle(AppActionButtonStyle(.primary)).disabled(loading)
                        .accessibilityIdentifier("inventory_cook_review")
                }
                .padding().background(AppPalette.canvas)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inventory_cook_footer")
            }
            .sheet(item: $review) { mutation in InventoryOperationReviewView(mutation: mutation) { dismiss() } }
            .task { await refreshCookingSources() }
        }
    }
    @MainActor private func refreshCookingSources() async {
        guard let owner = ownerID, DIContainer.shared.authService.currentUserID == owner else { error = InventoryError.accountChanged.localizedDescription; loading = false; return }
        loading = true
        let accepted = await reservations.refresh(using: DIContainer.shared.nutritionRepository, includingBatchID: batch.id)
        guard DIContainer.shared.authService.currentUserID == owner else { loading = false; return }
        if accepted, let snapshot = reservations.snapshot { stock = snapshot.physicalStock; error = nil } else { error = reservations.errorMessage }
        loading = false
    }
    @MainActor private func prepareReviewedCooking() async {
        guard !loading, let owner = ownerID, DIContainer.shared.authService.currentUserID == owner else { return }
        let choices = selected, reallocate = allowReservationReallocation
        loading = true
        defer { loading = false }
        guard await reservations.refresh(using: DIContainer.shared.nutritionRepository, includingBatchID: batch.id),
              let snapshot = reservations.snapshot, reservations.isFresh else { error = reservations.errorMessage; return }
        guard DIContainer.shared.authService.currentUserID == owner, selected == choices,
              allowReservationReallocation == reallocate else { error = "Your selections changed while allocations refreshed. Review the current choices before continuing."; return }
        do {
            stock = snapshot.physicalStock
            let lots = choices.compactMapValues(UUID.init(uuidString:))
            try InventoryReservationRules.validateCooking(batch: batch, selectedLots: lots, snapshot: snapshot, stock: stock, allowReallocation: reallocate)
            var mutation = try InventoryPlanningRules.cooked(batch: batch, originalMeal: originalMeal, stock: stock, selectedLots: lots,
                userID: owner, bestBefore: hasDate ? Calendar.current.startOfDay(for: enteredDate) : nil)
            if reallocate { mutation.title += " · reviewed planned-stock reallocation" }
            review = mutation
        } catch { self.error = error.localizedDescription }
    }
}

struct StockConsumeReviewView: View {
    private let ownerID: String?
    let item: PantryItem
    let plannedMeal: PlannedMeal?
    let trainingFuelTarget: TrainingFuelTarget?
    let onAcceptedFood: ((TrainingFuelTarget) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double
    @State private var date: Date
    @State private var mealName: String
    @State private var alsoLog: Bool
    @State private var waste: Bool
    @State private var error: String?
    @State private var review: InventoryMutation?
    init(item: PantryItem, plannedMeal: PlannedMeal? = nil, date: Date = Date(), waste: Bool = false, alreadyLogged: Bool = false, trainingFuelTarget: TrainingFuelTarget? = nil, onAcceptedFood: ((TrainingFuelTarget) -> Void)? = nil) {
        self.trainingFuelTarget = trainingFuelTarget; self.onAcceptedFood = onAcceptedFood
        self.item = item; self.plannedMeal = plannedMeal; ownerID = DIContainer.shared.authService.currentUserID
        _amount = State(initialValue: plannedMeal?.portions ?? min(1, item.quantity))
        _date = State(initialValue: date); _mealName = State(initialValue: plannedMeal?.mealType ?? "Lunch")
        _alsoLog = State(initialValue: item.portionFood != nil && !waste && !alreadyLogged)
        _waste = State(initialValue: waste)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let trainingFuelTarget { TrainingFuelTargetContextView(target: trainingFuelTarget) }
                Section(item.name) {
                    Text("Available · \(item.quantity.formatted()) \(item.unit)")
                    Text("If this use also logs a diary entry, later amount edits or deletion adjust its linked stock too. Stock-only use has no diary link; review its Undo in Pantry → Stock history to reverse the deduction.")
                    if item.quantityVerified != true || item.quantityUnknown == true { Text("Confirm its quantity in Edit stock before recording use.").foregroundStyle(AppPalette.caution) }
                    TextField("Amount used", value: $amount, format: .number).keyboardType(.decimalPad).disabled(plannedMeal != nil)
                        .accessibilityIdentifier("inventory_consume_amount")
                    Text(item.unit)
                    if plannedMeal == nil { Toggle("Write off / waste", isOn: $waste) }
                    if !waste, item.portionFood != nil {
                        Toggle("Also log this food portion", isOn: $alsoLog).accessibilityIdentifier("inventory_consume_also_log")
                        Text("If you already logged it elsewhere, switch this off. A matching existing food is never silently logged or consumed again.")
                        if alsoLog {
                            DatePicker("Food log date", selection: $date, in: ...Date(), displayedComponents: .date).disabled(plannedMeal != nil)
                            Picker("Meal", selection: $mealName) { ForEach(MealPlanEditingRules.mealTypes, id: \.self) { Text($0).tag($0) } }
                        }
                    }
                }
            }.appFormStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inventory_consume_form")
            .navigationTitle(waste ? "Write off stock" : "Use stock").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let error {
                        Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .fixedSize(horizontal: false, vertical: true).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .accessibilityIdentifier("inventory_consume_error")
                    }
                    Button("Review stock use") {
                        guard let owner = ownerID, DIContainer.shared.authService.currentUserID == owner else { error = InventoryError.accountChanged.localizedDescription; return }
                        do { review = try InventoryPlanningRules.reducing(item: item, amount: amount, reason: waste ? .waste : .consume,
                            userID: owner, plannedMeal: plannedMeal, date: date, mealName: mealName, alsoLog: alsoLog && !waste)
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("inventory_consume_review")
                }
                .padding().background(AppPalette.canvas)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inventory_consume_footer")
            }
            .sheet(item: $review) { mutation in
                InventoryOperationReviewView(mutation: mutation, trainingFuelTarget: trainingFuelTarget, onAccepted: { accepted, target in
                    if accepted.diary?.desired != nil, let target { onAcceptedFood?(target) }
                }) { dismiss() }
            }
        }
    }
}

private struct StockUseRequest: Identifiable {
    let id = UUID()
    let item: PantryItem
    let waste: Bool
}

struct StockHistoryView: View {
    @ObservedObject private var healthSync = InventoryHealthSyncQueue.shared
    @Environment(\.dismiss) private var dismiss
    @State private var receipts: [InventoryReceipt] = []
    @State private var loading = true
    @State private var error: String?
    @State private var review: InventoryMutation?
    private var undone: Set<UUID> { Set(receipts.filter { $0.status == .accepted }.compactMap { try? $0.mutation().undoing }.compactMap { $0 }) }
    var body: some View {
        NavigationStack {
            List {
                Text("Accepted operations are permanent receipts. Undo submits a new checked adjustment and preserves later purchases. Used portions must be restored before a fully consumed cooking batch can be undone.")
                Text("Deleting a diary entry alone does not put physical food back. Use the checked stock Undo here when correcting a stock deduction.")
                if healthSync.pendingCount > 0 || healthSync.message != nil {
                    Section("Apple Health") {
                        Text(healthSync.message ?? "Nutrition export pending · \(healthSync.pendingCount) operations")
                        Button("Retry Health sync") {
                            if let owner = DIContainer.shared.authService.currentUserID { healthSync.retry(userID: owner) }
                        }.accessibilityIdentifier("inventory_retry_health")
                    }
                }
                if loading { ProgressView("Loading stock history") }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
                ForEach(receipts) { receipt in
                    if let operation = try? receipt.mutation() {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(operation.title).fontWeight(.semibold)
                            Text("\(operation.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(receipt.status.rawValue)").foregroundStyle(.secondary)
                            if undone.contains(operation.id) { Text("Reversed by a later stock adjustment").foregroundStyle(.secondary) } else if receipt.status == .accepted, operation.reason != .undo {
                                Button("Review Undo") { Task { await prepareUndo(operation) } }
                                    .accessibilityIdentifier("inventory_undo_\(operation.id.uuidString)")
                            }
                        }
                    }
                }
            }.appFormStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inventory_history_list")
            .navigationTitle("Stock history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $review, onDismiss: { Task { await load() } }) { mutation in
                InventoryOperationReviewView(mutation: mutation) { Task { await load() } }
            }
            .task { await load() }
        }
    }
    private func load() async {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        do {
            let current = try await DIContainer.shared.nutritionRepository.fetchInventoryHistory(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            receipts = current.sorted { ((try? $0.mutation().createdAt) ?? .distantPast) > ((try? $1.mutation().createdAt) ?? .distantPast) }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func prepareUndo(_ operation: InventoryMutation) async {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        do {
            let stock = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
            let groceries = try await DIContainer.shared.nutritionRepository.fetchGroceryList(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            review = try InventoryPlanningRules.undoing(operation, current: stock, groceries: groceries)
        } catch { self.error = error.localizedDescription }
    }
}

struct GroceryStockTransferView: View {
    private let ownerID: String?
    let item: GroceryListItem
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var totalBought: Double
    @State private var transferring: Double
    @State private var addStock = true
    @State private var review: InventoryMutation?
    @State private var error: String?
    init(item: GroceryListItem, onSaved: @escaping () -> Void = {}) {
        self.item = item; self.onSaved = onSaved; ownerID = DIContainer.shared.authService.currentUserID
        let amount = item.quantityUnknown == true ? item.purchasedQuantity ?? 0 : max(item.quantity, item.purchasedQuantity ?? 0)
        _totalBought = State(initialValue: amount)
        _transferring = State(initialValue: max(0, amount - (item.transferredToPantryQuantity ?? 0)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    if item.quantityUnknown == true {
                        Text("Recipe amount unconfirmed. Enter the actual amount bought; no default item or gram amount has been assumed.")
                    } else { Text("Shopping requirement · \(item.quantity.formatted()) \(item.unit)") }
                    Text("Already transferred · \((item.transferredToPantryQuantity ?? 0).formatted()) \(item.unit)")
                    TextField("Actual total bought", value: $totalBought, format: .number).keyboardType(.decimalPad)
                        .accessibilityIdentifier("grocery_actual_bought")
                    Toggle("Also add this purchase to pantry", isOn: $addStock).accessibilityIdentifier("grocery_purchase_add_stock")
                    if addStock {
                        TextField("Add to pantry now", value: $transferring, format: .number).keyboardType(.decimalPad)
                            .accessibilityIdentifier("grocery_transfer_amount")
                    }
                    Text("Amounts are \(item.unit). One item or package stays a count; it is not converted into nutritional servings or grams. Confirm the actual amount bought.")
                }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
            }.appFormStyle()
            .navigationTitle("Bought → pantry").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Review purchase and stock") {
                    guard let owner = ownerID, DIContainer.shared.authService.currentUserID == owner else { error = InventoryError.accountChanged.localizedDescription; return }
                    do { review = try InventoryPlanningRules.purchasing(item: item, totalBought: totalBought, transferAmount: addStock ? transferring : 0, userID: owner) } catch { self.error = error.localizedDescription }
                }.buttonStyle(AppActionButtonStyle(.primary)).padding().background(AppPalette.canvas)
                    .accessibilityIdentifier("grocery_transfer_review")
            }
            .sheet(item: $review) { mutation in InventoryOperationReviewView(mutation: mutation) { onSaved(); dismiss() } }
        }
    }
}
