import SwiftUI
import MyFitPlateCore

struct QuickAddMacrosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dailyLogService: DailyLogService

    let selectedMealType: String
    let targetDate: Date
    @State private var trainingFuelTarget: TrainingFuelTarget?

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fats: String = ""

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var foodID = UUID().uuidString
    @State private var numberLocaleIdentifier = Locale.current.identifier
    @State private var unreadableDraft = false
    @StateObject private var saveQueue: QuickFoodLogQueue
    private let ownerID: String?
    private let draftStore = EditorDraftStore()
    private let draftScope = "quick-macro-input"

    init(selectedMealType: String, targetDate: Date, trainingFuelTarget: TrainingFuelTarget? = nil) {
        let owner = DIContainer.shared.authService.currentUserID
        ownerID = owner
        let store = EditorDraftStore()
        let queue = QuickFoodLogQueue(userID: owner ?? "", store: store, scope: "quick-macro-submit")
        _saveQueue = StateObject(wrappedValue: queue)
        var restored: QuickMacroDraft?
        if let owner {
            do { restored = try store.load(QuickMacroDraft.self, userID: owner, scope: "quick-macro-input")?.value } catch {
                _unreadableDraft = State(initialValue: true); _errorMessage = State(initialValue: "Your previous quick entry could not be opened. It has been kept unchanged.")
            }
        }
        let restoredTarget: TrainingFuelTarget?
        if let operation = queue.operations.first { restoredTarget = operation.draft.trainingFuelTarget } else if let restored { restoredTarget = restored.trainingFuelTarget } else { restoredTarget = trainingFuelTarget }
        _trainingFuelTarget = State(initialValue: restoredTarget)
        self.selectedMealType = queue.operations.first?.draft.mealName ?? restored?.mealName ?? selectedMealType
        self.targetDate = queue.operations.first?.draft.date ?? restored?.date ?? targetDate
        if let restored {
            _calories = State(initialValue: restored.calories)
            _protein = State(initialValue: restored.protein)
            _carbs = State(initialValue: restored.carbs)
            _fats = State(initialValue: restored.fats)
            _foodID = State(initialValue: restored.foodID)
            _numberLocaleIdentifier = State(initialValue: restored.numberLocaleIdentifier ?? Locale.current.identifier)
        } else if let pending = queue.operations.first, let food = pending.draft.entries.first?.food {
            _calories = State(initialValue: food.calories.formatted(.number.grouping(.never)))
            _protein = State(initialValue: food.protein.formatted(.number.grouping(.never)))
            _carbs = State(initialValue: food.carbs.formatted(.number.grouping(.never)))
            _fats = State(initialValue: food.fats.formatted(.number.grouping(.never)))
            _foodID = State(initialValue: pending.sourceFoodID)
        }

        #if DEBUG
        if ScreenshotDemoMode.isEnabled,
           ScreenshotDemoData.requestedScreen == "quick-add-macros", restored == nil, queue.operations.isEmpty {
            _calories = State(initialValue: "485")
            _protein = State(initialValue: "38")
            _carbs = State(initialValue: "52")
            _fats = State(initialValue: "14")
        }
        #endif
    }

    private var parsedCalories: Double { parsed(calories) }
    private var parsedProtein: Double { parsed(protein) }
    private var parsedCarbs: Double { parsed(carbs) }
    private var parsedFats: Double { parsed(fats) }

    private var finalCalories: Double {
        inputDraft.food?.calories ?? 0
    }

    private var hasMacroEntry: Bool {
        parsedProtein > 0 || parsedCarbs > 0 || parsedFats > 0
    }

    private var hasEntry: Bool {
        inputDraft.food != nil || !saveQueue.operations.isEmpty
    }

    private var inputColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                        if let target = trainingFuelTarget {
                            TrainingFuelTargetContextView(target: target, onDismiss: isSaving || saveQueue.operations.first?.draft.isSubmitted == true ? nil : {
                                if let operation = saveQueue.operations.first, !saveQueue.removeFuelContext(id: operation.id) { return }
                                trainingFuelTarget = nil; _ = checkpointInput()
                            })
                        }

                    AppScreenHeader(
                        eyebrow: selectedMealType,
                        title: "Quick Add",
                        subtitle: "Enter the nutrition you already know. Leave calories blank to calculate them from macros."
                    )
                    .accessibilityIdentifier("quick_add_header")

                    nutritionSection.disabled(isSaving || !saveQueue.operations.isEmpty)
                    summarySection
                    Text("\(selectedMealType) · \(targetDate.formatted(date: .abbreviated, time: .omitted))")
                        .appTextRole(.secondary).accessibilityIdentifier("quick_add_destination")
                    if !saveQueue.operations.isEmpty {
                        Text("This submitted amount is kept for safe retry.").appTextRole(.secondary)
                    }

                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSaving)
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.compact) {
                    if let message = errorMessage ?? validationMessage {
                        Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("quick_add_error")
                    }
                Button(action: saveMacros) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label(saveQueue.operations.isEmpty ? "Add to \(selectedMealType)" : "Retry saving", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(isSaving || !hasEntry || unreadableDraft)
                .accessibilityIdentifier("quick_add_action")
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
            }
        }
        .accessibilityIdentifier("quick_add_macros")
        .interactiveDismissDisabled(isSaving)
        .onChange(of: [calories, protein, carbs, fats]) { _, _ in _ = checkpointInput() }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Nutrition",
                subtitle: "Use values for the full amount you want to log."
            )

            LazyVGrid(columns: inputColumns, alignment: .leading, spacing: AppSpacing.row) {
                QuickMacroInputField(
                    title: "Calories",
                    unit: "cal",
                    value: $calories,
                    accent: AppPalette.energy,
                    accessibilityIdentifier: "quick_add_calories"
                )
                QuickMacroInputField(
                    title: "Protein",
                    unit: "g",
                    value: $protein,
                    accent: .accentProtein,
                    accessibilityIdentifier: "quick_add_protein"
                )
                QuickMacroInputField(
                    title: "Carbs",
                    unit: "g",
                    value: $carbs,
                    accent: .accentCarbs,
                    accessibilityIdentifier: "quick_add_carbs"
                )
                QuickMacroInputField(
                    title: "Fat",
                    unit: "g",
                    value: $fats,
                    accent: .accentFats,
                    accessibilityIdentifier: "quick_add_fat"
                )
            }
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick_add_nutrition")
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Entry Summary",
                subtitle: parsedCalories > 0
                    ? "Using the calorie value you entered."
                    : hasMacroEntry
                        ? "Calories are calculated from protein, carbs, and fat."
                        : "Your entry updates as you add nutrition values."
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Calories",
                    value: "\(finalCalories.formatted(.number.precision(.fractionLength(0)))) cal",
                    accent: AppPalette.energy
                ),
                AppMetricItem(
                    label: "Protein",
                    value: "\(formatted(parsedProtein)) g",
                    accent: .accentProtein
                ),
                AppMetricItem(
                    label: "Carbs",
                    value: "\(formatted(parsedCarbs)) g",
                    accent: .accentCarbs
                ),
                AppMetricItem(
                    label: "Fat",
                    value: "\(formatted(parsedFats)) g",
                    accent: .accentFats
                )
            ])
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick_add_summary")
    }

    private var inputDraft: QuickMacroDraft {
        var draft = QuickMacroDraft(date: targetDate, mealName: selectedMealType, foodID: foodID)
        draft.calories = calories
        draft.protein = protein
        draft.carbs = carbs
        draft.fats = fats
        draft.numberLocaleIdentifier = numberLocaleIdentifier
        draft.trainingFuelTarget = trainingFuelTarget
        return draft
    }

    private var validationMessage: String? {
        guard saveQueue.operations.isEmpty, [calories, protein, carbs, fats].contains(where: { !$0.isEmpty }), inputDraft.food == nil else { return nil }
        return "Enter positive nutrition amounts using your device's number format. Leave calories blank to calculate them from macros."
    }

    @discardableResult
    private func checkpointInput() -> Bool {
        guard !unreadableDraft, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return false }
        if !saveQueue.operations.isEmpty { return true }
        do {
            try draftStore.save(inputDraft, userID: ownerID, scope: draftScope)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not keep this entry on the device. Your input is still here; retry."
            return false
        }
    }

    private func saveMacros() {
        guard !isSaving, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else {
            errorMessage = "Sign back into the account that opened this entry."
            return
        }
        guard checkpointInput() else { return }
        var pending = saveQueue.operations.first
        if pending == nil, let food = inputDraft.food {
            pending = saveQueue.begin(food: food, date: targetDate, mealName: selectedMealType, source: "quick_macros", needsHydration: false, trainingFuelTarget: trainingFuelTarget)
        }
        guard let pending else {
            errorMessage = saveQueue.errorMessage ?? "Enter valid nonnegative nutrition amounts using your device's number format."
            return
        }
        isSaving = true
        saveQueue.save(id: pending.id, using: dailyLogService) { accepted in
            isSaving = false
            guard DIContainer.shared.authService.currentUserID == ownerID else {
                errorMessage = "This entry is kept with its original account. Sign back in to finish."
                return
            }
            guard accepted else {
                errorMessage = saveQueue.errorMessage ?? "Your entry is kept. Retry saving."
                return
            }
            do {
                // Keep the accepted operation until both checkpoints clear. If either
                // cleanup fails, reopening reuses its accepted receipt and food ID.
                try draftStore.remove(userID: ownerID, scope: draftScope)
                guard saveQueue.finish(id: pending.id) else {
                    errorMessage = "Your entry was saved. Retry to clear its receipt without adding it twice."
                    return
                }
                dismiss()
            } catch { errorMessage = "Your entry was saved. Retry to finish clearing the draft; it will not be added twice." }
        }
    }

    private func parsed(_ value: String) -> Double {
        QuickMacroDraft.number(value, locale: Locale(identifier: numberLocaleIdentifier)) ?? 0
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value == floor(value) ? 0 : 1)))
    }
}

