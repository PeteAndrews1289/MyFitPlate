import SwiftUI

struct SuggestionPreferencesView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedProteins: Set<String>
    @State private var selectedCarbs: Set<String>
    @State private var selectedVeggies: Set<String>
    @State private var selectedCuisines: Set<String>

    let allProteins = ["Chicken", "Beef", "Fish", "Tofu", "Eggs", "Pork", "Lamb"]
    let allCarbs = ["Rice", "Quinoa", "Potatoes", "Pasta", "Bread", "Oats"]
    let allVeggies = ["Broccoli", "Spinach", "Bell Peppers", "Onions", "Carrots", "Zucchini", "Asparagus"]
    let allCuisines = ["Any", "Italian", "Mexican", "Asian", "Mediterranean", "American"]

    init(goalSettings: GoalSettings) {
        _selectedProteins = State(initialValue: Set(goalSettings.suggestionProteins))
        _selectedCarbs = State(initialValue: Set(goalSettings.suggestionCarbs))
        _selectedVeggies = State(initialValue: Set(goalSettings.suggestionVeggies))
        _selectedCuisines = State(initialValue: Set(goalSettings.suggestionCuisines))
    }

    var body: some View {
        AppEditorScaffold(
            title: "Suggestion Preferences",
            subtitle: "Shape meal ideas without locking the planner to a narrow menu.",
            dismiss: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                preferenceSection(
                    title: "Proteins",
                    subtitle: "Choose any staples you enjoy.",
                    options: allProteins,
                    selection: $selectedProteins
                )
                preferenceSection(
                    title: "Carbohydrates",
                    subtitle: "Select the bases you want suggestions built around.",
                    options: allCarbs,
                    selection: $selectedCarbs
                )
                preferenceSection(
                    title: "Vegetables",
                    subtitle: "Use several choices for more variety.",
                    options: allVeggies,
                    selection: $selectedVeggies
                )
                preferenceSection(
                    title: "Cuisines",
                    subtitle: "\"Any\" keeps every cuisine available.",
                    options: allCuisines,
                    selection: $selectedCuisines,
                    isExclusive: true
                )
            }
        } actions: {
            Button("Save Preferences", action: saveAndDismiss)
                .buttonStyle(AppActionButtonStyle(.primary))
        }
        .tint(AppPalette.brand)
    }

    private func preferenceSection(
        title: String,
        subtitle: String,
        options: [String],
        selection: Binding<Set<String>>,
        isExclusive: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title, subtitle: subtitle)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: AppSpacing.compact)],
                alignment: .leading,
                spacing: AppSpacing.compact
            ) {
                ForEach(options, id: \.self) { item in
                    let isSelected = selection.wrappedValue.contains(item)
                    Button {
                        updateSelection(
                            item: item,
                            selection: selection,
                            isExclusive: isExclusive
                        )
                    } label: {
                        HStack(spacing: AppSpacing.compact) {
                            Text(item)
                                .appTextRole(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 2)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.text)
                        .padding(.horizontal, AppSpacing.row)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            isSelected ? AppPalette.brand : AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .stroke(
                                    isSelected ? Color.clear : AppPalette.separator,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
        }
        .appSurface(.emphasized)
    }

    private func updateSelection(
        item: String,
        selection: Binding<Set<String>>,
        isExclusive: Bool
    ) {
        if isExclusive {
            if item == "Any" {
                selection.wrappedValue = ["Any"]
            } else {
                selection.wrappedValue.remove("Any")
                if selection.wrappedValue.contains(item) {
                    selection.wrappedValue.remove(item)
                } else {
                    selection.wrappedValue.insert(item)
                }
            }
        } else if selection.wrappedValue.contains(item) {
            selection.wrappedValue.remove(item)
        } else {
            selection.wrappedValue.insert(item)
        }
    }

    private func saveAndDismiss() {
        goalSettings.suggestionProteins = selectedProteins.sorted()
        goalSettings.suggestionCarbs = selectedCarbs.sorted()
        goalSettings.suggestionVeggies = selectedVeggies.sorted()
        goalSettings.suggestionCuisines = selectedCuisines.sorted()
        if let userID = DIContainer.shared.authService.currentUserID {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
}
