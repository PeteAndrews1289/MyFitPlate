import MyFitPlateCore
import SwiftUI

struct MealPlanSurveyView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedProteins: Set<String> = ["Chicken"]
    @State private var selectedCarbs: Set<String> = ["Rice"]
    @State private var selectedVeggies: Set<String> = ["Broccoli", "Bell peppers", "Onions"]
    @State private var selectedSnacks: Set<String> = ["Yogurt", "Fruit"]
    @State private var selectedCuisines: Set<String> = ["Any"]

    @State private var customProtein = ""
    @State private var customCarb = ""
    @State private var customVeggies = ""
    @State private var customSnack = ""

    @State private var isLoading = false
    @State private var showAlert = false
    @State private var didGeneratePlan = false
    @State private var alertMessage = ""
    @State private var currentStep: Int

    private static let steps = [
        MealPlanSurveyStep(
            title: "Choose Proteins",
            subtitle: "Select the foods you want the week built around.",
            icon: "fish.fill"
        ),
        MealPlanSurveyStep(
            title: "Choose Carbohydrates",
            subtitle: "Pick the staples that fit your usual meals.",
            icon: "takeoutbag.and.cup.and.straw.fill"
        ),
        MealPlanSurveyStep(
            title: "Choose Vegetables",
            subtitle: "Include the produce you will actually prepare.",
            icon: "carrot.fill"
        ),
        MealPlanSurveyStep(
            title: "Choose Snacks",
            subtitle: "Add reliable options for the gaps between meals.",
            icon: "fork.knife"
        ),
        MealPlanSurveyStep(
            title: "Choose Cuisines",
            subtitle: "Keep it broad or give the week a few directions.",
            icon: "globe.americas.fill"
        ),
        MealPlanSurveyStep(
            title: "Choose a Cooking Style",
            subtitle: "Set the amount of prep and day-to-day variety you prefer.",
            icon: "stove.fill"
        )
    ]

    init(initialStep: Int = 0) {
        let lastStep = Self.steps.count - 1
        _currentStep = State(initialValue: min(max(initialStep, 0), lastStep))
    }

    var body: some View {
        AppSheetScaffold(
            title: "Generate a Meal Plan",
            subtitle: "Six choices shape a practical seven-day plan.",
            dismiss: { dismiss() }
        ) {
            VStack(spacing: 0) {
                progressHeader
                Divider()
                stepScrollView
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(isLoading)
        .overlay {
            if isLoading {
                generationOverlay
            }
        }
        .alert(didGeneratePlan ? "Meal Plan Ready" : "Meal Plan", isPresented: $showAlert) {
            Button("OK") {
                if didGeneratePlan {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage)
        }
        .accessibilityIdentifier("meal_plan_survey_screen")
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                Text("Step \(currentStep + 1) of \(Self.steps.count)")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.brand)
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .tint(AppPalette.brand)
                .accessibilityLabel("Meal plan setup progress")
                .accessibilityValue("Step \(currentStep + 1) of \(Self.steps.count)")
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .accessibilityIdentifier("meal_plan_survey_progress")
    }

    private var stepScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                stepHeader
                stepContent
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.section)
            .padding(.bottom, AppSpacing.section)
            .id(currentStep)
            .transition(.opacity)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(AppMotion.visibility, value: currentStep)
    }

    private var stepHeader: some View {
        let step = Self.steps[currentStep]
        return AppScreenHeader(title: step.title, subtitle: step.subtitle) {
            Image(systemName: step.icon)
                .appFont(size: 20, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 44, height: 44)
                .background(
                    AppPalette.brand.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            SurveySelectionView(
                items: ProteinChoice.allCases.map(\.rawValue),
                selectedItems: $selectedProteins,
                customItem: $customProtein,
                customPlaceholder: "Add another protein"
            )
        case 1:
            SurveySelectionView(
                items: CarbChoice.allCases.map(\.rawValue),
                selectedItems: $selectedCarbs,
                customItem: $customCarb,
                customPlaceholder: "Add another carbohydrate"
            )
        case 2:
            SurveySelectionView(
                items: VeggieChoice.allCases.map(\.rawValue),
                selectedItems: $selectedVeggies,
                customItem: $customVeggies,
                customPlaceholder: "Add another vegetable"
            )
        case 3:
            SurveySelectionView(
                items: SnackChoice.allCases.map(\.rawValue),
                selectedItems: $selectedSnacks,
                customItem: $customSnack,
                customPlaceholder: "Add another snack"
            )
        case 4:
            CuisineSelectionView(selectedCuisines: $selectedCuisines)
        default:
            CookingStyleSelectionView(selectedStyle: $goalSettings.cookingStyle)
        }
    }

    private var bottomActionBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) {
                    primaryActionButton
                    if currentStep > 0 {
                        backButton
                    }
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    actionButtons
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.separator)
                .frame(height: 1)
        }
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if currentStep > 0 {
            backButton
        }
        primaryActionButton
    }

    private var backButton: some View {
        Button("Back") {
            HapticManager.instance.feedback(.light)
            withAnimation(AppMotion.visibility) {
                currentStep = max(0, currentStep - 1)
            }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .accessibilityIdentifier("meal_plan_survey_back")
    }

    private var primaryActionButton: some View {
        Button {
            if currentStep == Self.steps.count - 1 {
                generateAndSavePlan()
            } else {
                HapticManager.instance.feedback(.light)
                withAnimation(AppMotion.visibility) {
                    currentStep = min(currentStep + 1, Self.steps.count - 1)
                }
            }
        } label: {
            Label(
                currentStep == Self.steps.count - 1 ? "Generate Seven-Day Plan" : "Next",
                systemImage: currentStep == Self.steps.count - 1 ? "wand.and.stars" : "arrow.right"
            )
        }
        .buttonStyle(AppActionButtonStyle(.primary))
        .disabled(isLoading || !canAdvance)
        .accessibilityIdentifier("meal_plan_survey_primary_action")
    }

    private var generationOverlay: some View {
        ZStack {
            AppPalette.canvas.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.group) {
                ProgressView()
                    .controlSize(.large)
                    .tint(AppPalette.brand)
                Text("Building Your Week")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                Text("Generating and saving seven days of meals.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .appSurface(.emphasized)
            .padding(AppSpacing.screenHorizontal)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("meal_plan_generation_loading")
    }

    private var progress: Double {
        Double(currentStep + 1) / Double(Self.steps.count)
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 0:
            return !normalized(selectedProteins, custom: customProtein).isEmpty
        case 1:
            return !normalized(selectedCarbs, custom: customCarb).isEmpty
        case 2:
            return !normalized(selectedVeggies, custom: customVeggies).isEmpty
        case 3:
            return !normalized(selectedSnacks, custom: customSnack).isEmpty
        case 4:
            return !MealPlanningPreferenceRules.normalizedCuisines(selectedCuisines).isEmpty
        default:
            return !goalSettings.cookingStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func normalized(_ selected: Set<String>, custom: String) -> [String] {
        MealPlanningPreferenceRules.normalizedItems(selected: selected, custom: custom)
    }

    private func generateAndSavePlan() {
        HapticManager.instance.feedback(.medium)
        isLoading = true
        didGeneratePlan = false
        alertMessage = ""

        let foodList = normalized(selectedProteins, custom: customProtein)
            + normalized(selectedCarbs, custom: customCarb)
            + normalized(selectedVeggies, custom: customVeggies)
        let cuisineList = MealPlanningPreferenceRules.normalizedCuisines(selectedCuisines)
        let snackList = normalized(selectedSnacks, custom: customSnack)

        Task { @MainActor in
            guard let userID = DIContainer.shared.authService.currentUserID else {
                finishWithError("Sign in before generating a meal plan.")
                return
            }

            let success = await mealPlannerService.generateAndSaveFullWeekPlan(
                goals: goalSettings,
                preferredFoods: foodList,
                preferredCuisines: cuisineList,
                preferredSnacks: snackList,
                userID: userID
            )

            isLoading = false
            didGeneratePlan = success
            alertMessage = success
                ? "Your seven-day meal plan is ready."
                : "The generated plan could not be saved. Please try again."
            showAlert = true
        }
    }

    private func finishWithError(_ message: String) {
        isLoading = false
        didGeneratePlan = false
        alertMessage = message
        showAlert = true
    }
}

private struct MealPlanSurveyStep {
    let title: String
    let subtitle: String
    let icon: String
}

private struct SurveySelectionView: View {
    let items: [String]
    @Binding var selectedItems: Set<String>
    @Binding var customItem: String
    let customPlaceholder: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.row), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            LazyVGrid(columns: columns, spacing: AppSpacing.row) {
                ForEach(items, id: \.self) { item in
                    SurveyChoiceButton(
                        title: item,
                        icon: nil,
                        isSelected: selectedItems.contains(item)
                    ) {
                        HapticManager.instance.feedback(.light)
                        if selectedItems.contains(item) {
                            selectedItems.remove(item)
                        } else {
                            selectedItems.insert(item)
                        }
                    }
                }
            }

            customField
        }
    }

    private var customField: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: "plus")
                .appFont(size: 16, weight: .semibold)
                .foregroundStyle(AppPalette.brand)
                .accessibilityHidden(true)
            TextField(customPlaceholder, text: $customItem)
                .appTextRole(.body)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
        .padding(.horizontal, AppSpacing.group)
        .frame(minHeight: 52)
        .background(
            AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
    }
}

