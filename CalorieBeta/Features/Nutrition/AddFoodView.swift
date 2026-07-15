import MyFitPlateCore
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
    var showsSavedControl: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    init(initialFoodItem: FoodItem, dailyLog: Binding<DailyLog?>, date: Date = Date(), source: String = "manual", targetMealName: String? = nil, onLogUpdated: @escaping () -> Void, onUpdate: ((FoodItem) -> Void)? = nil, showsSavedControl: Bool = true) {
        self.initialFoodItem = initialFoodItem
        self._dailyLog = dailyLog
        self.date = date
        self.source = source
        self.targetMealName = targetMealName
        self.onLogUpdated = onLogUpdated
        self.onUpdate = onUpdate
        self.showsSavedControl = showsSavedControl

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
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
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
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.group)
                    .padding(.bottom, AppSpacing.group)
                }
                .scrollDismissesKeyboard(.interactively)

                ManualFoodActionBar(
                    title: buttonText(),
                    isEnabled: logButtonEnabled,
                    action: logAdjustedFood
                )
            }
            .accessibilityIdentifier("manual_food_editor")
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
            if showsSavedControl {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: toggleSavedState) {
                        Image(systemName: isSavedAsCustom ? "star.fill" : "star")
                            .foregroundColor(isSavedAsCustom ? AppPalette.achievement : AppPalette.brandText)
                    }
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .onChange(of: selectedServingID) {
            syncEditableFieldsFromSelectedServing()
        }
        .onAppear {
            setupInitialData()
            if showsSavedControl {
                checkIfSaved()
            }
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
                            iconColor: AppPalette.critical
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder private var servingControlsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Serving",
                subtitle: "Set the amount and description used for this entry."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: AppSpacing.group) {
                            quantityInput
                            weightInput
                        }
                    } else {
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            quantityInput
                            weightInput
                        }
                    }
                }

                ManualFoodTextInput(
                    title: "Serving description",
                    placeholder: "1 cup, 1 bar, 100 g",
                    text: $servingSizeText,
                    keyboardType: .default,
                    icon: "fork.knife",
                    color: AppPalette.brand
                )

                if availableServings.count > 1 {
                    Divider()

                    Menu {
                        ForEach(availableServings) { option in
                            Button(option.description) {
                                selectedServingID = option.id
                            }
                        }
                    } label: {
                        AppListRow(
                            icon: "list.bullet.rectangle",
                            iconColor: AppPalette.brand,
                            title: "Detected serving options",
                            subtitle: selectedServingOption?.description ?? "Choose serving"
                        ) {
                            Image(systemName: "chevron.up.chevron.down")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, -AppSpacing.group)
                        .padding(.vertical, -AppSpacing.compact)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Detected serving options")
                    .accessibilityValue(selectedServingOption?.description ?? "Choose serving")
                }
            }
            .appSurface(.quiet)
        }
    }

    private var quantityInput: some View {
        ManualFoodTextInput(
            title: "Quantity",
            placeholder: "1",
            text: $quantity,
            keyboardType: .decimalPad,
            icon: "number",
            color: AppPalette.brand
        )
    }

    private var weightInput: some View {
        ManualFoodTextInput(
            title: "Weight",
            placeholder: "grams",
            text: $servingWeightText,
            keyboardType: .decimalPad,
            icon: "scalemass.fill",
            color: AppPalette.brand,
            unit: "g"
        )
    }

    @ViewBuilder private var detailControlsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Nutrition details",
                subtitle: "Optional values improve totals and evidence coverage."
            )

            VStack(alignment: .leading, spacing: AppSpacing.group) {
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
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manual_food_fat_validation")
                }

                ManualFoodTextInput(
                    title: "Fiber",
                    placeholder: "optional",
                    text: $fiberText,
                    keyboardType: .decimalPad,
                    icon: "leaf.fill",
                    color: .accentPositive,
                    unit: "g"
                )

                Divider()

                Button(action: beginNutritionLabelScan) {
                    AppListRow(
                        icon: "camera.viewfinder",
                        iconColor: AppPalette.brand,
                        title: "Scan nutrition label",
                        subtitle: "Use a label photo to fill the numbers faster."
                    ) {
                        Image(systemName: "chevron.right")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, -AppSpacing.group)
                    .padding(.vertical, -AppSpacing.compact)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the camera to scan a nutrition label.")
            }
            .appSurface(.quiet)
        }
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
            id: isLoggedItem || onUpdate != nil ? initialFoodItem.id : UUID().uuidString,
            name: trimmedFoodName, calories: n.calories, protein: n.protein, carbs: n.carbs, fats: n.fats,
            saturatedFat: n.saturatedFat, polyunsaturatedFat: n.polyunsaturatedFat, monounsaturatedFat: n.monounsaturatedFat, fiber: n.fiber,
            servingSize: n.servingDescription,
            servingWeight: n.servingWeightGrams,
            timestamp: isLoggedItem || onUpdate != nil ? initialFoodItem.timestamp : Date(),
            sourceMetadata: initialFoodItem.sourceMetadata ?? .userEntered(),
            calcium: n.calcium, iron: n.iron, potassium: n.potassium, sodium: n.sodium,
            vitaminA: n.vitaminA, vitaminC: n.vitaminC, vitaminD: n.vitaminD, vitaminB12: n.vitaminB12, folate: n.folate,
            magnesium: n.magnesium, phosphorus: n.phosphorus, zinc: n.zinc, copper: n.copper, manganese: n.manganese, selenium: n.selenium,
            vitaminB1: n.vitaminB1, vitaminB2: n.vitaminB2, vitaminB3: n.vitaminB3, vitaminB5: n.vitaminB5, vitaminB6: n.vitaminB6, vitaminE: n.vitaminE, vitaminK: n.vitaminK
        )
        let normalizedItem = rawItemToLog.normalizedForEstimatedSource(source)
        let itemToLog = onUpdate == nil
            ? normalizedItem.markedUserConfirmed(sourceType: .manual)
            : normalizedItem.markedUserEdited(
                sourceType: initialFoodItem.sourceMetadata?.sourceType ?? .custom,
                originalItem: initialFoodItem
            )

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
        if onUpdate == nil {
            HapticManager.instance.feedback(.medium)
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayEmoji: String {
        let trimmed = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodEmojiMapper.getEmoji(for: trimmed.isEmpty ? "food" : trimmed)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    foodGlyph
                    nameField
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    foodGlyph
                    nameField
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.emphasized)
    }

    private var foodGlyph: some View {
        Text(displayEmoji)
            .font(.system(size: 32))
            .frame(width: 54, height: 54)
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .accessibilityHidden(true)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Food name")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            TextField("Chicken bowl, protein bar, oatmeal", text: $foodName, axis: .vertical)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .lineLimit(1...3)
                .accessibilityIdentifier("manual_food_name")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: "barcode.viewfinder")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.brandText)
                    .frame(width: 40, height: 40)
                    .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Barcode correction")
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text("Log this food once and future scans for barcode \(barcodeDisplay) will use your saved label.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Label(hasScannedLabel ? "Label scanned" : "Label not scanned", systemImage: hasScannedLabel ? "checkmark.seal.fill" : "camera.viewfinder")
                    .appTextRole(.caption)
                    .foregroundStyle(hasScannedLabel ? Color.accentPositiveText : AppPalette.caution)

                if communitySharingEnabled {
                    Label("Eligible fixes may help future scans", systemImage: "person.2.fill")
                        .appTextRole(.caption)
                        .foregroundStyle(Color.accentProtein)
                }
            }

            Button(action: scanAction) {
                Label(hasScannedLabel ? "Scan label again" : "Scan nutrition label", systemImage: "camera.fill")
            }
            .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .appSurface(.emphasized)
    }
}

