import SwiftUI
import FirebaseAuth

struct FoodDetailView: View {
    var initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    var date: Date
    var source: String
    var onLogUpdated: () -> Void
    var onUpdate: ((FoodItem) -> Void)?

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

    private var selectedServingOption: ServingSizeOption? {
        guard let selectedID = selectedServingID else { return nil }
        return availableServings.first { $0.id == selectedID }
    }

    private var adjustedNutrients: (
        calories: Double, protein: Double, carbs: Double, fats: Double,
        saturatedFat: Double?, polyunsaturatedFat: Double?, monounsaturatedFat: Double?,
        fiber: Double?, calcium: Double?, iron: Double?, potassium: Double?, sodium: Double?,
        vitaminA: Double?, vitaminC: Double?, vitaminD: Double?, vitaminB12: Double?, folate: Double?,
        magnesium: Double?, phosphorus: Double?, zinc: Double?, copper: Double?, manganese: Double?, selenium: Double?,
        vitaminB1: Double?, vitaminB2: Double?, vitaminB3: Double?, vitaminB5: Double?, vitaminB6: Double?, vitaminE: Double?, vitaminK: Double?,
        servingDescription: String, servingWeightGrams: Double
    ) {
        guard let quantityValue = Double(quantity), quantityValue > 0, let currentSelectedServing = selectedServingOption else {
            let parsedInitialServing = parseQuantityFromServing(initialFoodItem.servingSize)
            let initialQtyFactor = parsedInitialServing.qty > 0 ? parsedInitialServing.qty : 1.0
            let baseDesc = parsedInitialServing.baseDesc

            return (
                calories: initialFoodItem.calories / initialQtyFactor,
                protein: initialFoodItem.protein / initialQtyFactor,
                carbs: initialFoodItem.carbs / initialQtyFactor,
                fats: initialFoodItem.fats / initialQtyFactor,
                saturatedFat: initialFoodItem.saturatedFat.map { $0 / initialQtyFactor },
                polyunsaturatedFat: initialFoodItem.polyunsaturatedFat.map { $0 / initialQtyFactor },
                monounsaturatedFat: initialFoodItem.monounsaturatedFat.map { $0 / initialQtyFactor },
                fiber: initialFoodItem.fiber.map { $0 / initialQtyFactor },
                calcium: initialFoodItem.calcium.map { $0 / initialQtyFactor },
                iron: initialFoodItem.iron.map { $0 / initialQtyFactor },
                potassium: initialFoodItem.potassium.map { $0 / initialQtyFactor },
                sodium: initialFoodItem.sodium.map { $0 / initialQtyFactor },
                vitaminA: initialFoodItem.vitaminA.map { $0 / initialQtyFactor },
                vitaminC: initialFoodItem.vitaminC.map { $0 / initialQtyFactor },
                vitaminD: initialFoodItem.vitaminD.map { $0 / initialQtyFactor },
                vitaminB12: initialFoodItem.vitaminB12.map { $0 / initialQtyFactor },
                folate: initialFoodItem.folate.map { $0 / initialQtyFactor },
                magnesium: initialFoodItem.magnesium.map { $0 / initialQtyFactor },
                phosphorus: initialFoodItem.phosphorus.map { $0 / initialQtyFactor },
                zinc: initialFoodItem.zinc.map { $0 / initialQtyFactor },
                copper: initialFoodItem.copper.map { $0 / initialQtyFactor },
                manganese: initialFoodItem.manganese.map { $0 / initialQtyFactor },
                selenium: initialFoodItem.selenium.map { $0 / initialQtyFactor },
                vitaminB1: initialFoodItem.vitaminB1.map { $0 / initialQtyFactor },
                vitaminB2: initialFoodItem.vitaminB2.map { $0 / initialQtyFactor },
                vitaminB3: initialFoodItem.vitaminB3.map { $0 / initialQtyFactor },
                vitaminB5: initialFoodItem.vitaminB5.map { $0 / initialQtyFactor },
                vitaminB6: initialFoodItem.vitaminB6.map { $0 / initialQtyFactor },
                vitaminE: initialFoodItem.vitaminE.map { $0 / initialQtyFactor },
                vitaminK: initialFoodItem.vitaminK.map { $0 / initialQtyFactor },
                servingDescription: baseDesc,
                servingWeightGrams: initialFoodItem.servingWeight / initialQtyFactor
            )
        }

        let factor = quantityValue
        let finalDescription: String
        if quantityValue == 1 {
            finalDescription = currentSelectedServing.description
        } else {
            finalDescription = "\(String(format: "%g", quantityValue)) x \(currentSelectedServing.description)"
        }
        
        let finalWeight = (currentSelectedServing.servingWeightGrams ?? 0) * factor
        return (
            calories: currentSelectedServing.calories * factor,
            protein: currentSelectedServing.protein * factor,
            carbs: currentSelectedServing.carbs * factor,
            fats: currentSelectedServing.fats * factor,
            saturatedFat: currentSelectedServing.saturatedFat.map { $0 * factor },
            polyunsaturatedFat: currentSelectedServing.polyunsaturatedFat.map { $0 * factor },
            monounsaturatedFat: currentSelectedServing.monounsaturatedFat.map { $0 * factor },
            fiber: currentSelectedServing.fiber.map { $0 * factor },
            calcium: currentSelectedServing.calcium.map { $0 * factor },
            iron: currentSelectedServing.iron.map { $0 * factor },
            potassium: currentSelectedServing.potassium.map { $0 * factor },
            sodium: currentSelectedServing.sodium.map { $0 * factor },
            vitaminA: currentSelectedServing.vitaminA.map { $0 * factor },
            vitaminC: currentSelectedServing.vitaminC.map { $0 * factor },
            vitaminD: currentSelectedServing.vitaminD.map { $0 * factor },
            vitaminB12: currentSelectedServing.vitaminB12.map { $0 * factor },
            folate: currentSelectedServing.folate.map { $0 * factor },
            magnesium: currentSelectedServing.magnesium.map { $0 * factor },
            phosphorus: currentSelectedServing.phosphorus.map { $0 * factor },
            zinc: currentSelectedServing.zinc.map { $0 * factor },
            copper: currentSelectedServing.copper.map { $0 * factor },
            manganese: currentSelectedServing.manganese.map { $0 * factor },
            selenium: currentSelectedServing.selenium.map { $0 * factor },
            vitaminB1: currentSelectedServing.vitaminB1.map { $0 * factor },
            vitaminB2: currentSelectedServing.vitaminB2.map { $0 * factor },
            vitaminB3: currentSelectedServing.vitaminB3.map { $0 * factor },
            vitaminB5: currentSelectedServing.vitaminB5.map { $0 * factor },
            vitaminB6: currentSelectedServing.vitaminB6.map { $0 * factor },
            vitaminE: currentSelectedServing.vitaminE.map { $0 * factor },
            vitaminK: currentSelectedServing.vitaminK.map { $0 * factor },
            servingDescription: finalDescription,
            servingWeightGrams: finalWeight
        )
    }

