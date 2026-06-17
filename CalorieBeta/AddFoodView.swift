import SwiftUI
import FirebaseAuth

struct AddFoodView: View {
    // New arguments for Smart Serving logic
    var initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    var date: Date = Date()
    var source: String = "manual"
    var onLogUpdated: () -> Void
    var onUpdate: ((FoodItem) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var bannerService: BannerService
    private let foodAPIService = FatSecretFoodAPIService()
    private let imageModel = MLImageModel()

    @State private var foodName: String
    @State private var availableServings: [ServingSizeOption] = []
    @State private var selectedServingID: UUID? = nil
    @State private var quantity: String = "1"
    @State private var isLoadingDetails: Bool = false
    @State private var errorLoading: String? = nil

    @State private var isLoggedItem: Bool
    @State private var baseLoggedItemNutrientsPerUnit: ServingSizeOption?
    
    @State private var isSavedAsCustom: Bool = false
    @State private var customFoodForAction: FoodItem?

    @State private var showingImagePicker = false
    @State private var isProcessingLabel = false
    @State private var scanError: (Bool, String) = (false, "")

    // MARK: - Robust Initializer
    init(initialFoodItem: FoodItem, dailyLog: Binding<DailyLog?>, date: Date = Date(), source: String = "manual", onLogUpdated: @escaping () -> Void, onUpdate: ((FoodItem) -> Void)? = nil) {
        self.initialFoodItem = initialFoodItem
        self._dailyLog = dailyLog
        self.date = date
        self.source = source
        self.onLogUpdated = onLogUpdated
        self.onUpdate = onUpdate
        
        let isEditingLoggedItem = source.starts(with: "log_")
        self._isLoggedItem = State(initialValue: isEditingLoggedItem)
        self._foodName = State(initialValue: initialFoodItem.name)

        // Robust initialization using new fields if available
        if let explicitQty = initialFoodItem.quantityValue {
            self._quantity = State(initialValue: String(format: "%g", explicitQty))
        } else {
            // Backward compatibility fallback
            if isEditingLoggedItem || source == "image_result_edit" {
                let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
                let qty = parsed.qty > 0 ? parsed.qty : 1.0
                self._quantity = State(initialValue: String(format: "%g", qty))
            } else {
                self._quantity = State(initialValue: "1")
            }
        }
    }
    
    private func parseQuantityFromServing(_ servingDesc: String) -> (qty: Double, baseDesc: String) {
        let components = servingDesc.components(separatedBy: " x ")
        if components.count == 2, let qty = Double(components[0]), qty > 0 {
            return (qty, components[1])
        }
        return (1.0, servingDesc)
    }

    private var selectedServingOption: ServingSizeOption? {
        guard let selectedID = selectedServingID else { return nil }
        return availableServings.first { $0.id == selectedID }
    }

    // MARK: - Adjusted Nutrients Calculation
    private var adjustedNutrients: (
        calories: Double, protein: Double, carbs: Double, fats: Double,
        saturatedFat: Double?, polyunsaturatedFat: Double?, monounsaturatedFat: Double?,
        fiber: Double?, calcium: Double?, iron: Double?, potassium: Double?, sodium: Double?,
        vitaminA: Double?, vitaminC: Double?, vitaminD: Double?, vitaminB12: Double?, folate: Double?,
        magnesium: Double?, phosphorus: Double?, zinc: Double?, copper: Double?, manganese: Double?, selenium: Double?,
        vitaminB1: Double?, vitaminB2: Double?, vitaminB3: Double?, vitaminB5: Double?, vitaminB6: Double?, vitaminE: Double?, vitaminK: Double?,
        servingDescription: String, servingWeightGrams: Double,
        quantityValue: Double, servingUnit: String // New return values
    ) {
        guard let quantityValue = Double(quantity), quantityValue > 0 else {
            // Fallback to initial values if input is invalid
            let unit = initialFoodItem.servingUnit ?? "serving"
            return (
                calories: initialFoodItem.calories, protein: initialFoodItem.protein, carbs: initialFoodItem.carbs, fats: initialFoodItem.fats,
                saturatedFat: initialFoodItem.saturatedFat, polyunsaturatedFat: initialFoodItem.polyunsaturatedFat, monounsaturatedFat: initialFoodItem.monounsaturatedFat,
                fiber: initialFoodItem.fiber, calcium: initialFoodItem.calcium, iron: initialFoodItem.iron, potassium: initialFoodItem.potassium, sodium: initialFoodItem.sodium,
                vitaminA: initialFoodItem.vitaminA, vitaminC: initialFoodItem.vitaminC, vitaminD: initialFoodItem.vitaminD, vitaminB12: initialFoodItem.vitaminB12,
                folate: initialFoodItem.folate, magnesium: initialFoodItem.magnesium, phosphorus: initialFoodItem.phosphorus, zinc: initialFoodItem.zinc,
                copper: initialFoodItem.copper, manganese: initialFoodItem.manganese, selenium: initialFoodItem.selenium, vitaminB1: initialFoodItem.vitaminB1,
                vitaminB2: initialFoodItem.vitaminB2, vitaminB3: initialFoodItem.vitaminB3, vitaminB5: initialFoodItem.vitaminB5, vitaminB6: initialFoodItem.vitaminB6,
                vitaminE: initialFoodItem.vitaminE, vitaminK: initialFoodItem.vitaminK,
                servingDescription: initialFoodItem.servingSize,
                servingWeightGrams: initialFoodItem.servingWeight,
                quantityValue: 1.0,
                servingUnit: unit
            )
        }

        // Determine base unit name
        let unitName: String
        let baseNutrients: ServingSizeOption
        
        if let selected = selectedServingOption {
            baseNutrients = selected
            unitName = selected.description
        } else {
            // Fallback construction from initial item
            let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
            let initialQty = parsed.qty
            baseNutrients = ServingSizeOption(
                description: parsed.baseDesc,
                servingWeightGrams: initialFoodItem.servingWeight / initialQty,
                calories: initialFoodItem.calories / initialQty,
                protein: initialFoodItem.protein / initialQty,
                carbs: initialFoodItem.carbs / initialQty,
                fats: initialFoodItem.fats / initialQty,
                saturatedFat: initialFoodItem.saturatedFat.map { $0 / initialQty },
                polyunsaturatedFat: initialFoodItem.polyunsaturatedFat.map { $0 / initialQty },
                monounsaturatedFat: initialFoodItem.monounsaturatedFat.map { $0 / initialQty },
                fiber: initialFoodItem.fiber.map { $0 / initialQty },
                calcium: initialFoodItem.calcium.map { $0 / initialQty },
                iron: initialFoodItem.iron.map { $0 / initialQty },
                potassium: initialFoodItem.potassium.map { $0 / initialQty },
                sodium: initialFoodItem.sodium.map { $0 / initialQty },
                vitaminA: initialFoodItem.vitaminA.map { $0 / initialQty },
                vitaminC: initialFoodItem.vitaminC.map { $0 / initialQty },
                vitaminD: initialFoodItem.vitaminD.map { $0 / initialQty },
                vitaminB12: initialFoodItem.vitaminB12.map { $0 / initialQty },
                folate: initialFoodItem.folate.map { $0 / initialQty },
                magnesium: initialFoodItem.magnesium.map { $0 / initialQty },
                phosphorus: initialFoodItem.phosphorus.map { $0 / initialQty },
                zinc: initialFoodItem.zinc.map { $0 / initialQty },
                copper: initialFoodItem.copper.map { $0 / initialQty },
                manganese: initialFoodItem.manganese.map { $0 / initialQty },
                selenium: initialFoodItem.selenium.map { $0 / initialQty },
                vitaminB1: initialFoodItem.vitaminB1.map { $0 / initialQty },
                vitaminB2: initialFoodItem.vitaminB2.map { $0 / initialQty },
                vitaminB3: initialFoodItem.vitaminB3.map { $0 / initialQty },
                vitaminB5: initialFoodItem.vitaminB5.map { $0 / initialQty },
                vitaminB6: initialFoodItem.vitaminB6.map { $0 / initialQty },
                vitaminE: initialFoodItem.vitaminE.map { $0 / initialQty },
                vitaminK: initialFoodItem.vitaminK.map { $0 / initialQty }
            )
            unitName = parsed.baseDesc
        }

        let factor = quantityValue
        let finalDescription = quantityValue == 1 ? unitName : "\(String(format: "%g", quantityValue)) x \(unitName)"
        let finalWeight = (baseNutrients.servingWeightGrams ?? 0) * factor
        
        return (
            calories: baseNutrients.calories * factor,
            protein: baseNutrients.protein * factor,
            carbs: baseNutrients.carbs * factor,
            fats: baseNutrients.fats * factor,
            saturatedFat: baseNutrients.saturatedFat.map { $0 * factor },
            polyunsaturatedFat: baseNutrients.polyunsaturatedFat.map { $0 * factor },
            monounsaturatedFat: baseNutrients.monounsaturatedFat.map { $0 * factor },
            fiber: baseNutrients.fiber.map { $0 * factor },
            calcium: baseNutrients.calcium.map { $0 * factor },
            iron: baseNutrients.iron.map { $0 * factor },
            potassium: baseNutrients.potassium.map { $0 * factor },
            sodium: baseNutrients.sodium.map { $0 * factor },
            vitaminA: baseNutrients.vitaminA.map { $0 * factor },
            vitaminC: baseNutrients.vitaminC.map { $0 * factor },
            vitaminD: baseNutrients.vitaminD.map { $0 * factor },
            vitaminB12: baseNutrients.vitaminB12.map { $0 * factor },
            folate: baseNutrients.folate.map { $0 * factor },
            magnesium: baseNutrients.magnesium.map { $0 * factor },
            phosphorus: baseNutrients.phosphorus.map { $0 * factor },
            zinc: baseNutrients.zinc.map { $0 * factor },
            copper: baseNutrients.copper.map { $0 * factor },
            manganese: baseNutrients.manganese.map { $0 * factor },
            selenium: baseNutrients.selenium.map { $0 * factor },
            vitaminB1: baseNutrients.vitaminB1.map { $0 * factor },
            vitaminB2: baseNutrients.vitaminB2.map { $0 * factor },
            vitaminB3: baseNutrients.vitaminB3.map { $0 * factor },
            vitaminB5: baseNutrients.vitaminB5.map { $0 * factor },
            vitaminB6: baseNutrients.vitaminB6.map { $0 * factor },
            vitaminE: baseNutrients.vitaminE.map { $0 * factor },
            vitaminK: baseNutrients.vitaminK.map { $0 * factor },
            servingDescription: finalDescription,
            servingWeightGrams: finalWeight,
            quantityValue: quantityValue,
            servingUnit: unitName
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack {
                    Text(FoodEmojiMapper.getEmoji(for: foodName) + " " + foodName)
                        .appFont(size: 22, weight: .bold)
                        .multilineTextAlignment(.center)
                        .padding(.top)
                        .padding(.horizontal)
                    Text("Serving: \(adjustedNutrients.servingDescription)")
                        .appFont(size: 15)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding(.bottom, 8)
                }.padding(.bottom, 5)
                Divider()
                
                Form {
                    Section(header: Text("Nutritional Information (Adjusted)"), footer: labelScannerButton) {
                        if isLoadingDetails && !isLoggedItem && source != "recent_tap" {
                            ProgressView()
                        } else if let error = errorLoading {
                            Text("Error: \(error)").foregroundColor(.red)
                        } else {
                            let n = adjustedNutrients
                            let totalUnsat = n.fats - (n.saturatedFat ?? 0)

                            nutrientRow(label: "Calories", value: String(format: "%.0f cal", n.calories))
                            nutrientRow(label: "Carbs", value: String(format: "%.1f g", n.carbs))
                            nutrientRow(label: "Protein", value: String(format: "%.1f g", n.protein))
                            nutrientRow(label: "Fat", value: String(format: "%.1f g", n.fats))
                            
                            DisclosureGroup("Fat & Fiber Details") {
                                nutrientRow(label: "Saturated Fat", value: n.saturatedFat, unit: "g")
                                nutrientRow(label: "Unsaturated Fat", value: totalUnsat > 0 ? totalUnsat : nil, unit: "g")
                                nutrientRow(label: "Fiber", value: n.fiber, unit: "g")
                            }
                            
                            DisclosureGroup("Vitamins & Minerals") {
                                nutrientRow(label: "Calcium", value: n.calcium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Iron", value: n.iron, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Potassium", value: n.potassium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Sodium", value: n.sodium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin A", value: n.vitaminA, unit: "mcg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin C", value: n.vitaminC, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin D", value: n.vitaminD, unit: "mcg", specifier: "%.0f")
                            }
                        }
                    }
                    Section(header: Text("Adjust Serving")) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            TextField("Qty", text: $quantity)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        if !availableServings.isEmpty && (!isLoggedItem || availableServings.count > 1) {
                            Menu {
                                ForEach(availableServings) { option in
                                    Button(option.description) {
                                        selectedServingID = option.id
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Serving Unit")
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Text(selectedServingOption?.description ?? "Select...")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Button(buttonText()) {
                    logAdjustedFood()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(quantity.isEmpty || Double(quantity) == 0)
                .padding()
            }
            .blur(radius: isProcessingLabel ? 3 : 0)
            
            if isProcessingLabel {
                ImageProcessingView()
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(isLoggedItem ? "Edit Log" : "Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleSavedState) {
                    Image(systemName: isSavedAsCustom ? "star.fill" : "star")
                        .foregroundColor(isSavedAsCustom ? .yellow : .brandPrimary)
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .onAppear {
            setupInitialData()
            checkIfSaved()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera) { image in
                isProcessingLabel = true
                imageModel.parseNutritionLabel(from: image) { result in
                    isProcessingLabel = false
                    switch result {
                    case .success(let nutrition): handleScannedNutrition(nutrition)
                    case .failure(let error): scanError = (true, error.localizedDescription)
                    }
                }
            }
        }
        .alert("Scan Error", isPresented: $scanError.0) { Button("OK") {} } message: { Text(scanError.1) }
    }
    
    private var labelScannerButton: some View {
        Button { showingImagePicker = true } label: {
            Label("Scan Nutrition Label", systemImage: "camera.fill")
        }
        .tint(.brandPrimary)
        .padding(.top, 5)
    }
    
    // MARK: - Setup Initial Data
    private func setupInitialData() {
        // Logic to determine if we should fetch API details or use existing
        if source == "search_result" || source == "barcode_result" {
            fetchAPIServingDetails()
        } else {
            // Create a default "1 serving" option from the existing data
            let defaultOption = createFallbackServing(from: initialFoodItem)
            self.availableServings = [defaultOption]
            self.selectedServingID = defaultOption.id
        }
    }
    
    private func fetchAPIServingDetails() {
        guard !isLoadingDetails else { return }
        isLoadingDetails = true
        
        foodAPIService.fetchFoodDetails(foodId: initialFoodItem.id) { result in
            DispatchQueue.main.async {
                self.isLoadingDetails = false
                switch result {
                case .success(let (info, servings)):
                    self.foodName = info.name
                    self.availableServings = servings.isEmpty ? [self.createFallbackServing(from: info)] : servings
                    self.selectedServingID = self.availableServings.first?.id
                case .failure:
                    self.availableServings = [self.createFallbackServing(from: self.initialFoodItem)]
                    self.selectedServingID = self.availableServings.first?.id
                }
            }
        }
    }
    
    private func createFallbackServing(from item: FoodItem) -> ServingSizeOption {
        // Helper to wrap a FoodItem into a ServingSizeOption
        return ServingSizeOption(
            description: item.servingSize.isEmpty ? "1 serving" : item.servingSize,
            servingWeightGrams: item.servingWeight,
            calories: item.calories, protein: item.protein, carbs: item.carbs, fats: item.fats,
            saturatedFat: item.saturatedFat, polyunsaturatedFat: item.polyunsaturatedFat, monounsaturatedFat: item.monounsaturatedFat, fiber: item.fiber,
            calcium: item.calcium, iron: item.iron, potassium: item.potassium, sodium: item.sodium,
            vitaminA: item.vitaminA, vitaminC: item.vitaminC, vitaminD: item.vitaminD, vitaminB12: item.vitaminB12, folate: item.folate,
            magnesium: item.magnesium, phosphorus: item.phosphorus, zinc: item.zinc, copper: item.copper, manganese: item.manganese, selenium: item.selenium,
            vitaminB1: item.vitaminB1, vitaminB2: item.vitaminB2, vitaminB3: item.vitaminB3, vitaminB5: item.vitaminB5, vitaminB6: item.vitaminB6, vitaminE: item.vitaminE, vitaminK: item.vitaminK
        )
    }
    
    private func handleScannedNutrition(_ data: NutritionLabelData) {
        self.foodName = data.foodName
        let scanned = ServingSizeOption(description: "Scanned Label", servingWeightGrams: nil, calories: data.calories, protein: data.protein, carbs: data.carbs, fats: data.fats, saturatedFat: data.saturatedFat, polyunsaturatedFat: data.polyunsaturatedFat, monounsaturatedFat: data.monounsaturatedFat, fiber: data.fiber, calcium: data.calcium, iron: data.iron, potassium: data.potassium, sodium: data.sodium, vitaminA: data.vitaminA, vitaminC: data.vitaminC, vitaminD: data.vitaminD, vitaminB12: data.vitaminB12, folate: data.folate, magnesium: data.magnesium, phosphorus: data.phosphorus, zinc: data.zinc, copper: data.copper, manganese: data.manganese, selenium: data.selenium, vitaminB1: data.vitaminB1, vitaminB2: data.vitaminB2, vitaminB3: data.vitaminB3, vitaminB5: data.vitaminB5, vitaminB6: data.vitaminB6, vitaminE: data.vitaminE, vitaminK: data.vitaminK)
        self.availableServings.insert(scanned, at: 0)
        self.selectedServingID = scanned.id
    }

    private func logAdjustedFood() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let n = adjustedNutrients
        
        let itemToLog = FoodItem(
            id: isLoggedItem ? initialFoodItem.id : UUID().uuidString,
            name: foodName, calories: n.calories, protein: n.protein, carbs: n.carbs, fats: n.fats,
            saturatedFat: n.saturatedFat, polyunsaturatedFat: n.polyunsaturatedFat, monounsaturatedFat: n.monounsaturatedFat, fiber: n.fiber,
            servingSize: n.servingDescription, servingWeight: n.servingWeightGrams, timestamp: Date(),
            calcium: n.calcium, iron: n.iron, potassium: n.potassium, sodium: n.sodium,
            vitaminA: n.vitaminA, vitaminC: n.vitaminC, vitaminD: n.vitaminD, vitaminB12: n.vitaminB12, folate: n.folate,
            magnesium: n.magnesium, phosphorus: n.phosphorus, zinc: n.zinc, copper: n.copper, manganese: n.manganese, selenium: n.selenium,
            vitaminB1: n.vitaminB1, vitaminB2: n.vitaminB2, vitaminB3: n.vitaminB3, vitaminB5: n.vitaminB5, vitaminB6: n.vitaminB6, vitaminE: n.vitaminE, vitaminK: n.vitaminK,
            // SAVE NEW FIELDS
            quantityValue: n.quantityValue,
            servingUnit: n.servingUnit
        )
        
        if let updateHandler = onUpdate {
            updateHandler(itemToLog)
        } else if isLoggedItem {
            dailyLogService.updateFoodInCurrentLog(for: userID, updatedFoodItem: itemToLog)
        } else {
            dailyLogService.addFoodToCurrentLog(for: userID, foodItem: itemToLog, source: source)
        }
        onLogUpdated()
        dismiss()
    }
    
    // Save/Unsave Custom Food Logic
    private func toggleSavedState() {
        if isSavedAsCustom { unsaveCustomFood() } else { saveAsCustomFood() }
    }
    private func saveAsCustomFood() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.saveCustomFood(for: userID, foodItem: initialFoodItem) { success in
            if success { isSavedAsCustom = true; bannerService.showBanner(title: "Saved", message: "Saved to My Foods") }
        }
    }
    private func unsaveCustomFood() {
        guard let userID = Auth.auth().currentUser?.uid, let id = customFoodForAction?.id else { return }
        dailyLogService.deleteCustomFood(for: userID, foodItemID: id) { success in
            if success { isSavedAsCustom = false; bannerService.showBanner(title: "Removed", message: "Removed from My Foods") }
        }
    }
    private func checkIfSaved() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchMyFoodItems(for: userID) { result in
            if case .success(let items) = result, let match = items.first(where: { $0.name == foodName }) {
                isSavedAsCustom = true; customFoodForAction = match
            }
        }
    }

    private func buttonText() -> String { onUpdate != nil ? "Update Item" : (isLoggedItem ? "Update Logged Item" : "Add to Log") }
    private func navigationTitleText() -> String { onUpdate != nil ? "Edit Item" : (isLoggedItem ? "Edit Logged Item" : "Log Food") }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    
    @ViewBuilder private func nutrientRow(label: String, value: Double?, unit: String, specifier: String = "%.1f") -> some View {
        if let v = value, v > 0 { HStack { Text(label).appFont(size: 15); Spacer(); Text("\(v, specifier: specifier) \(unit)").appFont(size: 15).foregroundColor(.secondary) } }
    }
    @ViewBuilder private func nutrientRow(label: String, value: String) -> some View {
        HStack { Text(label).appFont(size: 15); Spacer(); Text(value).appFont(size: 15).foregroundColor(.secondary) }
    }
}
