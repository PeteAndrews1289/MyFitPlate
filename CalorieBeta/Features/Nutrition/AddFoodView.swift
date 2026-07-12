import SwiftUI

struct AddFoodView: View {
    // New arguments for Smart Serving logic
    var initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    var date: Date = Date()
    var source: String = "manual"
    var targetMealName: String?
    var onLogUpdated: () -> Void
    var onUpdate: ((FoodItem) -> Void)?

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var bannerService: BannerService
    private let foodAPIService = FatSecretFoodAPIService()
    private let imageModel = MLImageModel()

    @State private var foodName: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatsText: String
    @State private var saturatedFatText: String
    @State private var fiberText: String
    @State private var servingSizeText: String
    @State private var servingWeightText: String
    @State private var availableServings: [ServingSizeOption] = []
    @State private var selectedServingID: UUID?
    @State private var quantity: String = "1"
    @State private var isLoadingDetails: Bool = false
    @State private var errorLoading: String?

    @State private var isLoggedItem: Bool
    @State private var baseLoggedItemNutrientsPerUnit: ServingSizeOption?

    @State private var isSavedAsCustom: Bool = false
    @State private var customFoodForAction: FoodItem?

    @State private var showingImagePicker = false
    @State private var isProcessingLabel = false
    @State private var hasScannedNutritionLabel = false
    @State private var scanError: (Bool, String) = (false, "")

