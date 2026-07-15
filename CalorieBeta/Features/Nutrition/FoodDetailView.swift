import SwiftUI
import UIKit

struct FoodTrustResolution: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

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
    @State private var correctionEditorDidSubmit = false
    @State private var correctionCalibrationContext: FoodTrustCalibrationContext?
    @State private var persistedTrustItem: FoodItem?
    @State private var trustResolution: FoodTrustResolution?
    @State private var isSavingTrustCorrection = false
    @State private var hasLoggedSuspiciousData = false
    @State private var hasLoggedTrustCardView = false
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
            foodID: persistedTrustItem?.id ?? initialFoodItem.id,
            metadata: trustMetadata
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
            saturatedFat: serving.saturatedFat,
            polyunsaturatedFat: serving.polyunsaturatedFat,
            monounsaturatedFat: serving.monounsaturatedFat,
            fiber: serving.fiber,
            servingSize: serving.description,
            servingWeight: serving.servingWeightGrams ?? 1.0,
            calcium: serving.calcium,
            iron: serving.iron,
            potassium: serving.potassium,
            sodium: serving.sodium,
            vitaminA: serving.vitaminA,
            vitaminC: serving.vitaminC,
            vitaminD: serving.vitaminD,
            vitaminB12: serving.vitaminB12,
            folate: serving.folate,
            magnesium: serving.magnesium,
            phosphorus: serving.phosphorus,
            zinc: serving.zinc,
            copper: serving.copper,
            manganese: serving.manganese,
            selenium: serving.selenium,
            vitaminB1: serving.vitaminB1,
            vitaminB2: serving.vitaminB2,
            vitaminB3: serving.vitaminB3,
            vitaminB5: serving.vitaminB5,
            vitaminB6: serving.vitaminB6,
            vitaminE: serving.vitaminE,
            vitaminK: serving.vitaminK
        )
    }

    private var sanityFindings: [FoodDataSanity.Finding] {
        FoodDataSanity.findings(for: sanityCheckItem)
    }

    private var trustMetadata: FoodSourceMetadata? {
        let trustItem = persistedTrustItem ?? initialFoodItem
        guard var metadata = trustItem.sourceMetadata else { return nil }
        if metadata.hasIndependentCrossVerification,
           !FoodSourceAgreement.preservesAgreementEvidence(sanityCheckItem, initialFoodItem) {
            metadata.crossVerifiedBy = nil
        }
        return metadata
    }

    private var trustEvaluation: FoodTrustEvaluation {
        FoodTrustEvaluation.evaluate(
            item: sanityCheckItem,
            descriptor: sourceDescriptor,
            metadata: trustMetadata
        )
    }

    private var trustCalibrationContext: FoodTrustCalibrationContext {
        FoodTrustCalibrationContext(
            item: sanityCheckItem,
            descriptor: sourceDescriptor,
            metadata: trustMetadata
        )
    }

    /// Trust telemetry links source/evidence categories to coarse correction outcomes so model
    /// weights can be calibrated from persisted behavior rather than impressions.
    private func logCorrectionAction(
        _ action: String,
        correctionScope: String? = nil,
        resultingItem: FoodItem? = nil,
        context: FoodTrustCalibrationContext? = nil
    ) {
        let context = context ?? correctionCalibrationContext ?? trustCalibrationContext
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.correctionAction.rawValue,
            parameters: context.analyticsParameters(
                action: action,
                correctionScope: correctionScope,
                resultingItem: resultingItem
            )
        )
    }

    private func logTrustAction(_ action: String) {
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trustAction.rawValue,
            parameters: trustCalibrationContext.analyticsParameters(action: action)
        )
    }

    private func logTrustCardViewedIfNeeded() {
        guard !hasLoggedTrustCardView else { return }
        hasLoggedTrustCardView = true
        DIContainer.shared.analyticsManager?.logEvent(
            ProductAnalytics.Event.trustCardViewed.rawValue,
            parameters: trustCalibrationContext.analyticsParameters()
        )
    }

    private func openCorrectionEditor(action: String) {
        guard !isSavingTrustCorrection else { return }
        correctionEditorDidSubmit = false
        correctionCalibrationContext = trustCalibrationContext
        logCorrectionAction(action, context: correctionCalibrationContext)
        showingCorrectionEditor = true
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
            fats: nutrients.fats,
            fiber: nutrients.fiber
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: AppSpacing.group) {
                        FoodDetailHeroCard(
                            foodName: foodName,
                            servingDescription: adjustedNutrients.servingDescription
                        )

                        FoodTrustReceipt(
                            descriptor: sourceDescriptor,
                            evaluation: trustEvaluation,
                            metadata: trustMetadata,
                            findings: sanityFindings,
                            isSavingCorrection: isSavingTrustCorrection,
                            resolution: trustResolution,
                            onAction: trustEvaluation.action.map { _ in
                                {
                                    logTrustAction("correction_opened")
                                    openCorrectionEditor(action: "trust_fix_opened")
                                }
                            }
                        )
                        .onAppear {
                            logTrustCardViewedIfNeeded()
                            logSuspiciousDataIfNeeded()
                        }

                        if shouldShowBarcodeCorrectionCard, trustEvaluation.action == nil {
                            FoodDetailBarcodeMemoryAction(
                                rememberAction: {
                                    logCorrectionAction("remember")
                                    saveAsCustomFood()
                                }
                            )
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
                            // Only flag when macros imply MORE calories than logged (a possible
                            // undercount). The other direction — logged higher than macros — is the
                            // alcohol / high-fiber / incomplete-macro case where "logged stays
                            // official," so surfacing it just adds noise (beer, low-cal tortillas).
                            if consistencyStatus.hasMeaningfulMismatch && consistencyStatus.delta > 0 {
                                NutritionConsistencyNoticeCard(status: consistencyStatus, style: .detail)
                            }

                            servingControlsCard
                            nutritionDetailsCard
                            FoodDetailLabelScanCard { showingImagePicker = true }
    }
}

                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                    .padding(.bottom, AppSpacing.row)
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
                        .foregroundColor(isSavedAsCustom ? AppPalette.achievement : AppPalette.brand)
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
        .sheet(isPresented: $showingCorrectionEditor, onDismiss: {
            if !correctionEditorDidSubmit {
                logCorrectionAction(
                    "correction_abandoned",
                    context: correctionCalibrationContext
                )
            }
            correctionEditorDidSubmit = false
            correctionCalibrationContext = nil
        }) {
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
        .alert("Scan error", isPresented: $scanError.0) {
            Button("OK") { }
        } message: {
            Text(scanError.1)
        }
    }

    @ViewBuilder private var servingControlsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Serving")

            HStack(spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoggedItem ? "Logged servings" : "Number of servings")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Quantity", text: $quantity)
                        .accessibilityLabel("Quantity")
                        .keyboardType(.decimalPad)
                        .appTextRole(.metric)
                        .foregroundStyle(AppPalette.text)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "number")
                    .appFont(size: 17, weight: .bold)
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.brand.opacity(0.10), in: Circle())
            }
            .padding(.vertical, AppSpacing.compact)

            if canChangeServing {
                if !availableServings.isEmpty {
                    Divider()

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
                                .foregroundStyle(AppPalette.brand)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Serving size")
                                    .appTextRole(.caption)
                                    .foregroundStyle(.secondary)

                                Text(selectedServingOption?.description ?? "Select")
                                    .appTextRole(.control)
                                    .foregroundStyle(AppPalette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Image(systemName: "chevron.up.chevron.down")
                                .appFont(size: 12, weight: .bold)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .padding(.vertical, AppSpacing.compact)
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
        .appSurface(.quiet)
        .accessibilityIdentifier("food_detail_serving_controls")
    }

    @ViewBuilder private var nutritionDetailsCard: some View {
        let nutrients = adjustedNutrients
        let totalUnsaturatedFat = nutrients.fats - (nutrients.saturatedFat ?? 0)

        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Nutrition details")

            DisclosureGroup("Fat and fiber") {
                VStack(spacing: 8) {
                    nutrientRow(label: "Saturated fat", value: nutrients.saturatedFat, unit: "g")
                    nutrientRow(label: "Polyunsaturated fat", value: nutrients.polyunsaturatedFat, unit: "g")
                    nutrientRow(label: "Monounsaturated fat", value: nutrients.monounsaturatedFat, unit: "g")
                    nutrientRow(label: "Unsaturated fat", value: totalUnsaturatedFat > 0 ? totalUnsaturatedFat : nil, unit: "g")
                    nutrientRow(label: "Dietary fiber", value: nutrients.fiber, unit: "g")
                }
                .padding(.top, 8)
            }

            Divider().opacity(0.5)

            DisclosureGroup("Vitamins and minerals") {
                VStack(spacing: 8) {
                    Text("\(nutrients.reportedVitaminMineralCount) of \(MicronutrientKey.vitaminAndMineralKeys.count) vitamins and minerals reported. Missing values are unknown, not zero.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .tint(AppPalette.brand)
        .appSurface(.quiet)
        .accessibilityIdentifier("food_detail_nutrition_details")
    }

    private var labelScannerButton: some View {
        Button {
            showingImagePicker = true
        } label: {
            Label("Not correct? Take a photo of the nutrition label.", systemImage: "camera.fill")
        }
        .tint(AppPalette.effort)
        .padding(.top, 5)
    }

    private func handleScannedNutrition(_ data: NutritionLabelData) {
        self.foodName = data.foodName
        let scannedServing = ServingSizeOption(
            description: data.servingDescription ?? "Scanned from label",
            servingWeightGrams: data.servingWeightGrams,
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
            return "Update item"
        }
        return isLoggedItem ? "Update logged item" : "Add to log"
    }

    private func navigationTitleText() -> String {
        if onUpdate != nil {
            return "Edit item"
        }
        return isLoggedItem ? "Edit logged item" : "Log food"
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

    private func saveCustomFood(
        foodName: String,
        serving: ServingSizeOption,
        quantityValue: Double,
        correctionScope: String? = nil,
        calibrationContext: FoodTrustCalibrationContext? = nil,
        completion: ((Bool, FoodItem?) -> Void)? = nil
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            if let correctionScope {
                logCorrectionAction(
                    "correction_save_failed",
                    correctionScope: correctionScope,
                    context: calibrationContext
                )
            }
            completion?(false, nil)
            return
        }
        let finalNutrients = ServingNutritionCalculator.adjustedNutrition(
            base: serving,
            quantityValue: quantityValue
        )
        
        let rawItemToSave = FoodItem(
            id: customFoodForAction?.id ?? (
                initialFoodItem.sourceMetadata?.sourceType == .custom
                    ? initialFoodItem.id
                    : UUID().uuidString
            ),
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
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self.persistedTrustItem = itemToSave
                    }
                    let message = self.hasSavedBarcodeCorrection
                        ? "\(foodName) will be used for future scans of this barcode."
                        : "\(foodName) added to My Foods."
                    bannerService.showBanner(title: "Saved", message: message)
                    self.contributeToCommunityPoolIfEligible(itemToSave)
                } else {
                    bannerService.showBanner(title: "Error", message: "Could not save custom food.", iconName: "xmark.circle.fill", iconColor: AppPalette.critical)
                }
                if let correctionScope {
                    self.logCorrectionAction(
                        success ? "correction_saved" : "correction_save_failed",
                        correctionScope: correctionScope,
                        resultingItem: success ? itemToSave : nil,
                        context: calibrationContext
                    )
                }
                completion?(success, success ? itemToSave : nil)
            }
        }
    }

    /// Shares a saved barcode correction with the community pool when the feature flag is
    /// on and the entry passes the sanity checker. Best-effort: failures stay silent.
    private func contributeToCommunityPoolIfEligible(_ item: FoodItem) {
        guard let barcode = item.sourceMetadata?.barcode else { return }
        let flagEnabled = DIContainer.shared.featureFlagService?.boolValue(for: .communityBarcodeCorrections) ?? false
        let decision = CommunityBarcodeRules.contributionDecision(item, barcode: barcode, flagEnabled: flagEnabled)
        DIContainer.shared.analyticsManager?.logEvent("community_barcode_contribution_evaluated", parameters: [
            "eligible": decision.isEligible,
            "reason": decision.reason,
            "flag_enabled": flagEnabled,
            "source": sourceDescriptor.sourceKey
        ])
        guard decision.isEligible, let store = DIContainer.shared.communityBarcodeStore else { return }
        Task {
            await store.contribute(item, barcode: barcode)
        }
    }

    private func applyFoodCorrectionAndRemember(foodName correctedName: String, serving correctedServing: ServingSizeOption) {
        let originalServing = correctionBaseServing
        let correctionScope = FoodCorrectionTelemetry.scope(
            originalName: foodName,
            originalServing: originalServing,
            correctedName: correctedName,
            correctedServing: correctedServing
        )
        let calibrationContext = correctionCalibrationContext ?? trustCalibrationContext
        correctionEditorDidSubmit = true
        logCorrectionAction(
            "correction_submitted",
            correctionScope: correctionScope,
            context: calibrationContext
        )
        isSavingTrustCorrection = true
        saveCustomFood(
            foodName: correctedName,
            serving: correctedServing,
            quantityValue: 1,
            correctionScope: correctionScope,
            calibrationContext: calibrationContext
        ) { success, persistedItem in
            self.isSavingTrustCorrection = false
            guard success, persistedItem != nil else { return }

            withAnimation(.easeInOut(duration: 0.24)) {
                self.foodName = correctedName
                self.availableServings.removeAll { $0.id == correctedServing.id }
                self.availableServings.insert(correctedServing, at: 0)
                self.selectedServingID = correctedServing.id
                self.quantity = "1"
                self.trustResolution = FoodTrustResolution(
                    title: "Correction saved",
                    detail: self.barcodeForCorrection == nil
                        ? "Trust now reflects your saved review"
                        : "Future scans will use this reviewed entry"
                )
            }
            HapticManager.instance.notification(.success)
        }
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
                    bannerService.showBanner(title: "Error", message: "Could not remove custom food.", iconName: "xmark.circle.fill", iconColor: AppPalette.critical)
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
                    self.persistedTrustItem = savedBarcodeItem
                } else if let savedItem = items.first(where: { $0.name == self.foodName }) {
                    self.isSavedAsCustom = true
                    self.hasSavedBarcodeCorrection = false
                    self.customFoodForAction = savedItem
                    if savedItem.id == self.initialFoodItem.id {
                        self.persistedTrustItem = savedItem
                    }
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
        let likelyApiId = FoodSearchRanking.isFatSecretID(initialFoodItem.id)
        
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
            .markedUserConfirmed(
                sourceType: inferredSourceType(for: itemSourceToLog),
                originalItem: initialFoodItem
            )

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
        if let unwrappedValue = value, unwrappedValue.isFinite, unwrappedValue >= 0 {
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
        if normalizedSource.contains("chain_builder") || normalizedSource.contains("chain builder") { return .chainBuilder }
        if normalizedSource.contains("recipe") { return .recipe }
        if normalizedSource.contains("meal_plan") { return .mealPlan }
        if normalizedSource.contains("manual") || normalizedSource.contains("custom") { return .manual }
        if normalizedSource.contains("recent") { return .recent }
        return nil
    }
}

struct FoodTrustReceipt: View {
    let descriptor: FoodSourceDescriptor
    let evaluation: FoodTrustEvaluation
    let metadata: FoodSourceMetadata?
    let findings: [FoodDataSanity.Finding]
    let isSavingCorrection: Bool
    let resolution: FoodTrustResolution?
    let onAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsScoreDetails = false
    @State private var presentedResolution: FoodTrustResolution?

    private var tint: Color {
        switch evaluation.level {
        case .excellent, .strong:
            return .accentPositiveText
        case .review:
            return AppPalette.caution
        case .low:
            return evaluation.requiresCorrection ? AppPalette.critical : AppPalette.caution
        }
    }

    private var sourceName: String {
        metadata?.sourceName ?? descriptor.title
    }

    private var verifiedSources: [String] {
        metadata?.validatedCrossVerifiedBy ?? []
    }

    private var crossVerificationText: String {
        if !verifiedSources.isEmpty {
            return "Calories + macros matched with \(verifiedSources.prefix(2).joined(separator: ", "))"
        }
        if descriptor.sourceKey == "community_barcode" {
            return "One community submission"
        }
        if descriptor.isEstimated {
            return "No independent database match"
        }
        switch descriptor.sourceKey {
        case "usda", "fatsecret", "open_food_facts":
            return "One database source"
        default:
            return "No independent database match"
        }
    }

    private var crossVerificationTint: Color {
        verifiedSources.isEmpty ? Color(UIColor.secondaryLabel) : .accentPositiveText
    }

    private var reviewText: String {
        switch metadata?.reviewStatus {
        case .userEdited:
            return "Nutrition edited"
        case .userConfirmed:
            return "Serving reviewed"
        case .notRequired, .unreviewed, nil:
            return "Serving not reviewed"
        }
    }

    private var visibleReasons: [FoodTrustReason] {
        evaluation.reasonDetails.filter { $0.kind != .evidence }
    }

    private var reviewTint: Color {
        switch metadata?.reviewStatus {
        case .userEdited, .userConfirmed:
            return .accentPositiveText
        case .notRequired:
            return Color(UIColor.secondaryLabel)
        case .unreviewed, nil:
            return descriptor.isEstimated ? AppPalette.caution : Color(UIColor.secondaryLabel)
        }
    }

    private var sanityText: String {
        let warningCount = findings.filter { $0.severity == .warning }.count
        if warningCount > 0 {
            return warningCount == 1 ? "1 warning" : "\(warningCount) warnings"
        }
        if findings.isEmpty {
            return "No warnings found"
        }
        return "1 detail to review"
    }

    private var sanityTint: Color {
        if findings.contains(where: { $0.severity == .warning }) {
            return AppPalette.critical
        }
        return findings.isEmpty ? .accentPositiveText : AppPalette.caution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            receiptHeader

            if let presentedResolution {
                resolutionNotice(presentedResolution)
                    .transition(.opacity)
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                receiptStep(
                    icon: descriptor.systemImage,
                    title: "Source",
                    value: sourceName,
                    detail: "\(descriptor.confidence). \(descriptor.detail)",
                    rowTint: tint,
                    isLast: false
                )
                receiptStep(
                    icon: "checkmark.seal.fill",
                    title: "Verification",
                    value: crossVerificationText,
                    detail: verificationDetail,
                    rowTint: crossVerificationTint,
                    isLast: false
                )
                nutritionStep
                receiptStep(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Your Review",
                    value: reviewText,
                    detail: reviewDetail,
                    rowTint: reviewTint,
                    isLast: true,
                    isEmphasized: presentedResolution != nil
                )
            }

            scoreDisclosure

            if let action = evaluation.action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 8) {
                        if isSavingCorrection {
                            ProgressView()
                        } else {
                            Image(systemName: action == "Fix data" ? "pencil" : "slider.horizontal.3")
                        }
                        Text(isSavingCorrection ? "Saving correction" : action)
                    }
                }
                .buttonStyle(AppActionButtonStyle(evaluation.requiresCorrection ? .destructive : .secondary))
                .disabled(isSavingCorrection)
                .accessibilityIdentifier("food_trust_action")
                .accessibilityLabel(isSavingCorrection ? "Saving correction" : action)
                .accessibilityHint("Opens the nutrition editor for this food.")
            }
        }
        .padding(.vertical, 4)
        .task(id: resolution?.id) {
            await presentResolutionIfNeeded()
        }
    }

    private var receiptHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    receiptIdentity
                    scoreSummary
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    receiptIdentity
                    Spacer(minLength: AppSpacing.group)
                    scoreSummary
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var receiptIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Trust Receipt")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
                .accessibilityIdentifier("food_trust_receipt")
            Text(evaluation.label)
                .appFont(size: 12, weight: .bold)
                .foregroundColor(tint)
        }
    }

    private var scoreSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(evaluation.score)")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(tint)
            Text("/99")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("food_trust_score")
        .accessibilityLabel("Trust Score")
        .accessibilityValue("\(evaluation.score) out of 99, \(evaluation.label)")
    }

    private func resolutionNotice(_ resolution: FoodTrustResolution) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentPositiveText)
            VStack(alignment: .leading, spacing: 1) {
                Text(resolution.title)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(resolution.detail)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentPositiveText)
                .frame(width: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(resolution.title). \(resolution.detail)")
    }

    private func receiptStep(
        icon: String,
        title: String,
        value: String,
        detail: String,
        rowTint: Color,
        isLast: Bool,
        showsFindings: Bool = false,
        isEmphasized: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .appFont(size: 12, weight: .bold)
                .foregroundColor(rowTint)
                .frame(width: 30, height: 30)
                .background(rowTint.opacity(0.11), in: Circle())
                .overlay {
                    Circle()
                        .stroke(rowTint.opacity(isEmphasized ? 0.48 : 0), lineWidth: 2)
                        .padding(-3)
                }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsFindings, !findings.isEmpty {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(findingFieldTitle(finding))
                                .appFont(size: 10, weight: .bold)
                                .foregroundColor(finding.severity == .warning ? AppPalette.critical : AppPalette.caution)
                            Text(finding.message)
                                .appFont(size: 11, weight: .medium)
                                .foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 3)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(finding.severity == .warning ? AppPalette.critical : AppPalette.caution)
                                .frame(width: 2)
                        }
                    }
                } else {
                    Text(detail)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .overlay(alignment: .topLeading) {
            if !isLast {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color(UIColor.separator).opacity(0.55))
                        .frame(width: 2, height: max(0, proxy.size.height - 27))
                        .offset(x: 14, y: 30)
                }
                .allowsHitTesting(false)
            }
        }
        .background(isEmphasized ? rowTint.opacity(0.055) : Color.clear)
        .scaleEffect(isEmphasized && !reduceMotion ? 1.01 : 1, anchor: .leading)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.22),
            value: isEmphasized
        )
        .accessibilityElement(children: .combine)
    }

    private var nutritionStep: some View {
        receiptStep(
            icon: "checkmark.shield.fill",
            title: "Nutrition Check",
            value: sanityText,
            detail: "No contradictions found in the serving, calories, macros, or fat breakdown.",
            rowTint: sanityTint,
            isLast: false,
            showsFindings: true,
            isEmphasized: presentedResolution != nil
        )
    }

    private var scoreDisclosure: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.2)) {
                    showsScoreDetails.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Why this score")
                        .appFont(size: 12, weight: .bold)
                    Spacer(minLength: 0)
                    Image(systemName: showsScoreDetails ? "chevron.up" : "chevron.down")
                        .appFont(size: 10, weight: .bold)
                }
                .foregroundColor(.textPrimary)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsScoreDetails ? "Hide Trust Score details" : "Show Trust Score details")

            if showsScoreDetails {
                Text(evaluation.summary)
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * CGFloat(evaluation.score) / 99)
                        }
                }
                .frame(height: 5)
                .accessibilityHidden(true)

                ForEach(Array(visibleReasons.prefix(3))) { reason in
                    Label(reason.text, systemImage: reasonIcon(for: reason))
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(reasonTint(for: reason))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var verificationDetail: String {
        if !verifiedSources.isEmpty {
            return "Independent sources agreed on calories and macros."
        }
        if descriptor.sourceKey == "community_barcode" {
            return "The published aggregate contains no contributor identity."
        }
        if descriptor.isEstimated {
            return "No database independently verified this estimate."
        }
        switch descriptor.sourceKey {
        case "usda", "fatsecret", "open_food_facts":
            return "No second source was available for comparison."
        default:
            return "No independent match is attached to this entry."
        }
    }

    private var reviewDetail: String {
        switch metadata?.reviewStatus {
        case .userEdited:
            return "Your saved nutrition correction is part of this entry."
        case .userConfirmed:
            return "You confirmed the serving or nutrition for this entry."
        case .notRequired:
            return "No personal correction is attached."
        case .unreviewed, nil:
            return descriptor.isEstimated
                ? "Review the serving before relying on this estimate."
                : "No personal review is attached."
        }
    }

    private func findingFieldTitle(_ finding: FoodDataSanity.Finding) -> String {
        switch finding.id {
        case "saturated_fat_exceeds_total": return "Saturated fat + Total fat"
        case "fiber_exceeds_carbs": return "Fiber + Total carbs"
        case "macros_exceed_serving_weight": return "Macros + Serving weight"
        case "serving_weight_implausible", "energy_density_impossible": return "Serving weight"
        case "sodium_unit_suspect", "sodium_high_for_entry": return "Sodium"
        case "potassium_unit_suspect", "potassium_high_for_entry": return "Potassium"
        case "macros_without_calories", "calories_undercount", "calories_below_macro_estimate",
             "calories_exceed_macros": return "Calories + Macros"
        default: return "Nutrition values"
        }
    }

    @MainActor
    private func presentResolutionIfNeeded() async {
        guard let resolution else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : .easeInOut(duration: 0.22)) {
            presentedResolution = resolution
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(resolution.title). \(resolution.detail)"
        )
        do {
            try await Task.sleep(nanoseconds: 2_600_000_000)
        } catch {
            return
        }
        guard presentedResolution?.id == resolution.id else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.14 : 0.2)) {
            presentedResolution = nil
        }
    }

    private func reasonIcon(for reason: FoodTrustReason) -> String {
        switch reason.kind {
        case .evidence:
            return "checkmark.circle.fill"
        case .caution:
            return "exclamationmark.circle.fill"
        case .correction:
            return "exclamationmark.triangle.fill"
        }
    }

    private func reasonTint(for reason: FoodTrustReason) -> Color {
        switch reason.kind {
        case .evidence:
            return Color(UIColor.secondaryLabel)
        case .caution:
            return AppPalette.caution
        case .correction:
            return AppPalette.critical
        }
    }
}
