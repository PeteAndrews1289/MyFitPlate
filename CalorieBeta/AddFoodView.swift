import SwiftUI
import FirebaseAuth

struct AddFoodView: View {
    // New arguments for Smart Serving logic
    var initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    var date: Date = Date()
    var source: String = "manual"
    var targetMealName: String?
    var onLogUpdated: () -> Void
    var onUpdate: ((FoodItem) -> Void)? = nil

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
    @State private var fiberText: String
    @State private var servingSizeText: String
    @State private var servingWeightText: String
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
        return Double(caloriesText) != nil || Double(proteinText) != nil || Double(carbsText) != nil || Double(fatsText) != nil
    }

    private func doubleValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var editableBaseServingOption: ServingSizeOption {
        let fallback = selectedServingOption
        let servingDescription = servingSizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (fallback?.description ?? "1 serving")
            : servingSizeText.trimmingCharacters(in: .whitespacesAndNewlines)

        return ServingSizeOption(
            description: servingDescription,
            servingWeightGrams: doubleValue(servingWeightText) ?? fallback?.servingWeightGrams ?? (initialFoodItem.servingWeight > 0 ? initialFoodItem.servingWeight : nil),
            calories: doubleValue(caloriesText) ?? fallback?.calories ?? initialFoodItem.calories,
            protein: doubleValue(proteinText) ?? fallback?.protein ?? initialFoodItem.protein,
            carbs: doubleValue(carbsText) ?? fallback?.carbs ?? initialFoodItem.carbs,
            fats: doubleValue(fatsText) ?? fallback?.fats ?? initialFoodItem.fats,
            saturatedFat: fallback?.saturatedFat ?? initialFoodItem.saturatedFat,
            polyunsaturatedFat: fallback?.polyunsaturatedFat ?? initialFoodItem.polyunsaturatedFat,
            monounsaturatedFat: fallback?.monounsaturatedFat ?? initialFoodItem.monounsaturatedFat,
            fiber: doubleValue(fiberText) ?? fallback?.fiber ?? initialFoodItem.fiber,
            calcium: fallback?.calcium ?? initialFoodItem.calcium,
            iron: fallback?.iron ?? initialFoodItem.iron,
            potassium: fallback?.potassium ?? initialFoodItem.potassium,
            sodium: fallback?.sodium ?? initialFoodItem.sodium,
            vitaminA: fallback?.vitaminA ?? initialFoodItem.vitaminA,
            vitaminC: fallback?.vitaminC ?? initialFoodItem.vitaminC,
            vitaminD: fallback?.vitaminD ?? initialFoodItem.vitaminD,
            vitaminB12: fallback?.vitaminB12 ?? initialFoodItem.vitaminB12,
            folate: fallback?.folate ?? initialFoodItem.folate,
            magnesium: fallback?.magnesium ?? initialFoodItem.magnesium,
            phosphorus: fallback?.phosphorus ?? initialFoodItem.phosphorus,
            zinc: fallback?.zinc ?? initialFoodItem.zinc,
            copper: fallback?.copper ?? initialFoodItem.copper,
            manganese: fallback?.manganese ?? initialFoodItem.manganese,
            selenium: fallback?.selenium ?? initialFoodItem.selenium,
            vitaminB1: fallback?.vitaminB1 ?? initialFoodItem.vitaminB1,
            vitaminB2: fallback?.vitaminB2 ?? initialFoodItem.vitaminB2,
            vitaminB3: fallback?.vitaminB3 ?? initialFoodItem.vitaminB3,
            vitaminB5: fallback?.vitaminB5 ?? initialFoodItem.vitaminB5,
            vitaminB6: fallback?.vitaminB6 ?? initialFoodItem.vitaminB6,
            vitaminE: fallback?.vitaminE ?? initialFoodItem.vitaminE,
            vitaminK: fallback?.vitaminK ?? initialFoodItem.vitaminK
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
            fats: nutrients.fats
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
        return "Macros imply \(macroCalories) cal, so this estimate will log as \(macroCalories) cal instead of \(loggedCalories)."
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        ManualFoodIdentityCard(foodName: $foodName)

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
                        if consistencyStatus.hasMeaningfulMismatch {
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
                        .foregroundColor(isSavedAsCustom ? .yellow : .brandPrimary)
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
                imageModel.parseNutritionLabel(from: image) { result in
                    isProcessingLabel = false
                    switch result {
                    case .success(let nutrition):
                        handleScannedNutrition(nutrition)
                        bannerService.showBanner(title: "Success", message: "Nutrition label scanned successfully", iconName: "checkmark.circle.fill", iconColor: .accentPositive)
                    case .failure(let error):
                        bannerService.showBanner(title: "Scan Error", message: "Couldn't read label: \(error.localizedDescription)", iconName: "exclamationmark.triangle.fill", iconColor: .red)
                    }
                }
            }
        }
    }

    @ViewBuilder private var servingControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Serving")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                ManualFoodTextInput(
                    title: "Quantity",
                    placeholder: "1",
                    text: $quantity,
                    keyboardType: .decimalPad,
                    icon: "number",
                    color: .brandPrimary
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
                placeholder: "1 cup, 1 bar, 100 g...",
                text: $servingSizeText,
                keyboardType: .default,
                icon: "fork.knife",
                color: .brandPrimary
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
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.brandPrimary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Detected serving options")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(UIColor.secondaryLabel))

                            Text(selectedServingOption?.description ?? "Choose serving")
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
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var detailControlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            ManualFoodTextInput(
                title: "Fiber",
                placeholder: "optional",
                text: $fiberText,
                keyboardType: .decimalPad,
                icon: "leaf.fill",
                color: .accentPositive
            )

            Button {
                showingImagePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.brandPrimary)
                        .frame(width: 42, height: 42)
                        .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scan nutrition label")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text("Use a label photo to fill the numbers faster.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
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
        Button { showingImagePicker = true } label: {
            Label("Scan Nutrition Label", systemImage: "camera.fill")
        }
        .tint(.brandPrimary)
        .padding(.top, 5)
    }

    private func syncEditableFieldsFromSelectedServing() {
        guard let selectedServingOption else { return }
        servingSizeText = selectedServingOption.description
        servingWeightText = Self.fieldText(for: selectedServingOption.servingWeightGrams)
        caloriesText = Self.fieldText(for: selectedServingOption.calories)
        proteinText = Self.fieldText(for: selectedServingOption.protein)
        carbsText = Self.fieldText(for: selectedServingOption.carbs)
        fatsText = Self.fieldText(for: selectedServingOption.fats)
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

                    var matchedServing: ServingSizeOption? = nil
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
        self.foodName = data.foodName
        let scanned = ServingSizeOption(description: "Scanned Label", servingWeightGrams: nil, calories: data.calories, protein: data.protein, carbs: data.carbs, fats: data.fats, saturatedFat: data.saturatedFat, polyunsaturatedFat: data.polyunsaturatedFat, monounsaturatedFat: data.monounsaturatedFat, fiber: data.fiber, calcium: data.calcium, iron: data.iron, potassium: data.potassium, sodium: data.sodium, vitaminA: data.vitaminA, vitaminC: data.vitaminC, vitaminD: data.vitaminD, vitaminB12: data.vitaminB12, folate: data.folate, magnesium: data.magnesium, phosphorus: data.phosphorus, zinc: data.zinc, copper: data.copper, manganese: data.manganese, selenium: data.selenium, vitaminB1: data.vitaminB1, vitaminB2: data.vitaminB2, vitaminB3: data.vitaminB3, vitaminB5: data.vitaminB5, vitaminB6: data.vitaminB6, vitaminE: data.vitaminE, vitaminK: data.vitaminK)
        self.availableServings.insert(scanned, at: 0)
        self.selectedServingID = scanned.id
        syncEditableFieldsFromSelectedServing()
    }

    private func logAdjustedFood() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let n = adjustedNutrients

        let rawItemToLog = FoodItem(
            id: isLoggedItem ? initialFoodItem.id : UUID().uuidString,
            name: trimmedFoodName, calories: n.calories, protein: n.protein, carbs: n.carbs, fats: n.fats,
            saturatedFat: n.saturatedFat, polyunsaturatedFat: n.polyunsaturatedFat, monounsaturatedFat: n.monounsaturatedFat, fiber: n.fiber,
            servingSize: n.servingDescription, servingWeight: n.servingWeightGrams, timestamp: isLoggedItem ? initialFoodItem.timestamp : Date(),
            calcium: n.calcium, iron: n.iron, potassium: n.potassium, sodium: n.sodium,
            vitaminA: n.vitaminA, vitaminC: n.vitaminC, vitaminD: n.vitaminD, vitaminB12: n.vitaminB12, folate: n.folate,
            magnesium: n.magnesium, phosphorus: n.phosphorus, zinc: n.zinc, copper: n.copper, manganese: n.manganese, selenium: n.selenium,
            vitaminB1: n.vitaminB1, vitaminB2: n.vitaminB2, vitaminB3: n.vitaminB3, vitaminB5: n.vitaminB5, vitaminB6: n.vitaminB6, vitaminE: n.vitaminE, vitaminK: n.vitaminK,
            quantityValue: n.quantityValue,
            servingUnit: n.servingUnit
        )
        let itemToLog = rawItemToLog.normalizedForEstimatedSource(source)

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
        onLogUpdated()
        dismiss()
    }

    // Save/Unsave Custom Food Logic
    private func toggleSavedState() {
        if isSavedAsCustom { unsaveCustomFood() } else { saveAsCustomFood() }
    }
    private func saveAsCustomFood() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let n = adjustedNutrients
        let rawItemToSave = FoodItem(
            id: customFoodForAction?.id ?? UUID().uuidString,
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
            vitaminK: n.vitaminK,
            quantityValue: n.quantityValue,
            servingUnit: n.servingUnit
        )
        let itemToSave = rawItemToSave.normalizedForEstimatedSource(source)
        dailyLogService.saveCustomFood(for: userID, foodItem: itemToSave) { success in
            if success {
                isSavedAsCustom = true
                customFoodForAction = itemToSave
                bannerService.showBanner(title: "Saved", message: "Saved to My Foods")
            }
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
            DispatchQueue.main.async {
                if case .success(let items) = result, let match = items.first(where: { $0.name == foodName }) {
                    isSavedAsCustom = true; customFoodForAction = match
                }
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

private struct ManualFoodIdentityCard: View {
    @Binding var foodName: String

    private var displayEmoji: String {
        let trimmed = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodEmojiMapper.getEmoji(for: trimmed.isEmpty ? "food" : trimmed)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(displayEmoji)
                .font(.system(size: 34))
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Food name")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(UIColor.secondaryLabel))

                TextField("Chicken bowl, protein bar, oatmeal...", text: $foodName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
            }
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            ManualFoodTextInput(title: "Fat", placeholder: "0", text: $fatsText, keyboardType: .decimalPad, icon: "drop.fill", color: .accentFats, unit: "g")
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
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())

                Spacer()

                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))

                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .font(.system(size: 22, weight: .bold))
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
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text(servingDescription)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(2)
                }

                Spacer()

                Text("\(Int(calories.rounded()))")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.orange)
                Text("cal")
                    .font(.system(size: 12, weight: .bold))
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
                .font(.system(size: 12, weight: .bold))
            Text("\(Int(value.rounded()))g")
                .font(.system(size: 12, weight: .semibold))
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
                .tint(.brandPrimary)

            Text("Loading serving details")
                .font(.system(size: 16, weight: .bold))
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
