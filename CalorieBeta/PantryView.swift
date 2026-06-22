import SwiftUI
import FirebaseAuth

struct PantryView: View {
    @EnvironmentObject var pantryService: PantryService
    @State private var newItemName = ""
    @State private var showingRecipeGeneration = false
    @State private var showingReceiptScanner = false

    private var groupedItems: [String: [PantryItem]] {
        Dictionary(grouping: pantryService.pantryItems, by: { $0.category })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                pantryList
                addItemBar
            }
            .navigationTitle("Smart Pantry")
            .onAppear {
                if let user = Auth.auth().currentUser {
                    pantryService.startListening(userID: user.uid)
                }
            }
            .sheet(isPresented: $showingRecipeGeneration) {
                PantryRecipeGenerationView(pantryService: pantryService)
            }
            .sheet(isPresented: $showingReceiptScanner) {
                ReceiptScannerView()
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
                Button(action: { showingReceiptScanner = true }) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundColor(.brandPrimary)
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
                    Label("Generate Pantry Recipe", systemImage: "sparkles")
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
        guard let user = Auth.auth().currentUser else { return }
        let trimmed = trimmedNewItemName
        guard !trimmed.isEmpty else { return }

        let item = PantryItem(
            name: trimmed,
            quantity: 1,
            unit: "item",
            category: IngredientCategoryMapper.groceryCategory(for: trimmed)
        )
        pantryService.addOrUpdateItem(item, userID: user.uid)
        newItemName = ""
    }

    private func delete(_ item: PantryItem) {
        guard let user = Auth.auth().currentUser else { return }
        pantryService.deleteItem(item, userID: user.uid)
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

    @State private var generatedRecipe: Recipe?
    @State private var isGenerating = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                if isGenerating {
                    ProgressView("Generating recipe...")
                        .padding()
                    Text("Only pantry ingredients are included in the prompt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Button("Try Again", action: generateRecipe)
                } else if let recipe = generatedRecipe {
                    recipePreview(recipe)

                    Button(isSaving ? "Saving..." : "Save Recipe") {
                        saveAndDismiss(recipe: recipe)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                    .padding()
                }
            }
            .navigationTitle("Pantry Recipe AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: generateRecipe)
        }
    }

    private func recipePreview(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recipe.name)
                    .font(.title)
                    .bold()

                Text("Nutrition per serving")
                    .font(.headline)
                HStack {
                    Text("\(Int(recipe.nutrition.calories)) kcal")
                    Text("\(Int(recipe.nutrition.protein))g protein")
                    Text("\(Int(recipe.nutrition.carbs))g carbs")
                    Text("\(Int(recipe.nutrition.fats))g fat")
                }
                .font(.subheadline)

                Text("Ingredients")
                    .font(.headline)
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    Text("- \(ingredient)")
                }

                Text("Instructions")
                    .font(.headline)
                ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                    Text("\(index + 1). \(instruction)")
                }
            }
            .padding()
        }
    }

    private func generateRecipe() {
        guard let user = Auth.auth().currentUser else { return }
        isGenerating = true
        errorMessage = nil

        let items = pantryService.pantryItems
            .map { "\($0.quantity) \($0.unit) \($0.name)" }
            .joined(separator: ", ")

        Task {
            let recipe = await recipeService.createRecipeFromPantry(itemsString: items, userID: user.uid)
            await MainActor.run {
                isGenerating = false
                if let recipe {
                    generatedRecipe = recipe
                } else {
                    errorMessage = "Failed to generate recipe. Please try again."
                }
            }
        }
    }

    private func saveAndDismiss(recipe: Recipe) {
        guard !isSaving else { return }
        Task {
            guard let user = Auth.auth().currentUser else { return }
            await MainActor.run {
                isSaving = true
                errorMessage = nil
            }

            do {
                _ = try await recipeService.saveRecipe(recipe, for: user.uid)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save recipe. Please try again."
                }
            }
        }
    }
}


struct ReceiptScannerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var pantryService: PantryService
    
    @State private var capturedImage: UIImage? = nil
    @State private var showingCamera = false
    @State private var scanningImage: UIImage? = nil
    @State private var isProcessing = false
    @State private var parsedItems: [PantryItem] = []
    @State private var errorMessage: String? = nil
    
    private let aiModel = MLImageModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if isProcessing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Parsing receipt... this may take a few seconds.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !parsedItems.isEmpty {
                    List {
                        Section(header: Text("Items Found (\(parsedItems.count))")) {
                            ForEach($parsedItems) { $item in
                                HStack {
                                    VStack(alignment: .leading) {
                                        TextField("Name", text: $item.name)
                                            .font(.headline)
                                        HStack {
                                            TextField("Qty", value: $item.quantity, format: .number)
                                                .keyboardType(.decimalPad)
                                                .frame(width: 50)
                                            TextField("Unit", text: $item.unit)
                                                .frame(width: 60)
                                            Text("•")
                                                .foregroundColor(.secondary)
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
                        Text("Add to Pantry")
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
                            .font(.system(size: 60))
                            .foregroundColor(.brandPrimary)
                        
                        Text("Scan a Grocery Receipt")
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
                            Label("Take Photo", systemImage: "camera")
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
                            ImagePicker(image: $capturedImage, sourceType: .camera)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Receipt Scanner")
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
                errorMessage = "Failed to parse receipt: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveToPantry() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        for item in parsedItems {
            pantryService.addOrUpdateItem(item, userID: userID)
        }
        dismiss()
    }
}