private struct ManualFoodMacroInputGrid: View {
    @Binding var caloriesText: String
    @Binding var proteinText: String
    @Binding var carbsText: String
    @Binding var fatsText: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Nutrition",
                subtitle: "Enter values for one serving."
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.group) {
                ManualFoodTextInput(title: "Calories", placeholder: "0", text: $caloriesText, keyboardType: .decimalPad, icon: "flame.fill", color: AppPalette.energy, unit: "cal")
                ManualFoodTextInput(title: "Protein", placeholder: "0", text: $proteinText, keyboardType: .decimalPad, icon: "bolt.fill", color: .accentProtein, unit: "g")
                ManualFoodTextInput(title: "Carbs", placeholder: "0", text: $carbsText, keyboardType: .decimalPad, icon: "leaf.fill", color: .accentCarbs, unit: "g")
                ManualFoodTextInput(title: "Total fat", placeholder: "0", text: $fatsText, keyboardType: .decimalPad, icon: "drop.fill", color: .accentFats, unit: "g")
            }
            .appSurface(.quiet)
            .accessibilityIdentifier("manual_food_nutrition")
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            fieldLabel

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .submitLabel(.next)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 48)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 0.5)
                }
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var fieldLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                fieldIcon

                Text(accessibilityTitle)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
        } else {
            HStack(spacing: AppSpacing.compact) {
                fieldIcon

                Text(title)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)

                if let unit {
                    Spacer(minLength: 0)
                    Text(unit)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var fieldIcon: some View {
        Image(systemName: icon)
            .appTextRole(.secondary)
            .foregroundStyle(color)
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    private var accessibilityTitle: String {
        guard let unit else { return title }
        return "\(title) (\(unit))"
    }
}

private struct ManualFoodPreviewCard: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let servingDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Preview", subtitle: servingDescription)

            AppMetricStrip(items: [
                AppMetricItem(label: "Calories", value: "\(Int(calories.rounded()).formatted()) cal", accent: AppPalette.energy),
                AppMetricItem(label: "Protein", value: "\(Int(protein.rounded()).formatted()) g", accent: .accentProtein),
                AppMetricItem(label: "Carbs", value: "\(Int(carbs.rounded()).formatted()) g", accent: .accentCarbs),
                AppMetricItem(label: "Fat", value: "\(Int(fats.rounded()).formatted()) g", accent: .accentFats)
            ])
            .appSurface(.emphasized)
        }
    }
}

private struct ManualFoodLoadingCard: View {
    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(AppPalette.brand)

            Text("Loading serving details")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }
}

private struct ManualFoodNoticeCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.caution)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface(.quiet)
    }
}

private struct ManualFoodActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "checkmark")
        }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(!isEnabled)
            .accessibilityIdentifier("manual_food_primary_action")
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.row)
            .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
    }
}
