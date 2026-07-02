import SwiftUI

struct FoodDetailView: View {
    var initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    var date: Date
    var source: String
    var targetMealName: String?
    var onLogUpdated: () -> Void
    var onUpdate: ((FoodItem) -> Void)?

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var bannerService: BannerService
    private let foodAPIService = FatSecretFoodAPIService()
    private let imageModel = MLImageModel()

    @State private var foodName: String
    @State private var availableServings: [ServingSizeOption] = []
    @State private var selectedServingID: UUID?
    @State private var quantity: String = "1"
    @State private var isLoadingDetails: Bool = false
    @State private var errorLoading: String?

    @State private var isLoggedItem: Bool
    @State private var baseLoggedItemNutrientsPerUnit: ServingSizeOption?
    
    @State private var isSavedAsCustom: Bool = false
    @State private var hasSavedBarcodeCorrection: Bool = false
    @State private var customFoodForAction: FoodItem?

    @State private var showingImagePicker = false
    @State private var showingCorrectionEditor = false
    @State private var hasLoggedSuspiciousData = false
    @State private var isProcessingLabel = false
    @State private var scanError: (Bool, String) = (false, "")

    // MARK: - Robust Initializer
    // Updated to use new model fields if available, ensuring stability.
    init(initialFoodItem: FoodItem, dailyLog: Binding<DailyLog?>, date: Date = Date(), source: String = "log", targetMealName: String? = nil, onLogUpdated: @escaping () -> Void, onUpdate: ((FoodItem) -> Void)? = nil) {
        self.initialFoodItem = initialFoodItem
        self._dailyLog = dailyLog
        self.date = date
        self.source = source
        self.targetMealName = targetMealName
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
        let parsed = ServingNutritionCalculator.parseQuantity(from: servingDesc)
        return (parsed.quantity, parsed.baseDescription)
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

    private var sourceDescriptor: FoodSourceDescriptor {
        FoodSourceClassifier.descriptor(
            for: source,
            foodID: initialFoodItem.id,
            metadata: initialFoodItem.sourceMetadata
        )
    }

    private var barcodeForCorrection: String? {
        let barcode = BarcodeCorrectionRules.normalizedBarcode(initialFoodItem.sourceMetadata?.barcode ?? "")
        return barcode.isEmpty ? nil : barcode
    }

    private var shouldShowBarcodeCorrectionCard: Bool {
        barcodeForCorrection != nil &&
            !hasSavedBarcodeCorrection &&
            sourceDescriptor.sourceKey != "custom_barcode"
    }

    private var correctionBaseServing: ServingSizeOption {
        selectedServingOption ?? ServingNutritionCalculator.baseServing(from: initialFoodItem)
    }

    // Sanity-checks the currently selected base serving (per one serving, not quantity-scaled,
    // so a big quantity can't trip the physical-plausibility rules).
    private var sanityCheckItem: FoodItem {
        let serving = correctionBaseServing
        return FoodItem(
            name: foodName,
            calories: serving.calories,
            protein: serving.protein,
            carbs: serving.carbs,
            fats: serving.fats,
            fiber: serving.fiber,
            servingSize: serving.description,
            servingWeight: serving.servingWeightGrams ?? 1.0,
            potassium: serving.potassium,
            sodium: serving.sodium
        )
    }

    private var sanityFindings: [FoodDataSanity.Finding] {
        FoodDataSanity.findings(for: sanityCheckItem)
    }

    /// Trust telemetry: which correction affordances get used, per source. Over time this
    /// says empirically which database is dirtiest and can weight search ranking.
    private func logCorrectionAction(_ action: String) {
        DIContainer.shared.analyticsManager?.logEvent("food_correction_action", parameters: [
            "action": action,
            "source": sourceDescriptor.sourceKey
        ])
    }

    private func logSuspiciousDataIfNeeded() {
        guard !hasLoggedSuspiciousData else { return }
        let findings = sanityFindings
        guard findings.contains(where: { $0.severity == .warning }) else { return }
        hasLoggedSuspiciousData = true
        DIContainer.shared.analyticsManager?.logEvent("food_data_suspicious", parameters: [
            "kinds": findings.map(\.id).joined(separator: ","),
            "source": sourceDescriptor.sourceKey
        ])
    }

    // MARK: - Adjusted Nutrients Calculation
    private var adjustedNutrients: AdjustedServingNutrition {
        let baseNutrients = selectedServingOption ?? ServingNutritionCalculator.baseServing(from: initialFoodItem)
        return ServingNutritionCalculator.adjustedNutrition(
            base: baseNutrients,
            quantityText: quantity
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

                        FoodSourceConfidenceCard(descriptor: sourceDescriptor)

                        if shouldShowBarcodeCorrectionCard {
                            FoodDetailBarcodeCorrectionCard(
                                fixAction: {
                                    logCorrectionAction("fix_opened")
                                    showingCorrectionEditor = true
                                },
                                rememberAction: {
                                    logCorrectionAction("remember")
                                    saveAsCustomFood()
                                }
                            )
                        }

                        if !sanityFindings.isEmpty {
                            FoodDataSanityCard(
                                findings: sanityFindings,
                                fixAction: {
                                    logCorrectionAction("sanity_fix_opened")
                                    showingCorrectionEditor = true
                                }
                            )
                            .onAppear(perform: logSuspiciousDataIfNeeded)
                        }

                        // AI estimates get a persistent refine path even when the numbers
                        // pass every sanity check — the least-trusted source should always
                        // be the easiest to correct.
                        if sourceDescriptor.isEstimated {
                            FoodDetailAIRefineCard(refineAction: {
                                logCorrectionAction("refine_opened")
                                showingCorrectionEditor = true
                            })
                        }

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
        .sheet(isPresented: $showingCorrectionEditor) {
            FoodDetailCorrectionSheet(
                foodName: foodName,
                serving: correctionBaseServing,
                barcode: barcodeForCorrection
            ) { correctedName, correctedServing in
                applyFoodCorrectionAndRemember(
                    foodName: correctedName,
                    serving: correctedServing
                )
            }
            .presentationDetents([.large])
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
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoggedItem ? "Logged servings" : "Number of servings")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "number")
                    .appFont(size: 17, weight: .bold)
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
                                .appFont(size: 14, weight: .bold)
                                .foregroundColor(.brandPrimary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Serving size")
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))

                                Text(selectedServingOption?.description ?? "Select...")
                                    .appFont(size: 15, weight: .bold)
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .appFont(size: 12, weight: .bold)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .padding(14)
                        .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if !isLoadingDetails {
                    Text("No other serving sizes available.")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            } else if let baseNutrients = baseLoggedItemNutrientsPerUnit {
                Text("Base serving: \(baseNutrients.description)")
                    .appFont(size: 13, weight: .medium)
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
                .appFont(size: 18, weight: .bold)
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
            sourceMetadata: initialFoodItem.sourceMetadata,
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
        let updatedFoodItem = rawUpdatedFoodItem
            .normalizedForEstimatedSource(source)
            .markedUserEdited(
                sourceType: inferredSourceType(for: source),
                originalItem: initialFoodItem
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
        let serving = selectedServingOption ?? ServingNutritionCalculator.baseServing(from: initialFoodItem)
        let quantityValue = Double(quantity) ?? 1
        saveCustomFood(foodName: foodName, serving: serving, quantityValue: quantityValue)
    }

    private func saveCustomFood(foodName: String, serving: ServingSizeOption, quantityValue: Double) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let finalNutrients = ServingNutritionCalculator.adjustedNutrition(
            base: serving,
            quantityValue: quantityValue
        )
        
        let rawItemToSave = FoodItem(
            id: UUID().uuidString,
            name: foodName,
            calories: finalNutrients.calories, protein: finalNutrients.protein, carbs: finalNutrients.carbs, fats: finalNutrients.fats,
            saturatedFat: finalNutrients.saturatedFat, polyunsaturatedFat: finalNutrients.polyunsaturatedFat, monounsaturatedFat: finalNutrients.monounsaturatedFat,
            fiber: finalNutrients.fiber, servingSize: finalNutrients.servingDescription, servingWeight: finalNutrients.servingWeightGrams,
            timestamp: nil,
            sourceMetadata: initialFoodItem.sourceMetadata,
            calcium: finalNutrients.calcium, iron: finalNutrients.iron,
            potassium: finalNutrients.potassium, sodium: finalNutrients.sodium, vitaminA: finalNutrients.vitaminA,
            vitaminC: finalNutrients.vitaminC, vitaminD: finalNutrients.vitaminD,
            vitaminB12: finalNutrients.vitaminB12, folate: finalNutrients.folate,
            magnesium: finalNutrients.magnesium, phosphorus: finalNutrients.phosphorus, zinc: finalNutrients.zinc,
            copper: finalNutrients.copper, manganese: finalNutrients.manganese, selenium: finalNutrients.selenium,
            vitaminB1: finalNutrients.vitaminB1, vitaminB2: finalNutrients.vitaminB2, vitaminB3: finalNutrients.vitaminB3,
            vitaminB5: finalNutrients.vitaminB5, vitaminB6: finalNutrients.vitaminB6, vitaminE: finalNutrients.vitaminE, vitaminK: finalNutrients.vitaminK
        )
        let itemToSave = rawItemToSave
            .normalizedForEstimatedSource(source)
            .savedAsCustomFood(
                barcode: initialFoodItem.sourceMetadata?.barcode,
                originalItem: initialFoodItem
            )

        dailyLogService.customFoodStore.saveCustomFood(for: userID, foodItem: itemToSave) { success in
            Task { @MainActor in
                if success {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = itemToSave.sourceMetadata?.barcode?.isEmpty == false
                    self.customFoodForAction = itemToSave
                    let message = self.hasSavedBarcodeCorrection
                        ? "\(foodName) will be used for future scans of this barcode."
                        : "\(foodName) added to My Foods."
                    bannerService.showBanner(title: "Saved", message: message)
                    self.contributeToCommunityPoolIfEligible(itemToSave)
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not save custom food.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }

    /// Shares a saved barcode correction with the community pool when the feature flag is
    /// on and the entry passes the sanity checker. Best-effort: failures stay silent.
    private func contributeToCommunityPoolIfEligible(_ item: FoodItem) {
        guard let barcode = item.sourceMetadata?.barcode else { return }
        let flagEnabled = DIContainer.shared.featureFlagService?.boolValue(for: .communityBarcodeCorrections) ?? false
        guard CommunityBarcodeRules.isEligibleForContribution(item, barcode: barcode, flagEnabled: flagEnabled),
              let store = DIContainer.shared.communityBarcodeStore else { return }
        Task {
            await store.contribute(item, barcode: barcode)
        }
    }

    private func applyFoodCorrectionAndRemember(foodName correctedName: String, serving correctedServing: ServingSizeOption) {
        logCorrectionAction("correction_saved")
        foodName = correctedName
        availableServings.insert(correctedServing, at: 0)
        selectedServingID = correctedServing.id
        quantity = "1"
        saveCustomFood(foodName: correctedName, serving: correctedServing, quantityValue: 1)
    }
    
    private func unsaveCustomFood() {
        guard let userID = DIContainer.shared.authService.currentUserID, let foodID = customFoodForAction?.id else { return }
        dailyLogService.customFoodStore.deleteCustomFood(for: userID, foodItemID: foodID) { success in
            Task { @MainActor in
                if success {
                    self.isSavedAsCustom = false
                    if let barcode = self.barcodeForCorrection,
                       let customFoodForAction = self.customFoodForAction,
                       BarcodeCorrectionRules.matches(customFoodForAction, barcode: barcode) {
                        self.hasSavedBarcodeCorrection = false
                    }
                    self.customFoodForAction = nil
                    bannerService.showBanner(title: "Removed", message: "\(foodName) removed from My Foods.", iconName: "star.slash.fill")
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not remove custom food.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }
    
    private func checkIfSaved() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.customFoodStore.fetchMyFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                guard case .success(let items) = result else { return }

                if let barcode = self.barcodeForCorrection,
                   let savedBarcodeItem = items.first(where: { BarcodeCorrectionRules.matches($0, barcode: barcode) }) {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = true
                    self.customFoodForAction = savedBarcodeItem
                } else if let savedItem = items.first(where: { $0.name == self.foodName }) {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = false
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
            let singleUnitNutrients = ServingNutritionCalculator.baseServing(from: initialFoodItem)
            self.availableServings = [singleUnitNutrients]
            self.selectedServingID = singleUnitNutrients.id
            self.baseLoggedItemNutrientsPerUnit = singleUnitNutrients
            self.isLoadingDetails = false
            
        } else if source == "recent_tap" {
            let singleUnitNutrients = ServingNutritionCalculator.baseServing(from: initialFoodItem)
            self.availableServings = [singleUnitNutrients]
            self.selectedServingID = singleUnitNutrients.id
            self.isLoadingDetails = false

        } else if source == "search_result" || source == "barcode_result" || source == "image_result" {
            fetchAPIServingDetails()
        } else {
            let baseServingOption = ServingNutritionCalculator.baseServing(from: initialFoodItem)
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
                        errorLoading = error.localizedDescription
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
        ServingNutritionCalculator.baseServing(from: foodItem)
    }

    // MARK: - Save Data (Robust)
    private func logAdjustedFood() {
        guard let userID = DIContainer.shared.authService.currentUserID, logButtonEnabled, selectedServingOption != nil else { return }
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
            sourceMetadata: initialFoodItem.sourceMetadata,
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
        let loggedFoodItem = rawLoggedFoodItem
            .normalizedForEstimatedSource(itemSourceToLog)
            .markedUserConfirmed(sourceType: inferredSourceType(for: itemSourceToLog))

        if isLoggedItem {
            dailyLogService.updateFoodInCurrentLog(for: userID, updatedFoodItem: loggedFoodItem)
        } else if let targetMealName {
            dailyLogService.addFoodToLog(
                for: userID,
                date: date,
                mealName: targetMealName,
                foodItem: loggedFoodItem,
                source: itemSourceToLog
            )
        } else {
            dailyLogService.addFoodToCurrentLog(for: userID, foodItem: loggedFoodItem, source: itemSourceToLog)
        }
        
        HapticManager.instance.feedback(.medium)
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

    private func inferredSourceType(for source: String) -> FoodSourceType? {
        let normalizedSource = source.lowercased()
        if normalizedSource.contains("usda") { return .usda }
        if normalizedSource.contains("open_food_facts") { return .openFoodFacts }
        if normalizedSource.contains("barcode") || normalizedSource.contains("fatsecret") { return .fatSecret }
        if normalizedSource.contains("menu") { return .aiMenu }
        if normalizedSource.contains("text") { return .aiText }
        if normalizedSource.contains("ai") || normalizedSource.contains("image") { return .aiImage }
        if normalizedSource.contains("recipe") { return .recipe }
        if normalizedSource.contains("meal_plan") { return .mealPlan }
        if normalizedSource.contains("manual") || normalizedSource.contains("custom") { return .manual }
        if normalizedSource.contains("recent") { return .recent }
        return nil
    }
}

private struct FoodSourceConfidenceCard: View {
    let descriptor: FoodSourceDescriptor

    private var tint: Color {
        switch descriptor.sourceKey {
        case "usda", "fatsecret", "manual", "planned", "custom_barcode":
            return .accentPositive
        case "open_food_facts", "recent":
            return .blue
        case "ai_estimate":
            return .orange
        default:
            return .brandPrimary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: descriptor.systemImage)
                .appFont(size: 17, weight: .bold)
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(descriptor.title)
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(descriptor.confidence)
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.10), in: Capsule())
                }

                Text(descriptor.detail)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.title). \(descriptor.confidence). \(descriptor.detail)")
    }
}