private struct SurveyChoiceButton: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.compact) {
                if let icon {
                    Image(systemName: icon)
                        .appFont(size: 16, weight: .semibold)
                        .foregroundStyle(isSelected ? AppPalette.brand : .secondary)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: AppSpacing.compact)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(isSelected ? AppPalette.brand : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppSpacing.group)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                isSelected ? AppPalette.brand.opacity(0.08) : AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(isSelected ? AppPalette.brand : AppPalette.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CuisineSelectionView: View {
    @Binding var selectedCuisines: Set<String>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let cuisines = ["Any", "Italian", "Mexican", "Asian", "Mediterranean", "American"]

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.row), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.row) {
            ForEach(cuisines, id: \.self) { cuisine in
                SurveyChoiceButton(
                    title: cuisine,
                    icon: icon(for: cuisine),
                    isSelected: selectedCuisines.contains(cuisine)
                ) {
                    HapticManager.instance.feedback(.light)
                    selectedCuisines = MealPlanningPreferenceRules.toggledCuisine(
                        cuisine,
                        in: selectedCuisines
                    )
                }
            }
        }
    }

    private func icon(for cuisine: String) -> String {
        switch cuisine {
        case "Italian": "wineglass.fill"
        case "Mexican": "flame.fill"
        case "Asian": "globe.asia.australia.fill"
        case "Mediterranean": "leaf.fill"
        case "American": "flag.fill"
        default: "globe.americas.fill"
        }
    }
}

