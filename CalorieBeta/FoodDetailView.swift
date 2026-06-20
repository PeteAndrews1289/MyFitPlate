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

    // MARK: - Robust Initializer
    // Updated to use new model fields if available, ensuring stability.
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

        // 1. IMPROVEMENT: Check for explicit quantity first.
        // This prevents errors if string formatting changes in the future.
        if let explicitQty = initialFoodItem.quantityValue {
            self._quantity = State(initialValue: String(format: "%g", explicitQty))
        } else {
            // Fallback for older data or items without explicit quantity
            if isEditingLoggedItem || source == "image_result_edit" {
                let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
                let qty = parsed.qty > 0 ? parsed.qty : 1.0
                self._quantity = State(initialValue: String(format: "%g", qty))
            } else {
                self._quantity = State(initialValue: "1")
            }
        }
    }

    // Helper to parse old string format (Backward Compatibility)
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

    private var isShowingDetailsLoading: Bool {
        isLoadingDetails && !isLoggedItem && source != "recent_tap" && source != "search_result_no_detail_fetch"
    }

    private var canChangeServing: Bool {
        !isLoggedItem || source == "recent_tap" || source == "image_result_edit" || (availableServings.count > 1 && source != "log_swipe_direct_edit_no_picker")
    }

    // MARK: - Adjusted Nutrients Calculation
    // Now returns structured data (quantityValue, servingUnit) alongside the strings.
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
            // Safe fallback if input is invalid
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

        // Determine the unit name safely
        let unitName: String
        let baseNutrients: ServingSizeOption
        
        if let selected = selectedServingOption {
            baseNutrients = selected
            unitName = selected.description
        } else {
            // If no option selected (rare), calculate base from initial item
            let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
            let initialQty = parsed.qty
            // Reconstruct a temporary base option
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
        let finalDescription: String
        if quantityValue == 1 {
            finalDescription = unitName
        } else {
            finalDescription = "\(String(format: "%g", quantityValue)) x \(unitName)"
        }
        
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

    private var adjustedConsistencyStatus: NutritionCalorieConsistency.Status {
        let nutrients = adjustedNutrients
        return NutritionCalorieConsistency.status(
            calories: nutrients.calories,
            protein: nutrients.protein,
            carbs: nutrients.carbs,
            fats: nutrients.fats
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        FoodDetailHeroCard(
                            foodName: foodName,
                            servingDescription: adjustedNutrients.servingDescription
                        )

                        if isShowingDetailsLoading {
                            FoodDetailLoadingCard()
                        } else {
                            if let error = errorLoading {
                                FoodDetailNoticeCard(
                                    title: "Serving details could not fully refresh",
                                    message: error
                                )
                            }

                            FoodDetailMacroGrid(
                                calories: adjustedNutrients.calories,
                                protein: adjustedNutrients.protein,
                                carbs: adjustedNutrients.carbs,
                                fats: adjustedNutrients.fats
                            )

                            let consistencyStatus = adjustedConsistencyStatus
                            if consistencyStatus.hasMeaningfulMismatch {
                                NutritionConsistencyNoticeCard(status: consistencyStatus, style: .detail)
                            }

                            servingControlsCard
                            nutritionDetailsCard
                            FoodDetailLabelScanCard { showingImagePicker = true }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)

                FoodDetailActionBar(
                    title: buttonText(),
                    isEnabled: logButtonEnabled,
                    action: handleButtonAction
                )
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

    @ViewBuilder private var servingControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Serving")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoggedItem ? "Logged servings" : "Number of servings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "number")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: Circle())
            }
            .padding(14)
            .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if canChangeServing {
                if !availableServings.isEmpty {
                    Menu {
                        ForEach(availableServings) { option in
                            Button(option.description) {
                                selectedServingID = option.id
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.brandPrimary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Serving size")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(UIColor.secondaryLabel))

                                Text(selectedServingOption?.description ?? "Select...")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .padding(14)
                        .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if !isLoadingDetails {
                    Text("No other serving sizes available.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            } else if let baseNutrients = baseLoggedItemNutrientsPerUnit {
                Text("Base serving: \(baseNutrients.description)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var nutritionDetailsCard: some View {
        let nutrients = adjustedNutrients
        let totalUnsaturatedFat = nutrients.fats - (nutrients.saturatedFat ?? 0)

        VStack(alignment: .leading, spacing: 13) {
            Text("Nutrition Details")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            DisclosureGroup("Fat & Fiber") {
                VStack(spacing: 8) {
                    nutrientRow(label: "Saturated Fat", value: nutrients.saturatedFat, unit: "g")
                    nutrientRow(label: "Polyunsaturated Fat", value: nutrients.polyunsaturatedFat, unit: "g")
                    nutrientRow(label: "Monounsaturated Fat", value: nutrients.monounsaturatedFat, unit: "g")
                    nutrientRow(label: "Unsaturated Fat", value: totalUnsaturatedFat > 0 ? totalUnsaturatedFat : nil, unit: "g")
                    nutrientRow(label: "Dietary Fiber", value: nutrients.fiber, unit: "g")
                }
                .padding(.top, 8)
            }

            Divider().opacity(0.5)

            DisclosureGroup("Vitamins & Minerals") {
                VStack(spacing: 8) {
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
                .padding(.top, 8)
            }
        }
        .tint(.brandPrimary)
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    
    // MARK: - Update Item (Refactored)
    private func updateItem(onUpdate: (FoodItem) -> Void) {
        guard let quantityValue = Double(quantity), quantityValue > 0 else { return }
        
        let finalNutrients = adjustedNutrients
        let rawUpdatedFoodItem = FoodItem(
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
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK,
            // Save the structured quantity
            quantityValue: finalNutrients.quantityValue,
            servingUnit: finalNutrients.servingUnit
        )
        let updatedFoodItem = rawUpdatedFoodItem.normalizedForEstimatedSource(source)
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
        
        let rawItemToSave = FoodItem(
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
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK,
            quantityValue: finalNutrients.quantityValue,
            servingUnit: finalNutrients.servingUnit
        )
        let itemToSave = rawItemToSave.normalizedForEstimatedSource(source)

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
    
    // MARK: - Setup Initial Data
    // Updated to handle logic for new quantity/unit fields logic
    private func setupInitialData() {
        dailyLogService.activelyViewedDate = self.date

        if source.starts(with: "log_") || source.starts(with: "image_result_edit") {
            // Determine quantity factor (either from explicit new field or parsed string)
            let qtyFactor: Double
            let unitName: String
            
            if let explicitQty = initialFoodItem.quantityValue, let explicitUnit = initialFoodItem.servingUnit {
                qtyFactor = explicitQty
                unitName = explicitUnit
            } else {
                let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
                qtyFactor = parsed.qty > 0 ? parsed.qty : 1.0
                unitName = parsed.baseDesc
            }
            
            // Calculate "Per Unit" nutrients by dividing totals by quantity factor
            let singleUnitNutrients = ServingSizeOption(
                description: unitName,
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
            // (Same logic as above but handled for recent items)
            let qtyFactor: Double
            let unitName: String
            
            if let explicitQty = initialFoodItem.quantityValue, let explicitUnit = initialFoodItem.servingUnit {
                qtyFactor = explicitQty
                unitName = explicitUnit
            } else {
                let parsed = parseQuantityFromServing(initialFoodItem.servingSize)
                qtyFactor = parsed.qty > 0 ? parsed.qty : 1.0
                unitName = parsed.baseDesc
            }
            
            let singleUnitNutrients = ServingSizeOption(
                description: unitName,
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

    // MARK: - Save Data (Robust)
    private func logAdjustedFood() {
        guard let userID = Auth.auth().currentUser?.uid, logButtonEnabled, selectedServingOption != nil else { return }
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
        
        let rawLoggedFoodItem = FoodItem(
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
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK,
            quantityValue: finalNutrients.quantityValue,
            servingUnit: finalNutrients.servingUnit
        )
        let loggedFoodItem = rawLoggedFoodItem.normalizedForEstimatedSource(itemSourceToLog)

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

private struct FoodDetailHeroCard: View {
    let foodName: String
    let servingDescription: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(FoodEmojiMapper.getEmoji(for: foodName))
                .font(.system(size: 34))
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(foodName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(servingDescription, systemImage: "scalemass.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct FoodDetailMacroGrid: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            FoodDetailMacroTile(title: "Calories", value: "\(Int(calories.rounded()))", unit: "cal", icon: "flame.fill", color: .orange)
            FoodDetailMacroTile(title: "Protein", value: String(format: "%.1f", protein), unit: "g", icon: "bolt.fill", color: .accentProtein)
            FoodDetailMacroTile(title: "Carbs", value: String(format: "%.1f", carbs), unit: "g", icon: "leaf.fill", color: .accentCarbs)
            FoodDetailMacroTile(title: "Fat", value: String(format: "%.1f", fats), unit: "g", icon: "drop.fill", color: .accentFats)
        }
    }
}

private struct FoodDetailMacroTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(unit)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FoodDetailLoadingCard: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Loading serving options")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)

            Text("Pulling the most accurate nutrition details for this food.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 18)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FoodDetailNoticeCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.orange)
                .frame(width: 34, height: 34)
                .background(Color.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FoodDetailLabelScanCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Nutrition label looks different?")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("Take a label photo to replace these numbers.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(14)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FoodDetailActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isEnabled)
        }
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