private struct QuickMacroInputField: View {
    let title: String
    let unit: String
    @Binding var value: String
    let accent: Color
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(title)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                TextField("0", text: $value)
                    .keyboardType(.decimalPad)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(accessibilityIdentifier)

                Text(unit)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.row)
            .frame(minHeight: 48)
            .background(
                AppPalette.canvas,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 0.5)
            }
        }
    }
}

struct MenuScannerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var recommendedMeals: [FoodItem] = []
    @State private var errorMessage: String?
    @State private var remainingCaloriesSnapshot: Double = 0
    
    private let aiModel = MLImageModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if isProcessing {
                    loadingState
                } else if !recommendedMeals.isEmpty {
                    resultsState
                } else {
                    VStack(spacing: 24) {
                        Image(systemName: "menucard")
                            .appFont(size: 60)
                            .foregroundColor(AppPalette.effort)
                        
                        Text("Menu matchmaker")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Snap a photo of any restaurant menu. We'll find the best options that fit your remaining macros.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 32)
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundColor(AppPalette.critical)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(AppPalette.critical.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            showingCamera = true
                        }) {
                            Label("Scan menu", systemImage: "camera")
                                .font(.headline)
                                .foregroundColor(AppPalette.onBrand)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.brandPrimary)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal, 32)
                        .onChange(of: capturedImage) { _, newValue in
                            if let uiImage = newValue {
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
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Menu scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(AppPalette.effort)
            Text("Reading the menu and matching your macros")
                .appFont(size: 15, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsState: some View {
        let remaining = remainingCaloriesSnapshot
        let fittingCount = recommendedMeals.filter { remaining > 0 && $0.calories <= remaining }.count
        return ScrollView {
            VStack(spacing: 12) {
                if remaining > 0 && fittingCount == 0 {
                    menuBudgetBanner(remaining: remaining)
                }

                HStack {
                    Text(remaining > 0
                         ? "5 picks · \(fittingCount.formatted()) fit your remaining \(Int(remaining).formatted()) cal"
                         : "Top picks from this menu")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Spacer()
                }
                .padding(.horizontal, 4)

                ForEach(recommendedMeals) { meal in
                    Button { logMeal(meal) } label: {
                        menuMealCard(meal, fitsBudget: remaining > 0 && meal.calories <= remaining)
                    }
                    .buttonStyle(.plain)
                }

                Text("AI estimates. Double-check before logging.")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding()
        }
    }

    private func menuBudgetBanner(remaining: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 14, weight: .bold)
                .foregroundColor(AppPalette.caution)
                .frame(width: 30, height: 30)
                .background(AppPalette.caution.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("All picks exceed your remaining \(Int(remaining).formatted()) cal")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("These are the closest options on the menu. Log mindfully or save room elsewhere.")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppPalette.caution.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func menuMealCard(_ meal: FoodItem, fitsBudget: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(AppPalette.effort)
                .frame(width: 44, height: 44)
                .background(AppPalette.effort.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(meal.name)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                HStack(spacing: 9) {
                    Text("\(Int(meal.calories).formatted()) cal").foregroundColor(AppPalette.energy)
                    Text("P \(Int(meal.protein).formatted()) g").foregroundColor(.accentProtein)
                    Text("C \(Int(meal.carbs).formatted()) g").foregroundColor(.accentCarbs)
                    Text("F \(Int(meal.fats).formatted()) g").foregroundColor(.accentFats)
                }
                .appFont(size: 12, weight: .semibold)

                if fitsBudget {
                    Text("Fits your budget")
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(.accentPositive)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentPositive.opacity(0.14), in: Capsule())
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "plus.circle.fill")
                .appFont(size: 26)
                .foregroundColor(AppPalette.brandText)
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        let remainingCals = max(0, (goalSettings.calories ?? 2000) - (dailyLogService.currentDailyLog?.totalCalories() ?? 0))
        let remainingPro = max(0, goalSettings.protein - (dailyLogService.currentDailyLog?.totalMacros().protein ?? 0))
        remainingCaloriesSnapshot = remainingCals
        
        aiModel.recommendMenuMeals(from: image, remainingCalories: remainingCals, remainingProtein: remainingPro) { result in
            isProcessing = false
            switch result {
            case .success(let meals):
                if meals.isEmpty {
                    errorMessage = "We couldn't find any good matches on this menu."
                } else {
                    recommendedMeals = Array(meals.prefix(5))
                }
            case .failure(let error):
                errorMessage = "Couldn't analyze menu: \(error.localizedDescription)"
            }
        }
    }
    
    private func logMeal(_ meal: FoodItem) {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        dailyLogService.addFoodToCurrentLog(for: userID, foodItem: meal, source: "MenuMatchmaker")
        dismiss()
    }
}
