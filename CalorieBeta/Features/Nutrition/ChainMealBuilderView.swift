import Foundation
import SwiftUI
import MyFitPlateCore

public struct ChainMealBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedChain: ChainRestaurant = ChainRestaurantCatalog.allChains[0]
    @State private var selections: [String: ChainSelectionItem] = [:]
    @State private var chainSearchText = ""
    @State private var selectedMeal: String
    let trainingFuelTarget: TrainingFuelTarget?
    let onLogMeal: (FoodItem, String) -> Void

    public init(
        initialMeal: String = "Lunch",
        trainingFuelTarget: TrainingFuelTarget? = nil,
        onLogMeal: @escaping (FoodItem, String) -> Void
    ) {
        self._selectedMeal = State(initialValue: initialMeal)
        self.trainingFuelTarget = trainingFuelTarget
        self.onLogMeal = onLogMeal

        #if DEBUG
        if ScreenshotDemoData.requestedScreen == "builder",
           let chipotle = ChainRestaurantCatalog.allChains.first(where: { $0.id == "chipotle" }) {
            let showcaseNames = [
                "Cilantro-Lime White Rice",
                "Black Beans",
                "Adobo Chicken",
                "Fajita Veggies",
                "Fresh Tomato Salsa (Pico)",
                "Monterey Jack Cheese"
            ]
            let ingredients = chipotle.categories
                .flatMap(\.ingredients)
                .filter { showcaseNames.contains($0.name) }
            let showcaseSelections = Dictionary(
                uniqueKeysWithValues: ingredients.map { ingredient in
                    (
                        ingredient.id,
                        ChainSelectionItem(
                            id: ingredient.id,
                            ingredient: ingredient,
                            portion: .regular,
                            count: 1
                        )
                    )
                }
            )
            _selectedChain = State(initialValue: chipotle)
            _selections = State(initialValue: showcaseSelections)
        }
        #endif
    }

    private var filteredChains: [ChainRestaurant] {
        let query = chainSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ChainRestaurantCatalog.allChains }

        return ChainRestaurantCatalog.allChains.filter { chain in
            chain.name.localizedCaseInsensitiveContains(query) ||
                chain.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var brandColor: Color {
        Color(chainHex: selectedChain.brandColorHex)
    }

    private var nutritionTotals: ChainMealNutritionTotals {
        selectedChain.nutritionTotals(for: selections)
    }

    private var totalCalories: Double {
        nutritionTotals.calories
    }

    private var totalProtein: Double {
        nutritionTotals.protein
    }

    private var totalCarbs: Double {
        nutritionTotals.carbs
    }

    private var totalFat: Double {
        nutritionTotals.fat
    }

    private var selectedItemCount: Int {
        selections.values.reduce(0) { $0 + $1.count }
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        chainSearchBar
                        chainSelectorBar
                        selectedChainHeader
                        if let trainingFuelTarget {
                            TrainingFuelTargetContextView(
                                target: trainingFuelTarget,
                                currentCalories: totalCalories,
                                currentProtein: totalProtein,
                                currentCarbs: totalCarbs
                            )
                        }
                        mealSelectorBar

                        ForEach(selectedChain.categories) { category in
                            categorySection(for: category)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.row)
                    .padding(.bottom, AppSpacing.group)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                stickyBottomBar
            }
            .navigationTitle("Fast Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .appFont(size: 16, weight: .semibold)
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Reset") { selections.removeAll() }
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(selections.isEmpty ? .secondary : .brandPrimary)
                        .disabled(selections.isEmpty)
                }
            }
            .onChange(of: selectedChain) { _, _ in
                selections.removeAll()
            }
        }
    }

    // MARK: - Chain Selector Bar
    private var chainSearchBar: some View {
        HStack(spacing: AppSpacing.compact) {
            if !usesAccessibilityLayout {
                Image(systemName: "magnifyingglass")
                    .appTextRole(.control)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            TextField(usesAccessibilityLayout ? "Find chain" : "Search chains", text: $chainSearchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .appTextRole(.body)
                .accessibilityIdentifier("chain_builder_search")

            if !chainSearchText.isEmpty {
                Button {
                    chainSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appTextRole(.control)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear chain search")
            }
        }
        .padding(.horizontal, AppSpacing.row)
        .frame(minHeight: 54)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator.opacity(0.7), lineWidth: 0.5)
        }
    }

    private var chainSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filteredChains) { chain in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedChain = chain
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: chain.iconName)
                                .appFont(size: 14, weight: .bold)

                            Text(chain.name)
                                .appFont(size: 14, weight: .bold)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(
                            selectedChain.id == chain.id
                            ? Color(chainHex: chain.brandColorHex)
                            : AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .stroke(Color(chainHex: chain.brandColorHex).opacity(selectedChain.id == chain.id ? 0 : 0.35), lineWidth: 1)
                        )
                        .foregroundColor(
                            selectedChain.id == chain.id
                            ? (chain.brandForegroundUsesDarkText ? .black : .white)
                            : .textPrimary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chain_builder_chain_\(chain.id)")
                }
            }
        }
    }

    private var selectedChainHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Group {
                if usesAccessibilityLayout {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        selectedChainIdentity
                        selectedChainItemCount
                    }
                } else {
                    HStack(spacing: AppSpacing.row) {
                        selectedChainIdentity
                        Spacer(minLength: 0)
                        selectedChainItemCount
                    }
                }
            }

            Label {
                Text("Estimated catalog · Updated \(ChainRestaurantCatalog.lastUpdatedDate) · Review before logging")
                    .appTextRole(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.shield")
                    .appTextRole(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("chain_builder_selected_chain")
    }

    private var selectedChainIdentity: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: selectedChain.iconName)
                .appTextRole(.sectionTitle)
                .foregroundStyle(brandColor)
                .frame(width: 44, height: 44)
                .background(brandColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedChain.name)
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text(selectedChain.subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedChainItemCount: some View {
        Text("\(selectedChain.ingredientCount) items")
            .appTextRole(.secondary)
            .foregroundStyle(brandColor)
            .accessibilityIdentifier("chain_builder_catalog_count")
    }

    // MARK: - Meal Selector Bar
    @ViewBuilder
    private var mealSelectorBar: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    mealSelectorLabel
                    mealPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    mealSelectorLabel
                    Spacer()
                    mealPicker
                }
            }
        }
        .padding(.vertical, AppSpacing.compact)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityIdentifier("chain_builder_meal_target")
    }

    private var mealSelectorLabel: some View {
        Text("Log to meal")
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
    }

    private var mealPicker: some View {
        Picker("Meal", selection: $selectedMeal) {
            ForEach(["Breakfast", "Lunch", "Dinner", "Snacks"], id: \.self) { meal in
                Text(meal).tag(meal)
            }
        }
        .pickerStyle(.menu)
        .tint(AppPalette.brand)
    }

    // MARK: - Category Section
    private func categorySection(for category: ChainCategory) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(category.title)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            VStack(spacing: AppSpacing.compact) {
                ForEach(category.ingredients) { ingredient in
                    ingredientRow(for: ingredient)
                }
            }
        }
    }

    private func ingredientRow(for ingredient: ChainIngredient) -> some View {
        let isSelected = selections[ingredient.id] != nil
        let currentPortion = selections[ingredient.id]?.portion ?? .regular

        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Button {
                toggleIngredient(ingredient)
            } label: {
                ingredientSummary(ingredient, isSelected: isSelected)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ingredient.name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            if isSelected {
                switch ingredient.controlStyle {
                case .portion:
                    portionControl(for: ingredient, currentPortion: currentPortion)

                case .stepper(let unit):
                    quantityControl(for: ingredient, unit: unit)

                case .fixed:
                    EmptyView()
                }
            }
        }
        .padding(AppSpacing.row)
        .background(
            isSelected
            ? AppPalette.brand.opacity(0.08)
            : AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(
                    isSelected
                    ? AppPalette.brand.opacity(0.45)
                    : AppPalette.separator.opacity(0.45),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
        .accessibilityIdentifier("chain_builder_ingredient_\(ingredient.id)")
    }

    @ViewBuilder
    private func ingredientSummary(_ ingredient: ChainIngredient, isSelected: Bool) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ingredientIdentity(ingredient, isSelected: isSelected)
                ingredientNutrition(ingredient, alignment: .leading)
            }
        } else {
            HStack(spacing: AppSpacing.row) {
                ingredientIdentity(ingredient, isSelected: isSelected)
                Spacer(minLength: AppSpacing.compact)
                ingredientNutrition(ingredient, alignment: .trailing)
            }
        }
    }

    private func ingredientIdentity(_ ingredient: ChainIngredient, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .appTextRole(.sectionTitle)
                .foregroundStyle(isSelected ? AppPalette.brand : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(ingredient.name)
                    .appTextRole(.body)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(ingredient.servingDescription)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ingredientNutrition(
        _ ingredient: ChainIngredient,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text("\(Int(ingredient.calories.rounded())) cal")
                .appTextRole(.body)
                .foregroundStyle(AppPalette.text)

            Text(
                "P \(Int(ingredient.protein.rounded()))g  " +
                "C \(Int(ingredient.carbs.rounded()))g  " +
                "F \(Int(ingredient.fat.rounded()))g"
            )
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func portionControl(
        for ingredient: ChainIngredient,
        currentPortion: ChainMealPortion
    ) -> some View {
        if usesAccessibilityLayout {
            HStack(spacing: AppSpacing.row) {
                Text("Portion")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Menu {
                    ForEach(ChainMealPortion.allCases) { portion in
                        Button(portion.title) {
                            updatePortion(for: ingredient, to: portion)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentPortion.title)
                            .appTextRole(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .appTextRole(.caption)
                    }
                    .foregroundStyle(AppPalette.text)
                    .padding(.horizontal, AppSpacing.row)
                    .frame(minHeight: 44)
                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                }
            }
        } else {
            HStack(spacing: AppSpacing.compact) {
                Text("Portion")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                ForEach(ChainMealPortion.allCases) { portion in
                    Button {
                        updatePortion(for: ingredient, to: portion)
                    } label: {
                        Text(portion.title)
                            .appTextRole(.caption)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 36)
                            .background(
                                currentPortion == portion
                                ? AppPalette.brand.opacity(0.16)
                                : AppPalette.canvas,
                                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            )
                            .foregroundStyle(currentPortion == portion ? AppPalette.brand : AppPalette.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func quantityControl(for ingredient: ChainIngredient, unit: String) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                quantityLabel(unit: unit)
                quantityButtons(for: ingredient)
            }
        } else {
            HStack(spacing: AppSpacing.compact) {
                quantityLabel(unit: unit)
                Spacer(minLength: 0)
                quantityButtons(for: ingredient)
            }
        }
    }

    private func quantityLabel(unit: String) -> some View {
        Text("Quantity (\(unit))")
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
    }

    private func quantityButtons(for ingredient: ChainIngredient) -> some View {
        HStack(spacing: AppSpacing.compact) {
            Button {
                decrementCount(for: ingredient)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .disabled((selections[ingredient.id]?.count ?? 1) <= 1)
            .accessibilityLabel("Decrease quantity")

            Text("\(selections[ingredient.id]?.count ?? 1)")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .frame(minWidth: 32)
                .contentTransition(.numericText())

            Button {
                incrementCount(for: ingredient)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .disabled(!canIncrement(ingredient))
            .accessibilityLabel("Increase quantity")
        }
    }

    private func toggleIngredient(_ ingredient: ChainIngredient) {
        if selections[ingredient.id] != nil {
            selections.removeValue(forKey: ingredient.id)
        } else {
            selections[ingredient.id] = ChainSelectionItem(
                id: ingredient.id,
                ingredient: ingredient,
                portion: .regular,
                count: 1
            )
        }
    }

    private func updatePortion(for ingredient: ChainIngredient, to portion: ChainMealPortion) {
        guard var existing = selections[ingredient.id] else { return }
        existing.portion = portion
        selections[ingredient.id] = existing
    }

    private func incrementCount(for ingredient: ChainIngredient) {
        guard var existing = selections[ingredient.id] else { return }
        guard existing.count < ingredient.maximumCount else { return }
        existing.count += 1
        selections[ingredient.id] = existing
    }

    private func decrementCount(for ingredient: ChainIngredient) {
        guard var existing = selections[ingredient.id], existing.count > 1 else { return }
        existing.count -= 1
        selections[ingredient.id] = existing
    }

    private func canIncrement(_ ingredient: ChainIngredient) -> Bool {
        (selections[ingredient.id]?.count ?? 1) < ingredient.maximumCount
    }

    // MARK: - Sticky Bottom Bar
    private var stickyBottomBar: some View {
        VStack(spacing: AppSpacing.row) {
            if !usesAccessibilityLayout {
                HStack(spacing: 14) {
                    calorieSelectionSummary
                    Spacer()
                    macroSummary
                }
            }

            Button {
                logCustomMeal()
            } label: {
                Label(
                    usesAccessibilityLayout ? "Review order" : "Review \(selectedMeal) meal",
                    systemImage: "checkmark.circle.fill"
                )
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(selections.isEmpty)
            .accessibilityValue(
                "\(Int(totalCalories.rounded())) calories, " +
                "\(selectedItemCount) \(selectedItemCount == 1 ? "item" : "items") selected"
            )
            .accessibilityIdentifier("chain_builder_review_meal")
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.row)
        .padding(.bottom, AppSpacing.compact)
        .background {
            AppPalette.canvas
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var calorieSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(totalCalories.rounded())) cal")
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            Text("\(selectedItemCount) \(selectedItemCount == 1 ? "item" : "items") selected")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("chain_builder_selection_summary")
    }

    private var macroSummary: some View {
        HStack(spacing: 8) {
            macroBadge(label: "P", grams: totalProtein, color: .green)
            macroBadge(label: "C", grams: totalCarbs, color: .orange)
            macroBadge(label: "F", grams: totalFat, color: .blue)
        }
    }

    private func macroBadge(label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .appTextRole(.caption)
                .foregroundStyle(color)
            Text("\(Int(grams.rounded()))g")
                .appTextRole(.secondary)
                .foregroundStyle(AppPalette.text)
        }
        .padding(.horizontal, AppSpacing.compact)
        .frame(minHeight: 32)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func logCustomMeal() {
        guard !selections.isEmpty else { return }

        let customMealItem = selectedChain.customMealFoodItem(from: selections)

        onLogMeal(customMealItem, selectedMeal)
        dismiss()
    }
}

private extension Color {
    init(chainHex hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch sanitized.count {
        case 6:
            red = (value & 0xFF0000) >> 16
            green = (value & 0x00FF00) >> 8
            blue = value & 0x0000FF
        default:
            red = 51
            green = 153
            blue = 102
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1
        )
    }
}
