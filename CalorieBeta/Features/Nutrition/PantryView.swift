import SwiftUI

struct PantryView: View {
    @EnvironmentObject var pantryService: PantryService
    @State private var newItemName = ""
    @State private var showingRecipeGeneration = false
    @State private var showingReceiptScanner = false

    private var groupedItems: [String: [PantryItem]] {
        Dictionary(grouping: pantryService.pantryItems, by: { $0.category })
    }

    private var isReceiptScannerEnabled: Bool {
        DIContainer.shared.featureFlagService?.isFeatureEnabled(.receiptScanner) ?? FeatureFlag.receiptScanner.defaultValue
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                pantryList
                addItemBar
            }
            .navigationTitle("Smart pantry")
            .onAppear {
                if let userID = DIContainer.shared.authService.currentUserID {
                    pantryService.startListening(userID: userID)
                }
            }
            .sheet(isPresented: $showingRecipeGeneration) {
                PantryRecipeGenerationView(pantryService: pantryService)
            }
            .sheet(isPresented: $showingReceiptScanner) {
                if isReceiptScannerEnabled {
                    ReceiptScannerView()
                }
            }
        }
    }

    private var pantryList: some View {
        List {
            if pantryService.isLoading && pantryService.pantryItems.isEmpty {
                ProgressView("Loading pantry")
            } else if pantryService.pantryItems.isEmpty {
                Text("Your pantry is empty. Add ingredients below.")
                    .foregroundColor(.secondary)
                    .padding()
            }

            ForEach(groupedItems.keys.sorted(), id: \.self) { category in
                Section(header: Text(category)) {
                    ForEach(groupedItems[category] ?? []) { item in
                        PantryItemRow(item: item)
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: pantryService.pantryItems.isEmpty ? 72 : 132)
        }
    }

    private var addItemBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if isReceiptScannerEnabled {
                    Button(action: { showingReceiptScanner = true }) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Scan receipt")
                }
                
                TextField("Add ingredient", text: $newItemName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(addItem)

                Button("Add", action: addItem)
                    .disabled(trimmedNewItemName.isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))

            if !pantryService.pantryItems.isEmpty {
                Button(action: { showingRecipeGeneration = true }) {
                    Label("Generate pantry recipe", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandPrimary)
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var trimmedNewItemName: String {
        newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
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
}

private struct PantryItemRow: View {
    let item: PantryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                Text(item.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(quantityText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var quantityText: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        let quantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
        return "\(quantity) \(item.unit)"
    }
}

struct PantryRecipeGenerationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var recipeService: RecipeService
    @ObservedObject var pantryService: PantryService

    @State private var generatedRecipes: [Recipe] = []
    @State private var isGenerating = true
    @State private var savingName: String?
    @State private var savedNames: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isGenerating {
                    VStack {
                        ProgressView("Generating recipes")
                            .tint(.blue)
                            .padding()
                        Text("Only your pantry ingredients are included in the prompt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else if let errorMessage {
                    VStack {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                        Button("Try again", action: generateRecipe)
                            .buttonStyle(.bordered)
                            .tint(.blue)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(Array(generatedRecipes.enumerated()), id: \.offset) { _, recipe in
                                recipeCard(recipe)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Pantry recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: generateRecipe)
        }
    }

    private func recipeCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(.title3)
                .bold()

            LazyVGrid(columns: nutritionColumns, spacing: 8) {
                nutritionBadge(label: "Calories", value: "\(formatted(recipe.nutrition.calories)) cal")
                nutritionBadge(label: "Protein", value: "\(formatted(recipe.nutrition.protein)) g")
                nutritionBadge(label: "Carbs", value: "\(formatted(recipe.nutrition.carbs)) g")
                nutritionBadge(label: "Fat", value: "\(formatted(recipe.nutrition.fats)) g")
            }

            Text("Ingredients")
                .font(.headline)
            ForEach(recipe.ingredients, id: \.self) { ingredient in
                Text("- \(ingredient)")
                    .font(.subheadline)
            }

            Text("Instructions")
                .font(.headline)
            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                Text("\(index + 1). \(instruction)")
                    .font(.subheadline)
            }

            Button {
                save(recipe)
            } label: {
                if savedNames.contains(recipe.name) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                } else if savingName == recipe.name {
                    Text("Saving")
                } else {
                    Label("Save recipe", systemImage: "bookmark")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(savedNames.contains(recipe.name) || savingName != nil)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var nutritionColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func nutritionBadge(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func formatted(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    private func generateRecipe() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        isGenerating = true
        errorMessage = nil

        let items = pantryService.pantryItems
            .map { "\($0.quantity) \($0.unit) \($0.name)" }
            .joined(separator: ", ")

        Task {
            let recipes = await recipeService.createRecipesFromPantry(itemsString: items, userID: userID)
            await MainActor.run {
                isGenerating = false
                if recipes.isEmpty {
                    errorMessage = "Failed to generate recipes. Please try again."
                } else {
                    generatedRecipes = recipes
                }
            }
        }
    }

    private func save(_ recipe: Recipe) {
        guard savingName == nil, !savedNames.contains(recipe.name) else { return }
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        savingName = recipe.name
        errorMessage = nil
        Task {
            do {
                _ = try await recipeService.saveRecipe(recipe, for: userID)
                await MainActor.run {
                    savedNames.insert(recipe.name)
                    savingName = nil
                }
            } catch {
                await MainActor.run {
                    savingName = nil
                    errorMessage = "Couldn't save recipe. Please try again."
                }
            }
        }
    }
}

struct ReceiptScannerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var pantryService: PantryService
    
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var scanningImage: UIImage?
    @State private var isProcessing = false
    @State private var parsedItems: [PantryItem] = []
    @State private var errorMessage: String?
    
    private let aiModel = MLImageModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if isProcessing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.blue)
                        Text("Parsing receipt. This may take a few seconds.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !parsedItems.isEmpty {
                    List {
                        Section(header: Text("Items found (\(parsedItems.count.formatted()))")) {
                            ForEach($parsedItems) { $item in
                                HStack {
                                    VStack(alignment: .leading) {
                                        TextField("Name", text: $item.name)
                                            .font(.headline)
                                        HStack {
                                            TextField("Amount", value: $item.quantity, format: .number)
                                                .keyboardType(.decimalPad)
                                                .frame(width: 50)
                                            TextField("Unit", text: $item.unit)
                                                .frame(width: 60)
                                            Divider()
                                                .frame(height: 16)
                                            TextField("Category", text: $item.category)
                                                .foregroundColor(.secondary)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                            }
                            .onDelete { indices in
                                parsedItems.remove(atOffsets: indices)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    
                    Button {
                        saveToPantry()
                    } label: {
                        Text("Add to pantry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.brandPrimary)
                            .cornerRadius(10)
                            .padding()
                    }
                } else {
                    VStack(spacing: 24) {
                        Image(systemName: "doc.text.viewfinder")
                            .appFont(size: 60)
                            .foregroundColor(.blue)
                        
                        Text("Scan a grocery receipt")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Take a photo of your receipt and the AI will automatically identify the food items and stock your smart pantry.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 32)
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            showingCamera = true
                        }) {
                            Label("Take photo", systemImage: "camera")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandPrimary)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 32)
                        .onChange(of: capturedImage) { _, newValue in
                            if let uiImage = newValue {
                                scanningImage = uiImage
                                processImage(uiImage)
                            }
                        }
                        .sheet(isPresented: $showingCamera) {
                            ImagePicker(sourceType: .camera) { uiImage in
                                capturedImage = uiImage
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Receipt scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        aiModel.parseGroceryReceipt(from: image) { result in
            isProcessing = false
            switch result {
            case .success(let items):
                if items.isEmpty {
                    errorMessage = "No food items found on this receipt."
                } else {
                    parsedItems = items
                }
            case .failure(let error):
                errorMessage = "Couldn't read receipt: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveToPantry() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        for item in parsedItems {
            pantryService.addOrUpdateItem(item, userID: userID)
        }
        dismiss()
    }
}