    // MARK: - Robust Initializer
    init(initialFoodItem: FoodItem, dailyLog: Binding<DailyLog?>, date: Date = Date(), source: String = "manual", targetMealName: String? = nil, onLogUpdated: @escaping () -> Void, onUpdate: ((FoodItem) -> Void)? = nil) {
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
        self._caloriesText = State(initialValue: Self.fieldText(for: initialFoodItem.calories))
        self._proteinText = State(initialValue: Self.fieldText(for: initialFoodItem.protein))
        self._carbsText = State(initialValue: Self.fieldText(for: initialFoodItem.carbs))
        self._fatsText = State(initialValue: Self.fieldText(for: initialFoodItem.fats))
        self._saturatedFatText = State(initialValue: Self.fieldText(for: initialFoodItem.saturatedFat))
        self._fiberText = State(initialValue: Self.fieldText(for: initialFoodItem.fiber))
        self._servingSizeText = State(initialValue: initialFoodItem.servingSize.isEmpty ? "1 serving" : initialFoodItem.servingSize)
        self._servingWeightText = State(initialValue: Self.fieldText(for: initialFoodItem.servingWeight))

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

    private static func fieldText(for value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%g", value)
    }

    private func parseQuantityFromServing(_ servingDesc: String) -> (qty: Double, baseDesc: String) {
        let parsed = ServingNutritionCalculator.parseQuantity(from: servingDesc)
        return (parsed.quantity, parsed.baseDescription)
    }

    private var selectedServingOption: ServingSizeOption? {
        guard let selectedID = selectedServingID else { return nil }
        return availableServings.first { $0.id == selectedID }
    }

    private var trimmedFoodName: String {
        foodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var logButtonEnabled: Bool {
        guard !trimmedFoodName.isEmpty else { return false }
        guard let quantityValue = Double(quantity), quantityValue > 0 else { return false }
        let numericFields = [
            caloriesText, proteinText, carbsText, fatsText,
            saturatedFatText, fiberText, servingWeightText
        ]
        guard numericFields.allSatisfy({ text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || doubleValue(text) != nil
        }) else {
            return false
        }
        let hasCoreNutrition = [caloriesText, proteinText, carbsText, fatsText]
            .contains { doubleValue($0) != nil }
        return hasCoreNutrition && saturatedFatValidationMessage == nil
    }

    private func doubleValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private var saturatedFatValidationMessage: String? {
        guard let saturatedFat = doubleValue(saturatedFatText) else { return nil }
        let totalFat = doubleValue(fatsText) ?? selectedServingOption?.fats ?? initialFoodItem.fats
        guard !FoodDataSanity.saturatedFatFitsWithinTotalFat(
            saturatedFat: saturatedFat,
            totalFat: totalFat
        ) else {
            return nil
        }
        return "Saturated fat cannot be greater than total fat."
    }

    private var editableBaseServingOption: ServingSizeOption {
        let trimmedDescription = servingSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServingNutritionCalculator.editableServing(
            from: initialFoodItem,
            selectedServing: selectedServingOption,
            edits: ServingNutritionEdits(
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                servingWeightGrams: doubleValue(servingWeightText),
                calories: doubleValue(caloriesText),
                protein: doubleValue(proteinText),
                carbs: doubleValue(carbsText),
                fats: doubleValue(fatsText),
                visibleSaturatedFat: doubleValue(saturatedFatText),
                visibleFiber: doubleValue(fiberText)
            )
        )
    }

    // MARK: - Adjusted Nutrients Calculation
    private var adjustedNutrients: AdjustedServingNutrition {
        ServingNutritionCalculator.adjustedNutrition(
            base: editableBaseServingOption,
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

    private var estimatedNormalizationMessage: String? {
        let status = adjustedConsistencyStatus
        guard NutritionCalorieConsistency.isEstimatedSource(source),
              status.hasMeaningfulMismatch,
              status.delta > 0 else {
            return nil
        }

        let loggedCalories = Int(status.loggedCalories.rounded())
        let macroCalories = Int(status.macroDerivedCalories.rounded())
        return "Macros imply \(macroCalories.formatted()) cal, so this estimate will log as \(macroCalories.formatted()) cal instead of \(loggedCalories.formatted())."
    }

    private var correctionBarcode: String? {
        let normalized = BarcodeCorrectionRules.normalizedBarcode(initialFoodItem.sourceMetadata?.barcode ?? "")
        return normalized.isEmpty ? nil : normalized
    }

    private var isBarcodeCorrectionFlow: Bool {
        source == "manual_barcode_create" && correctionBarcode != nil
    }

    private var communityCorrectionSharingEnabled: Bool {
        DIContainer.shared.featureFlagService?.boolValue(for: .communityBarcodeCorrections) ?? false
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        ManualFoodIdentityCard(foodName: $foodName)

                        if isBarcodeCorrectionFlow, let correctionBarcode {
                            ManualBarcodeCorrectionCard(
                                barcode: correctionBarcode,
                                hasScannedLabel: hasScannedNutritionLabel,
                                communitySharingEnabled: communityCorrectionSharingEnabled,
                                scanAction: beginNutritionLabelScan
                            )
                        }

                        if isLoadingDetails && !isLoggedItem && source != "recent_tap" {
                            ManualFoodLoadingCard()
                        }

                        if let errorLoading {
                            ManualFoodNoticeCard(title: "Serving details unavailable", message: errorLoading)
                        }

                        ManualFoodMacroInputGrid(
                            caloriesText: $caloriesText,
                            proteinText: $proteinText,
                            carbsText: $carbsText,
                            fatsText: $fatsText
                        )

                        servingControlsCard
                        detailControlsCard

                        ManualFoodPreviewCard(
                            calories: adjustedNutrients.calories,
                            protein: adjustedNutrients.protein,
                            carbs: adjustedNutrients.carbs,
                            fats: adjustedNutrients.fats,
                            servingDescription: adjustedNutrients.servingDescription
                        )

                        let consistencyStatus = adjustedConsistencyStatus
                        // Only flag a possible undercount (macros imply MORE than logged). The
                        // logged-higher direction (alcohol, fiber, incomplete macros) is the safe
                        // "logged stays official" case — flagging it just adds noise.
                        if consistencyStatus.hasMeaningfulMismatch && consistencyStatus.delta > 0 {
                            NutritionConsistencyNoticeCard(
                                status: consistencyStatus,
                                style: .detail,
                                messageOverride: estimatedNormalizationMessage
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)

                ManualFoodActionBar(
                    title: buttonText(),
                    isEnabled: logButtonEnabled,
                    action: logAdjustedFood
                )
            }
            .blur(radius: isProcessingLabel ? 3 : 0)

            if isProcessingLabel {
                ImageProcessingView()
            }
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle(navigationTitleText())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: toggleSavedState) {
                    Image(systemName: isSavedAsCustom ? "star.fill" : "star")
                        .foregroundColor(isSavedAsCustom ? .yellow : .blue)
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .onChange(of: selectedServingID) {
            syncEditableFieldsFromSelectedServing()
        }
        .onAppear {
            setupInitialData()
            checkIfSaved()
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: .camera) { image in
                isProcessingLabel = true
                logLabelScanStarted()
                DIContainer.shared.analyticsManager.log(.aiFeatureUsed, ["feature": AIFeature.nutritionLabel.rawValue])
                imageModel.parseNutritionLabel(from: image) { result in
                    isProcessingLabel = false
                    switch result {
                    case .success(let nutrition):
                        handleScannedNutrition(nutrition)
                        logLabelScanCompleted(result: "success")
                        bannerService.showBanner(title: "Success", message: "Nutrition label scanned successfully", iconName: "checkmark.circle.fill", iconColor: .accentPositive)
                    case .failure(let error):
                        logLabelScanCompleted(result: "failure")
                        bannerService.showBanner(
                            title: "Scan error",
                            message: "Couldn't read label: \(error.localizedDescription)",
                            iconName: "exclamationmark.triangle.fill",
                            iconColor: .red
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder private var servingControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Serving")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                ManualFoodTextInput(
                    title: "Quantity",
                    placeholder: "1",
                    text: $quantity,
                    keyboardType: .decimalPad,
                    icon: "number",
                    color: .blue
                )

                ManualFoodTextInput(
                    title: "Weight",
                    placeholder: "grams",
                    text: $servingWeightText,
                    keyboardType: .decimalPad,
                    icon: "scalemass.fill",
                    color: .blue
                )
            }

            ManualFoodTextInput(
                title: "Serving description",
                placeholder: "1 cup, 1 bar, 100 g",
                text: $servingSizeText,
                keyboardType: .default,
                icon: "fork.knife",
                color: .blue
            )

            if availableServings.count > 1 {
                Menu {
                    ForEach(availableServings) { option in
                        Button(option.description) {
                            selectedServingID = option.id
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Detected serving options")
                                .appFont(size: 13, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))

                            Text(selectedServingOption?.description ?? "Choose serving")
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
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var detailControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.textPrimary)

            ManualFoodTextInput(
                title: "Saturated fat",
                placeholder: "optional",
                text: $saturatedFatText,
                keyboardType: .decimalPad,
                icon: "drop.fill",
                color: .accentFats,
                unit: "g"
            )

            if let saturatedFatValidationMessage {
                Label(saturatedFatValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ManualFoodTextInput(
                title: "Fiber",
                placeholder: "optional",
                text: $fiberText,
                keyboardType: .decimalPad,
                icon: "leaf.fill",
                color: .accentPositive
            )

            Button {
                beginNutritionLabelScan()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(.blue)
                        .frame(width: 42, height: 42)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scan nutrition label")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)

                        Text("Use a label photo to fill the numbers faster.")
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .padding(14)
                .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var labelScannerButton: some View {
        Button { beginNutritionLabelScan() } label: {
            Label("Scan nutrition label", systemImage: "camera.fill")
        }
        .tint(.blue)
        .padding(.top, 5)
    }

    private func beginNutritionLabelScan() {
        showingImagePicker = true
    }

    private func logLabelScanStarted() {
        guard isBarcodeCorrectionFlow else { return }
        DIContainer.shared.analyticsManager?.logEvent("barcode_label_correction_scan_started", parameters: [
            "barcode_length": correctionBarcode?.count ?? 0
        ])
    }

    private func logLabelScanCompleted(result: String) {
        guard isBarcodeCorrectionFlow else { return }
        DIContainer.shared.analyticsManager?.logEvent("barcode_label_correction_scan_completed", parameters: [
            "result": result,
            "barcode_length": correctionBarcode?.count ?? 0
        ])
    }

    private func syncEditableFieldsFromSelectedServing() {
        guard let selectedServingOption else { return }
        servingSizeText = selectedServingOption.description
        servingWeightText = Self.fieldText(for: selectedServingOption.servingWeightGrams)
        caloriesText = Self.fieldText(for: selectedServingOption.calories)
        proteinText = Self.fieldText(for: selectedServingOption.protein)
        carbsText = Self.fieldText(for: selectedServingOption.carbs)
        fatsText = Self.fieldText(for: selectedServingOption.fats)
        saturatedFatText = Self.fieldText(for: selectedServingOption.saturatedFat)
        fiberText = Self.fieldText(for: selectedServingOption.fiber)
    }

    // MARK: - Setup Initial Data
    private func setupInitialData() {
        dailyLogService.activelyViewedDate = self.date

        // Logic to determine if we should fetch API details or use existing
        if source == "search_result" || source == "barcode_result" {
            fetchAPIServingDetails()
        } else {
            // Create a default "1 serving" option from the existing data
            let defaultOption = createFallbackServing(from: initialFoodItem)
            self.availableServings = [defaultOption]
            self.selectedServingID = defaultOption.id
            syncEditableFieldsFromSelectedServing()
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

                    let parsed = self.parseQuantityFromServing(self.initialFoodItem.servingSize)
                    let targetDescription = self.initialFoodItem.servingUnit ?? parsed.baseDesc

                    var matchedServing: ServingSizeOption?
                    if !targetDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        matchedServing = self.availableServings.first { option in
                            option.description.localizedCaseInsensitiveCompare(targetDescription) == .orderedSame ||
                            targetDescription.localizedCaseInsensitiveContains(option.description)
                        }
                    }

                    self.selectedServingID = matchedServing?.id ?? self.availableServings.first?.id
                    self.syncEditableFieldsFromSelectedServing()
                case .failure(let error):
                    self.errorLoading = error.localizedDescription
                    self.availableServings = [self.createFallbackServing(from: self.initialFoodItem)]
                    self.selectedServingID = self.availableServings.first?.id
                    self.syncEditableFieldsFromSelectedServing()
                }
            }
        }
    }

    private func createFallbackServing(from item: FoodItem) -> ServingSizeOption {
        ServingNutritionCalculator.baseServing(from: item)
    }

    private func handleScannedNutrition(_ data: NutritionLabelData) {
        hasScannedNutritionLabel = true
        self.foodName = data.foodName
        let scanned = ServingSizeOption(description: data.servingDescription ?? "Scanned label", servingWeightGrams: data.servingWeightGrams, calories: data.calories, protein: data.protein, carbs: data.carbs, fats: data.fats, saturatedFat: data.saturatedFat, polyunsaturatedFat: data.polyunsaturatedFat, monounsaturatedFat: data.monounsaturatedFat, fiber: data.fiber, calcium: data.calcium, iron: data.iron, potassium: data.potassium, sodium: data.sodium, vitaminA: data.vitaminA, vitaminC: data.vitaminC, vitaminD: data.vitaminD, vitaminB12: data.vitaminB12, folate: data.folate, magnesium: data.magnesium, phosphorus: data.phosphorus, zinc: data.zinc, copper: data.copper, manganese: data.manganese, selenium: data.selenium, vitaminB1: data.vitaminB1, vitaminB2: data.vitaminB2, vitaminB3: data.vitaminB3, vitaminB5: data.vitaminB5, vitaminB6: data.vitaminB6, vitaminE: data.vitaminE, vitaminK: data.vitaminK)
        self.availableServings.insert(scanned, at: 0)
        self.selectedServingID = scanned.id
        syncEditableFieldsFromSelectedServing()
    }

    private func logAdjustedFood() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let n = adjustedNutrients

        let rawItemToLog = FoodItem(
            id: isLoggedItem ? initialFoodItem.id : UUID().uuidString,
            name: trimmedFoodName, calories: n.calories, protein: n.protein, carbs: n.carbs, fats: n.fats,
            saturatedFat: n.saturatedFat, polyunsaturatedFat: n.polyunsaturatedFat, monounsaturatedFat: n.monounsaturatedFat, fiber: n.fiber,
            servingSize: n.servingDescription, servingWeight: n.servingWeightGrams, timestamp: isLoggedItem ? initialFoodItem.timestamp : Date(),
            sourceMetadata: initialFoodItem.sourceMetadata ?? .userEntered(),
            calcium: n.calcium, iron: n.iron, potassium: n.potassium, sodium: n.sodium,
            vitaminA: n.vitaminA, vitaminC: n.vitaminC, vitaminD: n.vitaminD, vitaminB12: n.vitaminB12, folate: n.folate,
            magnesium: n.magnesium, phosphorus: n.phosphorus, zinc: n.zinc, copper: n.copper, manganese: n.manganese, selenium: n.selenium,
            vitaminB1: n.vitaminB1, vitaminB2: n.vitaminB2, vitaminB3: n.vitaminB3, vitaminB5: n.vitaminB5, vitaminB6: n.vitaminB6, vitaminE: n.vitaminE, vitaminK: n.vitaminK
        )
        let itemToLog = rawItemToLog
            .normalizedForEstimatedSource(source)
            .markedUserConfirmed(sourceType: .manual)

        if let updateHandler = onUpdate {
            updateHandler(itemToLog)
        } else if isLoggedItem {
            dailyLogService.updateFoodInCurrentLog(for: userID, updatedFoodItem: itemToLog)
        } else if let targetMealName {
            dailyLogService.addFoodToLog(
                for: userID,
                date: date,
                mealName: targetMealName,
                foodItem: itemToLog,
                source: source
            )
        } else {
            dailyLogService.addFoodToCurrentLog(for: userID, foodItem: itemToLog, source: source)
        }
        rememberManualBarcodeCorrectionIfNeeded(itemToLog, userID: userID)
        HapticManager.instance.feedback(.medium)
        onLogUpdated()
        dismiss()
    }

    private func rememberManualBarcodeCorrectionIfNeeded(_ foodItem: FoodItem, userID: String) {
        guard isBarcodeCorrectionFlow,
              let correctionBarcode else {
            return
        }

        var correction = foodItem.savedAsCustomFood(
            barcode: correctionBarcode,
            originalItem: initialFoodItem
        )
        if hasScannedNutritionLabel {
            correction.sourceMetadata?.notes = "Created from a scanned nutrition label after a barcode lookup miss."
        }
        dailyLogService.customFoodStore.saveCustomFood(for: userID, foodItem: correction) { success in
            Task { @MainActor in
                let parameters: [String: Any] = [
                    "barcode_length": correctionBarcode.count,
                    "used_label_scan": hasScannedNutritionLabel,
                    "community_flag_enabled": communityCorrectionSharingEnabled
                ]
                if success {
                    DIContainer.shared.analyticsManager.barcodeMissRecovery(.manualFoodCreated(correction))
                    DIContainer.shared.analyticsManager?.logEvent(
                        "barcode_label_correction_saved",
                        parameters: parameters
                    )
                    contributeToCommunityPoolIfEligible(correction)
                } else {
                    DIContainer.shared.analyticsManager?.logEvent(
                        "barcode_label_correction_save_failed",
                        parameters: parameters
                    )
                }
            }
        }
    }

    /// Shares a saved barcode correction with the community pool when the feature flag is
    /// enabled and the item passes local sanity checks. Best-effort: failed writes stay silent.
    private func contributeToCommunityPoolIfEligible(_ item: FoodItem) {
        guard let barcode = item.sourceMetadata?.barcode else { return }
        let flagEnabled = communityCorrectionSharingEnabled
        let decision = CommunityBarcodeRules.contributionDecision(item, barcode: barcode, flagEnabled: flagEnabled)
        DIContainer.shared.analyticsManager?.logEvent("community_barcode_contribution_evaluated", parameters: [
            "eligible": decision.isEligible,
            "reason": decision.reason,
            "flag_enabled": flagEnabled,
            "source": source
        ])
        guard decision.isEligible, let store = DIContainer.shared.communityBarcodeStore else { return }
        Task {
            await store.contribute(item, barcode: barcode)
        }
    }

    // Save/Unsave Custom Food Logic
    private func toggleSavedState() {
        if isSavedAsCustom { unsaveCustomFood() } else { saveAsCustomFood() }
    }
    private func saveAsCustomFood() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let n = adjustedNutrients
        let rawItemToSave = FoodItem(
            id: customFoodForAction?.id ?? (
                initialFoodItem.sourceMetadata?.sourceType == .custom
                    ? initialFoodItem.id
                    : UUID().uuidString
            ),
            name: trimmedFoodName,
            calories: n.calories,
            protein: n.protein,
            carbs: n.carbs,
            fats: n.fats,
            saturatedFat: n.saturatedFat,
            polyunsaturatedFat: n.polyunsaturatedFat,
            monounsaturatedFat: n.monounsaturatedFat,
            fiber: n.fiber,
            servingSize: n.servingDescription,
            servingWeight: n.servingWeightGrams,
            timestamp: nil,
            sourceMetadata: initialFoodItem.sourceMetadata,
            calcium: n.calcium,
            iron: n.iron,
            potassium: n.potassium,
            sodium: n.sodium,
            vitaminA: n.vitaminA,
            vitaminC: n.vitaminC,
            vitaminD: n.vitaminD,
            vitaminB12: n.vitaminB12,
            folate: n.folate,
            magnesium: n.magnesium,
            phosphorus: n.phosphorus,
            zinc: n.zinc,
            copper: n.copper,
            manganese: n.manganese,
            selenium: n.selenium,
            vitaminB1: n.vitaminB1,
            vitaminB2: n.vitaminB2,
            vitaminB3: n.vitaminB3,
            vitaminB5: n.vitaminB5,
            vitaminB6: n.vitaminB6,
            vitaminE: n.vitaminE,
            vitaminK: n.vitaminK
        )
        var itemToSave = rawItemToSave
            .normalizedForEstimatedSource(source)
            .savedAsCustomFood(
                barcode: initialFoodItem.sourceMetadata?.barcode,
                originalItem: initialFoodItem
            )
        if hasScannedNutritionLabel {
            itemToSave.sourceMetadata?.notes = "Created from a scanned nutrition label."
        }
        dailyLogService.customFoodStore.saveCustomFood(for: userID, foodItem: itemToSave) { success in
            if success {
                isSavedAsCustom = true
                customFoodForAction = itemToSave
                bannerService.showBanner(title: "Saved", message: "Saved to My Foods")
                contributeToCommunityPoolIfEligible(itemToSave)
            }
        }
    }
    private func unsaveCustomFood() {
        guard let userID = DIContainer.shared.authService.currentUserID, let id = customFoodForAction?.id else { return }
        dailyLogService.customFoodStore.deleteCustomFood(for: userID, foodItemID: id) { success in
            if success { isSavedAsCustom = false; bannerService.showBanner(title: "Removed", message: "Removed from My Foods") }
        }
    }
    private func checkIfSaved() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.customFoodStore.fetchMyFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                if case .success(let items) = result, let match = items.first(where: { $0.name == foodName }) {
                    isSavedAsCustom = true; customFoodForAction = match
                }
            }
        }
    }

    private func buttonText() -> String { onUpdate != nil ? "Update item" : (isLoggedItem ? "Update logged item" : "Add to log") }
    private func navigationTitleText() -> String { onUpdate != nil ? "Edit item" : (isLoggedItem ? "Edit logged item" : "Log food") }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

    @ViewBuilder private func nutrientRow(label: String, value: Double?, unit: String, specifier: String = "%.1f") -> some View {
        if let v = value, v > 0 { HStack { Text(label).appFont(size: 15); Spacer(); Text("\(v, specifier: specifier) \(unit)").appFont(size: 15).foregroundColor(.secondary) } }
    }
    @ViewBuilder private func nutrientRow(label: String, value: String) -> some View {
        HStack { Text(label).appFont(size: 15); Spacer(); Text(value).appFont(size: 15).foregroundColor(.secondary) }
    }
}

private struct ManualFoodIdentityCard: View {
    @Binding var foodName: String

    private var displayEmoji: String {
        let trimmed = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodEmojiMapper.getEmoji(for: trimmed.isEmpty ? "food" : trimmed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(displayEmoji)
                .appFont(size: 34)
                .frame(width: 62, height: 62)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text("Food name")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                TextField("Chicken bowl, protein bar, oatmeal", text: $foodName)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
            }
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ManualBarcodeCorrectionCard: View {
    let barcode: String
    let hasScannedLabel: Bool
    let communitySharingEnabled: Bool
    let scanAction: () -> Void

    private var barcodeDisplay: String {
        guard barcode.count > 4 else { return barcode }
        return "ending \(barcode.suffix(4))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Barcode correction")
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Log this food once and future scans for barcode \(barcodeDisplay) will use your saved label.")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label(hasScannedLabel ? "Label scanned" : "Label not scanned", systemImage: hasScannedLabel ? "checkmark.seal.fill" : "camera.viewfinder")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(hasScannedLabel ? .accentPositive : .orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background((hasScannedLabel ? Color.accentPositive : Color.orange).opacity(0.10), in: Capsule())

                if communitySharingEnabled {
                    Label("Eligible fixes may help future scans", systemImage: "person.2.fill")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(.accentProtein)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.accentProtein.opacity(0.10), in: Capsule())
                }
            }

            Button(action: scanAction) {
                Label(hasScannedLabel ? "Scan label again" : "Scan nutrition label", systemImage: "camera.fill")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.brandPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ManualFoodMacroInputGrid: View {
    @Binding var caloriesText: String
    @Binding var proteinText: String
    @Binding var carbsText: String
    @Binding var fatsText: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ManualFoodTextInput(title: "Calories", placeholder: "0", text: $caloriesText, keyboardType: .decimalPad, icon: "flame.fill", color: .orange, unit: "cal")
            ManualFoodTextInput(title: "Protein", placeholder: "0", text: $proteinText, keyboardType: .decimalPad, icon: "bolt.fill", color: .accentProtein, unit: "g")
            ManualFoodTextInput(title: "Carbs", placeholder: "0", text: $carbsText, keyboardType: .decimalPad, icon: "leaf.fill", color: .accentCarbs, unit: "g")
            ManualFoodTextInput(title: "Total fat", placeholder: "0", text: $fatsText, keyboardType: .decimalPad, icon: "drop.fill", color: .accentFats, unit: "g")
        }
    }
}

private struct ManualFoodTextInput: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let icon: String
    let color: Color
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())

                Spacer()

                if let unit {
                    Text(unit)
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .submitLabel(.next)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ManualFoodPreviewCard: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let servingDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview")
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(servingDescription)
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(2)
                }

                Spacer()

                Text(Int(calories.rounded()).formatted())
                    .appFont(size: 30, weight: .bold)
                    .foregroundColor(.orange)
                Text("cal")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }

            HStack(spacing: 8) {
                ManualFoodMacroPill(label: "P", value: protein, color: .accentProtein)
                ManualFoodMacroPill(label: "C", value: carbs, color: .accentCarbs)
                ManualFoodMacroPill(label: "F", value: fats, color: .accentFats)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ManualFoodMacroPill: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .appFont(size: 12, weight: .bold)
            Text("\(Int(value.rounded()).formatted()) g")
                .appFont(size: 12, weight: .semibold)
        }
        .foregroundColor(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct ManualFoodLoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.blue)

            Text("Loading serving details")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ManualFoodNoticeCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.orange)
                .frame(width: 34, height: 34)
                .background(Color.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text(message)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ManualFoodActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isEnabled)
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