private enum ProteinChoice: String, CaseIterable {
    case chicken = "Chicken"
    case beef = "Beef"
    case fish = "Fish"
    case tofu = "Tofu"
    case eggs = "Eggs"
    case pork = "Pork"
}

private enum CarbChoice: String, CaseIterable {
    case rice = "Rice"
    case quinoa = "Quinoa"
    case potatoes = "Potatoes"
    case pasta = "Pasta"
    case bread = "Bread"
    case oats = "Oats"
}

private enum VeggieChoice: String, CaseIterable {
    case broccoli = "Broccoli"
    case spinach = "Spinach"
    case bellPeppers = "Bell peppers"
    case onions = "Onions"
    case carrots = "Carrots"
    case zucchini = "Zucchini"
}

private enum SnackChoice: String, CaseIterable {
    case yogurt = "Yogurt"
    case nuts = "Nuts"
    case fruit = "Fruit"
    case proteinBar = "Protein bar"
}

private struct CookingStyleItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
}

private struct CookingStyleSelectionView: View {
    @Binding var selectedStyle: String

    private let styles = [
        CookingStyleItem(
            id: "Macro-Focused Prep",
            title: "Macro-Focused Prep",
            description: "Batch proteins, grains, and vegetables for flexible portions.",
            icon: "shippingbox.fill"
        ),
        CookingStyleItem(
            id: "Aesthetic Prep",
            title: "Portioned Meal Prep",
            description: "Prepare complete meals in individual containers.",
            icon: "takeoutbag.and.cup.and.straw.fill"
        ),
        CookingStyleItem(
            id: "Daily Fresh",
            title: "Daily Fresh",
            description: "Cook distinct meals with more day-to-day variety.",
            icon: "frying.pan.fill"
        ),
        CookingStyleItem(
            id: "Flexible",
            title: "Flexible",
            description: "Mix batch preparation with fresh cooking as needed.",
            icon: "shuffle"
        )
    ]

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ForEach(styles) { style in
                Button {
                    HapticManager.instance.feedback(.light)
                    selectedStyle = style.id
                } label: {
                    CookingStyleRow(style: style, isSelected: selectedStyle == style.id)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedStyle == style.id ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedStyle == style.id ? .isSelected : [])
            }
        }
    }
}

private struct CookingStyleRow: View {
    let style: CookingStyleItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: style.icon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(isSelected ? AppPalette.brand : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    isSelected ? AppPalette.brand.opacity(0.10) : AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(style.title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(style.description)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.compact)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(isSelected ? AppPalette.brand : .secondary)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.group)
        .background(
            isSelected ? AppPalette.brand.opacity(0.06) : AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(isSelected ? AppPalette.brand : AppPalette.separator, lineWidth: 1)
        }
    }
}