    init(initialFoodItem: FoodItem, dailyLog: Binding<DailyLog?>, date: Date = Date(), source: String = "log", onLogUpdated: @escaping () -> Void, onUpdate: ((FoodItem) -> Void)? = nil) {
        self.initialFoodItem = initialFoodItem
        self._dailyLog = dailyLog
        self.date = date
        self.source = source
        self.onLogUpdated = onLogUpdated
        self.onUpdate = onUpdate
        
        let isEditingLoggedItem = source.starts(with: "log_")
        self._isLoggedItem = State(initialValue: isEditingLoggedItem)
        self._foodName = State(initialValue: initialFoodItem.name)

        var initialQuantityString = "1"
        if isEditingLoggedItem || source == "image_result_edit" {
            let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
            initialQuantityString = String(format: "%g", parsed.qty > 0 ? parsed.qty : 1.0)
        }
        self._quantity = State(initialValue: initialQuantityString)
    }

    private func parseQuantityFromServing(_ servingDesc: String) -> (qty: Double, baseDesc: String) {
        let components = servingDesc.components(separatedBy: " x ")
        if components.count == 2, let qty = Double(components[0]), qty > 0 {
            return (qty, components[1])
        }
        return (1.0, servingDesc)
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
                    Section(header: Text("Nutritional Information (Adjusted for Quantity)"), footer: labelScannerButton) {
                        if isLoadingDetails && !isLoggedItem && source != "recent_tap" && source != "search_result_no_detail_fetch" { ProgressView() }
                        else if let error = errorLoading { Text("Error loading details: \(error)").foregroundColor(.red) }
                        else {
                            let nutrients = adjustedNutrients
                            let totalUnsaturatedFat = nutrients.fats - (nutrients.saturatedFat ?? 0)

                            nutrientRow(label: "Calories", value: String(format: "%.0f cal", nutrients.calories))
                            nutrientRow(label: "Carbs", value: String(format: "%.1f g", nutrients.carbs))
                            nutrientRow(label: "Protein", value: String(format: "%.1f g", nutrients.protein))
                            nutrientRow(label: "Total Fat", value: String(format: "%.1f g", nutrients.fats))
                            
                            DisclosureGroup("Fat & Fiber Details") {
                                nutrientRow(label: "Saturated Fat", value: nutrients.saturatedFat, unit: "g")
                                nutrientRow(label: "Polyunsaturated Fat", value: nutrients.polyunsaturatedFat, unit: "g")
                                nutrientRow(label: "Monounsaturated Fat", value: nutrients.monounsaturatedFat, unit: "g")
                                nutrientRow(label: "Unsaturated Fat", value: totalUnsaturatedFat > 0 ? totalUnsaturatedFat : nil, unit: "g")
                                nutrientRow(label: "Dietary Fiber", value: nutrients.fiber, unit: "g")
                            }
                            
                            DisclosureGroup("Vitamins & Minerals") {
                                nutrientRow(label: "Calcium", value: nutrients.calcium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Iron", value: nutrients.iron, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Potassium", value: nutrients.potassium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Sodium", value: nutrients.sodium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin A", value: nutrients.vitaminA, unit: "mcg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin C", value: nutrients.vitaminC, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin D", value: nutrients.vitaminD, unit: "mcg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin B12", value: nutrients.vitaminB12, unit: "mcg", specifier: "%.1f")
                                nutrientRow(label: "Folate", value: nutrients.folate, unit: "mcg", specifier: "%.0f")
                                nutrientRow(label: "Magnesium", value: nutrients.magnesium, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Phosphorus", value: nutrients.phosphorus, unit: "mg", specifier: "%.0f")
                                nutrientRow(label: "Zinc", value: nutrients.zinc, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Copper", value: nutrients.copper, unit: "mcg", specifier: "%.0f")
                                nutrientRow(label: "Manganese", value: nutrients.manganese, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Selenium", value: nutrients.selenium, unit: "mcg", specifier: "%.0f")
                                nutrientRow(label: "Vitamin B1", value: nutrients.vitaminB1, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Vitamin B2", value: nutrients.vitaminB2, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Vitamin B3", value: nutrients.vitaminB3, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Vitamin B5", value: nutrients.vitaminB5, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Vitamin B6", value: nutrients.vitaminB6, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Vitamin E", value: nutrients.vitaminE, unit: "mg", specifier: "%.1f")
                                nutrientRow(label: "Vitamin K", value: nutrients.vitaminK, unit: "mcg", specifier: "%.0f")
                            }
                        }
                    }
                    Section(header: Text("Adjust Serving")) {
                        HStack {
                            Text(isLoggedItem ? "Number of Logged Servings" : "Number of Servings")
                            Spacer()
                            TextField("Quantity", text: $quantity).keyboardType(.decimalPad).textFieldStyle(RoundedBorderTextFieldStyle()).frame(width: 80).multilineTextAlignment(.trailing)
                        }
                        if !isLoggedItem || source == "recent_tap" || source == "image_result_edit" || (availableServings.count > 1 && source != "log_swipe_direct_edit_no_picker") {
                            if !availableServings.isEmpty {
                                Menu {
                                    ForEach(availableServings) { option in
                                        Button(option.description) {
                                            selectedServingID = option.id
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("Serving Size")
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        Text(selectedServingOption?.description ?? "Select...")
                                            .foregroundColor(Color(UIColor.secondaryLabel))
                                    }
                                }
                            } else if !isLoadingDetails { Text("No other serving sizes available.").appFont(size: 12).foregroundColor(Color(UIColor.secondaryLabel)) }
                        } else if let baseNutrients = baseLoggedItemNutrientsPerUnit {
                            Text("Base Serving: \(baseNutrients.description)")
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }
                    }
                }
                Button(buttonText()) {
                    handleButtonAction()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!logButtonEnabled)
                .padding()
            }.blur(radius: isProcessingLabel ? 3 : 0)
            
            if isProcessingLabel {
                ImageProcessingView()
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(navigationTitleText()).navigationBarTitleDisplayMode(.inline)
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
                self.isProcessingLabel = true
                imageModel.parseNutritionLabel(from: image) { result in
                    self.isProcessingLabel = false
                    switch result {
                    case .success(let nutrition):
                        self.handleScannedNutrition(nutrition)
                    case .failure(let error):
                        self.scanError = (true, "Could not read the nutrition label. Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        .alert("Scan Error", isPresented: $scanError.0) {
            Button("OK") { }
        } message: {
            Text(scanError.1)
        }
    }

    private var labelScannerButton: some View {
        Button {
            showingImagePicker = true
        } label: {
            Label("Not correct? Take a photo of the nutrition label.", systemImage: "camera.fill")
        }
        .tint(.green)
        .padding(.top, 5)
    }

    private func handleScannedNutrition(_ data: NutritionLabelData) {
        self.foodName = data.foodName
        let scannedServing = ServingSizeOption(
            description: "Scanned from Label",
            servingWeightGrams: nil,
            calories: data.calories,
            protein: data.protein,
            carbs: data.carbs,
            fats: data.fats,
            saturatedFat: data.saturatedFat,
            polyunsaturatedFat: data.polyunsaturatedFat,
            monounsaturatedFat: data.monounsaturatedFat,
            fiber: data.fiber,
            calcium: data.calcium,
            iron: data.iron,
            potassium: data.potassium,
            sodium: data.sodium,
            vitaminA: data.vitaminA,
            vitaminC: data.vitaminC,
            vitaminD: data.vitaminD,
            vitaminB12: data.vitaminB12,
            folate: data.folate,
            magnesium: data.magnesium,
            phosphorus: data.phosphorus,
            zinc: data.zinc,
            copper: data.copper,
            manganese: data.manganese,
            selenium: data.selenium,
            vitaminB1: data.vitaminB1,
            vitaminB2: data.vitaminB2,
            vitaminB3: data.vitaminB3,
            vitaminB5: data.vitaminB5,
            vitaminB6: data.vitaminB6,
            vitaminE: data.vitaminE,
            vitaminK: data.vitaminK
        )
        self.availableServings.insert(scannedServing, at: 0)
        self.selectedServingID = scannedServing.id
        self.quantity = "1"
    }

    private func buttonText() -> String {
        if onUpdate != nil {
            return "Update Item"
        }
        return isLoggedItem ? "Update Logged Item" : "Add to Log"
    }

    private func navigationTitleText() -> String {
        if onUpdate != nil {
            return "Edit Item"
        }
        return isLoggedItem ? "Edit Logged Item" : "Log Food"
    }

    private func handleButtonAction() {
        if let onUpdate = onUpdate {
            updateItem(onUpdate: onUpdate)
        } else {
            logAdjustedFood()
        }
    }
    
    private func updateItem(onUpdate: (FoodItem) -> Void) {
        guard let quantityValue = Double(quantity), quantityValue > 0 else { return }
        
        let finalNutrients = adjustedNutrients
        let updatedFoodItem = FoodItem(
            id: initialFoodItem.id,
            name: foodName, calories: finalNutrients.calories,
            protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber,
            servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: initialFoodItem.timestamp ?? Date(),
            calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium,
            vitaminA: finalNutrients.vitaminA, vitaminC: finalNutrients.vitaminC,
            vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        onUpdate(updatedFoodItem)
        dismiss()
    }

    private var logButtonEnabled: Bool {
        let quantityValue = Double(quantity) ?? 0
        return quantityValue > 0 && selectedServingOption != nil
    }

    private func toggleSavedState() {
        if isSavedAsCustom {
            unsaveCustomFood()
        } else {
            saveAsCustomFood()
        }
    }

    private func saveAsCustomFood() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let finalNutrients = adjustedNutrients
        
        let itemToSave = FoodItem(
            id: UUID().uuidString,
            name: foodName,
            calories: finalNutrients.calories, protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber, servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: nil, calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium, vitaminA: finalNutrients.vitaminA,
            vitaminC: finalNutrients.vitaminC, vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        
        dailyLogService.saveCustomFood(for: userID, foodItem: itemToSave) { success in
            Task { @MainActor in
                if success {
                    self.isSavedAsCustom = true
                    self.customFoodForAction = itemToSave
                    bannerService.showBanner(title: "Saved", message: "\(foodName) added to My Foods.")
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not save custom food.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }
    
    private func unsaveCustomFood() {
        guard let userID = Auth.auth().currentUser?.uid, let foodID = customFoodForAction?.id else { return }
        dailyLogService.deleteCustomFood(for: userID, foodItemID: foodID) { success in
            Task { @MainActor in
                if success {
                    self.isSavedAsCustom = false
                    self.customFoodForAction = nil
                    bannerService.showBanner(title: "Removed", message: "\(foodName) removed from My Foods.", iconName: "star.slash.fill")
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not remove custom food.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }
    
    private func checkIfSaved() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchMyFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                if case .success(let items) = result,
                   let savedItem = items.first(where: { $0.name == self.foodName }) {
                    self.isSavedAsCustom = true
                    self.customFoodForAction = savedItem
                }
            }
        }
    }
    
    private func setupInitialData() {
        dailyLogService.activelyViewedDate = self.date

        if source.starts(with: "log_") || source.starts(with: "image_result_edit") {
            let parsedInfo = parseQuantityFromServing(initialFoodItem.servingSize)
            let qtyFactor = parsedInfo.qty > 0 ? parsedInfo.qty : 1.0
            
            let singleUnitNutrients = ServingSizeOption(
                description: parsedInfo.baseDesc,
                servingWeightGrams: initialFoodItem.servingWeight / qtyFactor,
                calories: initialFoodItem.calories / qtyFactor,
                protein: initialFoodItem.protein / qtyFactor,
                carbs: initialFoodItem.carbs / qtyFactor,
                fats: initialFoodItem.fats / qtyFactor,
                saturatedFat: initialFoodItem.saturatedFat.map { $0 / qtyFactor },
                polyunsaturatedFat: initialFoodItem.polyunsaturatedFat.map { $0 / qtyFactor },
                monounsaturatedFat: initialFoodItem.monounsaturatedFat.map { $0 / qtyFactor },
                fiber: initialFoodItem.fiber.map { $0 / qtyFactor },
                calcium: initialFoodItem.calcium.map { $0 / qtyFactor },
                iron: initialFoodItem.iron.map { $0 / qtyFactor },
                potassium: initialFoodItem.potassium.map { $0 / qtyFactor },
                sodium: initialFoodItem.sodium.map { $0 / qtyFactor },
                vitaminA: initialFoodItem.vitaminA.map { $0 / qtyFactor },
                vitaminC: initialFoodItem.vitaminC.map { $0 / qtyFactor },
                vitaminD: initialFoodItem.vitaminD.map { $0 / qtyFactor },
                vitaminB12: initialFoodItem.vitaminB12.map { $0 / qtyFactor },
                folate: initialFoodItem.folate.map { $0 / qtyFactor },
                magnesium: initialFoodItem.magnesium.map { $0 / qtyFactor },
                phosphorus: initialFoodItem.phosphorus.map { $0 / qtyFactor },
                zinc: initialFoodItem.zinc.map { $0 / qtyFactor },
                copper: initialFoodItem.copper.map { $0 / qtyFactor },
                manganese: initialFoodItem.manganese.map { $0 / qtyFactor },
                selenium: initialFoodItem.selenium.map { $0 / qtyFactor },
                vitaminB1: initialFoodItem.vitaminB1.map { $0 / qtyFactor },
                vitaminB2: initialFoodItem.vitaminB2.map { $0 / qtyFactor },
                vitaminB3: initialFoodItem.vitaminB3.map { $0 / qtyFactor },
                vitaminB5: initialFoodItem.vitaminB5.map { $0 / qtyFactor },
                vitaminB6: initialFoodItem.vitaminB6.map { $0 / qtyFactor },
                vitaminE: initialFoodItem.vitaminE.map { $0 / qtyFactor },
                vitaminK: initialFoodItem.vitaminK.map { $0 / qtyFactor }
            )
            self.availableServings = [singleUnitNutrients]
            self.selectedServingID = singleUnitNutrients.id
            self.baseLoggedItemNutrientsPerUnit = singleUnitNutrients
            self.isLoadingDetails = false
            
        } else if source == "recent_tap" {
            let parsedInfo = parseQuantityFromServing(initialFoodItem.servingSize)
            let loggedQty = parsedInfo.qty > 0 ? parsedInfo.qty : 1.0
            
            let singleUnitNutrients = ServingSizeOption(
                description: parsedInfo.baseDesc,
                servingWeightGrams: initialFoodItem.servingWeight / loggedQty,
                calories: initialFoodItem.calories / loggedQty,
                protein: initialFoodItem.protein / loggedQty,
                carbs: initialFoodItem.carbs / loggedQty,
                fats: initialFoodItem.fats / loggedQty,
                saturatedFat: initialFoodItem.saturatedFat.map { $0 / loggedQty },
                polyunsaturatedFat: initialFoodItem.polyunsaturatedFat.map { $0 / loggedQty },
                monounsaturatedFat: initialFoodItem.monounsaturatedFat.map { $0 / loggedQty },
                fiber: initialFoodItem.fiber.map { $0 / loggedQty },
                calcium: initialFoodItem.calcium.map { $0 / loggedQty },
                iron: initialFoodItem.iron.map { $0 / loggedQty },
                potassium: initialFoodItem.potassium.map { $0 / loggedQty },
                sodium: initialFoodItem.sodium.map { $0 / loggedQty },
                vitaminA: initialFoodItem.vitaminA.map { $0 / loggedQty },
                vitaminC: initialFoodItem.vitaminC.map { $0 / loggedQty },
                vitaminD: initialFoodItem.vitaminD.map { $0 / loggedQty },
                vitaminB12: initialFoodItem.vitaminB12.map { $0 / loggedQty },
                folate: initialFoodItem.folate.map { $0 / loggedQty },
                magnesium: initialFoodItem.magnesium.map { $0 / loggedQty },
                phosphorus: initialFoodItem.phosphorus.map { $0 / loggedQty },
                zinc: initialFoodItem.zinc.map { $0 / loggedQty },
                copper: initialFoodItem.copper.map { $0 / loggedQty },
                manganese: initialFoodItem.manganese.map { $0 / loggedQty },
                selenium: initialFoodItem.selenium.map { $0 / loggedQty },
                vitaminB1: initialFoodItem.vitaminB1.map { $0 / loggedQty },
                vitaminB2: initialFoodItem.vitaminB2.map { $0 / loggedQty },
                vitaminB3: initialFoodItem.vitaminB3.map { $0 / loggedQty },
                vitaminB5: initialFoodItem.vitaminB5.map { $0 / loggedQty },
                vitaminB6: initialFoodItem.vitaminB6.map { $0 / loggedQty },
                vitaminE: initialFoodItem.vitaminE.map { $0 / loggedQty },
                vitaminK: initialFoodItem.vitaminK.map { $0 / loggedQty }
            )
            self.availableServings = [singleUnitNutrients]
            self.selectedServingID = singleUnitNutrients.id
            self.isLoadingDetails = false

        } else if source == "search_result" || source == "barcode_result" || source == "image_result" {
            fetchAPIServingDetails()
        } else {
            let baseServingOption = ServingSizeOption(
                description: initialFoodItem.servingSize.isEmpty ? "1 serving" : initialFoodItem.servingSize,
                servingWeightGrams: initialFoodItem.servingWeight,
                calories: initialFoodItem.calories,
                protein: initialFoodItem.protein,
                carbs: initialFoodItem.carbs,
                fats: initialFoodItem.fats,
                saturatedFat: initialFoodItem.saturatedFat,
                polyunsaturatedFat: initialFoodItem.polyunsaturatedFat,
                monounsaturatedFat: initialFoodItem.monounsaturatedFat,
                fiber: initialFoodItem.fiber,
                calcium: initialFoodItem.calcium,
                iron: initialFoodItem.iron,
                potassium: initialFoodItem.potassium,
                sodium: initialFoodItem.sodium,
                vitaminA: initialFoodItem.vitaminA,
                vitaminC: initialFoodItem.vitaminC,
                vitaminD: initialFoodItem.vitaminD,
                vitaminB12: initialFoodItem.vitaminB12,
                folate: initialFoodItem.folate,
                magnesium: initialFoodItem.magnesium,
                phosphorus: initialFoodItem.phosphorus,
                zinc: initialFoodItem.zinc,
                copper: initialFoodItem.copper,
                manganese: initialFoodItem.manganese,
                selenium: initialFoodItem.selenium,
                vitaminB1: initialFoodItem.vitaminB1,
                vitaminB2: initialFoodItem.vitaminB2,
                vitaminB3: initialFoodItem.vitaminB3,
                vitaminB5: initialFoodItem.vitaminB5,
                vitaminB6: initialFoodItem.vitaminB6,
                vitaminE: initialFoodItem.vitaminE,
                vitaminK: initialFoodItem.vitaminK
            )
            self.availableServings = [baseServingOption]
            self.selectedServingID = baseServingOption.id
            self.isLoadingDetails = false
        }
    }
    
    private func fetchAPIServingDetails() {
        guard !isLoadingDetails else { return }
        let likelyApiId = initialFoodItem.id.count < 20 && !initialFoodItem.id.contains("-")
        
        if likelyApiId && availableServings.isEmpty {
            isLoadingDetails = true; errorLoading = nil
            foodAPIService.fetchFoodDetails(foodId: initialFoodItem.id) { result in
                DispatchQueue.main.async {
                    self.isLoadingDetails = false
                    switch result {
                    case .success(let (foodInfo, servings)):
                        self.foodName = foodInfo.name
                        self.availableServings = servings.isEmpty ? [self.createFallbackServing(from: foodInfo)] : servings
                        if let matchingServing = self.availableServings.first(where: { $0.description == self.initialFoodItem.servingSize && $0.servingWeightGrams == self.initialFoodItem.servingWeight }) {
                            self.selectedServingID = matchingServing.id
                        } else if let firstServing = self.availableServings.first {
                            self.selectedServingID = firstServing.id
                        } else {
                            self.selectedServingID = nil
                            self.errorLoading = "No servings found for item."
                        }
                    case .failure(let error):
                        errorLoading = error.localizedDescription;
                        self.availableServings = [self.createFallbackServing(from: self.initialFoodItem)]
                        self.selectedServingID = self.availableServings.first?.id
                    }
                }
            }
        } else if availableServings.isEmpty {
            self.availableServings = [self.createFallbackServing(from: self.initialFoodItem)]
            self.selectedServingID = self.availableServings.first?.id
            self.isLoadingDetails = false
        }
    }
    
    private func createFallbackServing(from foodItem: FoodItem) -> ServingSizeOption {
        let parsed = parseQuantityFromServing(foodItem.servingSize)
        let qtyFactor = parsed.qty > 0 ? parsed.qty : 1.0
        return ServingSizeOption(
            description: parsed.baseDesc.isEmpty ? "1 serving" : parsed.baseDesc,
            servingWeightGrams: foodItem.servingWeight / qtyFactor,
            calories: foodItem.calories / qtyFactor,
            protein: foodItem.protein / qtyFactor,
            carbs: foodItem.carbs / qtyFactor,
            fats: foodItem.fats / qtyFactor,
            saturatedFat: foodItem.saturatedFat.map { $0 / qtyFactor },
            polyunsaturatedFat: initialFoodItem.polyunsaturatedFat.map { $0 / qtyFactor },
            monounsaturatedFat: initialFoodItem.monounsaturatedFat.map { $0 / qtyFactor },
            fiber: initialFoodItem.fiber.map { $0 / qtyFactor },
            calcium: initialFoodItem.calcium.map { $0 / qtyFactor },
            iron: initialFoodItem.iron.map { $0 / qtyFactor },
            potassium: initialFoodItem.potassium.map { $0 / qtyFactor },
            sodium: initialFoodItem.sodium.map { $0 / qtyFactor },
            vitaminA: initialFoodItem.vitaminA.map { $0 / qtyFactor },
            vitaminC: initialFoodItem.vitaminC.map { $0 / qtyFactor },
            vitaminD: initialFoodItem.vitaminD.map { $0 / qtyFactor },
            vitaminB12: initialFoodItem.vitaminB12.map { $0 / qtyFactor },
            folate: initialFoodItem.folate.map { $0 / qtyFactor },
            magnesium: initialFoodItem.magnesium.map { $0 / qtyFactor },
            phosphorus: initialFoodItem.phosphorus.map { $0 / qtyFactor },
            zinc: initialFoodItem.zinc.map { $0 / qtyFactor },
            copper: initialFoodItem.copper.map { $0 / qtyFactor },
            manganese: initialFoodItem.manganese.map { $0 / qtyFactor },
            selenium: initialFoodItem.selenium.map { $0 / qtyFactor },
            vitaminB1: initialFoodItem.vitaminB1.map { $0 / qtyFactor },
            vitaminB2: initialFoodItem.vitaminB2.map { $0 / qtyFactor },
            vitaminB3: initialFoodItem.vitaminB3.map { $0 / qtyFactor },
            vitaminB5: initialFoodItem.vitaminB5.map { $0 / qtyFactor },
            vitaminB6: initialFoodItem.vitaminB6.map { $0 / qtyFactor },
            vitaminE: initialFoodItem.vitaminE.map { $0 / qtyFactor },
            vitaminK: initialFoodItem.vitaminK.map { $0 / qtyFactor }
        )
    }

    private func logAdjustedFood() {
        guard let userID = Auth.auth().currentUser?.uid, logButtonEnabled, let currentSelectedServing = selectedServingOption else { return }
        guard let quantityValue = Double(quantity), quantityValue > 0 else { return }

        dailyLogService.activelyViewedDate = self.date
        let finalNutrients = adjustedNutrients
        
        var itemSourceToLog = "unknown_detail_view"
        if !isLoggedItem {
            switch self.source {
            case "barcode_result": itemSourceToLog = "barcode_scan"
            case "search_result": itemSourceToLog = "api"
            case "image_result": itemSourceToLog = "image_scan"
            case "recent_tap":
                let parsedInfo = parseQuantityFromServing(initialFoodItem.servingSize)
                if initialFoodItem.id.count < 20 && !initialFoodItem.id.contains("-") && !parsedInfo.baseDesc.lowercased().contains("recipe") && !parsedInfo.baseDesc.lowercased().contains("ai est.") {
                    itemSourceToLog = "api_recent"
                } else if parsedInfo.baseDesc.lowercased().contains("recipe") {
                    itemSourceToLog = "recipe_recent"
                } else if parsedInfo.baseDesc.lowercased().contains("ai est.") || initialFoodItem.name.lowercased().contains("ai logged") {
                    itemSourceToLog = "ai_recent"
                } else {
                    itemSourceToLog = "manual_recent"
                }
            default: itemSourceToLog = self.source
            }
        }
        
        let loggedFoodItem = FoodItem(
            id: isLoggedItem ? initialFoodItem.id : UUID().uuidString,
            name: foodName, calories: finalNutrients.calories,
            protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber,
            servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: isLoggedItem ? initialFoodItem.timestamp : Date(),
            calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium,
            vitaminA: finalNutrients.vitaminA, vitaminC: finalNutrients.vitaminC,
            vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        
        if isLoggedItem {
            dailyLogService.updateFoodInCurrentLog(for: userID, updatedFoodItem: loggedFoodItem)
        } else {
            dailyLogService.addFoodToCurrentLog(for: userID, foodItem: loggedFoodItem, source: itemSourceToLog)
        }
        
        onLogUpdated(); dismiss()
    }

    @ViewBuilder private func nutrientRow(label: String, value: Double?, unit: String, specifier: String = "%.1f") -> some View {
        if let unwrappedValue = value, unwrappedValue > 0.001 || (specifier == "%.0f" && unwrappedValue >= 0.5) {
            HStack { Text(label).appFont(size: 15); Spacer(); Text("\(unwrappedValue, specifier: specifier) \(unit)").appFont(size: 15).foregroundColor(Color(UIColor.secondaryLabel)) }
        } else {
            EmptyView()
        }
    }
    @ViewBuilder private func nutrientRow(label: String, value: String) -> some View {
        HStack { Text(label).appFont(size: 15); Spacer(); Text(value).appFont(size: 15).foregroundColor(Color(UIColor.secondaryLabel)) }
    }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}
