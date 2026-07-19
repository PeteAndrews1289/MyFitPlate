import SwiftUI

struct QuickAddMacrosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dailyLogService: DailyLogService

    let selectedMealType: String
    let targetDate: Date

    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fats: String = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(selectedMealType: String, targetDate: Date) {
        self.selectedMealType = selectedMealType
        self.targetDate = targetDate

        #if DEBUG
        if ScreenshotDemoMode.isEnabled,
           ScreenshotDemoData.requestedScreen == "quick-add-macros" {
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

    private var calculatedCalories: Double {
        parsedProtein * 4 + parsedCarbs * 4 + parsedFats * 9
    }

    private var finalCalories: Double {
        parsedCalories > 0 ? parsedCalories : calculatedCalories
    }

    private var hasMacroEntry: Bool {
        parsedProtein > 0 || parsedCarbs > 0 || parsedFats > 0
    }

    private var hasEntry: Bool {
        parsedCalories > 0 || hasMacroEntry
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
                    AppScreenHeader(
                        eyebrow: selectedMealType,
                        title: "Quick Add",
                        subtitle: "Enter the nutrition you already know. Leave calories blank to calculate them from macros."
                    )
                    .accessibilityIdentifier("quick_add_header")

                    nutritionSection
                    summarySection

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .appTextRole(.secondary)
                            .foregroundStyle(AppPalette.critical)
                            .fixedSize(horizontal: false, vertical: true)
                            .appSurface(.quiet)
                            .accessibilityIdentifier("quick_add_error")
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
                    Button("Cancel") { dismiss() }
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveMacros) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Add to \(selectedMealType)", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(isSaving || !hasEntry)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("quick_add_action")
            }
        }
        .accessibilityIdentifier("quick_add_macros")
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
                    value: "\(Int(finalCalories.rounded()).formatted()) cal",
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

    private func saveMacros() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            errorMessage = "You need to be signed in."
            return
        }

        let p = parsedProtein
        let c = parsedCarbs
        let f = parsedFats

        let newFood = FoodItem(
            id: UUID().uuidString,
            name: "Quick add macros",
            calories: finalCalories,
            protein: p,
            carbs: c,
            fats: f,
            servingSize: "1 custom entry",
            servingWeight: 1,
            timestamp: Date(),
            sourceMetadata: .userEntered(sourceName: "Quick add")
        )

        isSaving = true

        dailyLogService.fetchLog(for: userID, date: targetDate) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(var log):
                    if let index = log.meals.firstIndex(where: { $0.name == selectedMealType }) {
                        log.meals[index].foodItems.append(newFood)
                    } else {
                        let newMeal = Meal(name: selectedMealType, foodItems: [newFood])
                        log.meals.append(newMeal)
                    }
                    dailyLogService.updateDailyLog(for: userID, updatedLog: log) { success in
                        isSaving = false
                        if success {
                            dismiss()
                        } else {
                            errorMessage = "Failed to save macros."
                        }
                    }
                case .failure(let error):
                    isSaving = false
                    errorMessage = "Failed to fetch log: \(error.localizedDescription)"
                }
            }
        }
    }

    private func parsed(_ value: String) -> Double {
        max(Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0, 0)
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
