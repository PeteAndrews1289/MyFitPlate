import Foundation
import SwiftUI
import MyFitPlateCore

public struct ChainMealBuilderView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedChain: ChainRestaurant = ChainRestaurantCatalog.allChains[0]
    @State private var selections: [String: ChainSelectionItem] = [:]
    @State private var chainSearchText = ""
    @State private var selectedMeal: String
    let onLogMeal: (FoodItem, String) -> Void

    public init(initialMeal: String = "Lunch", onLogMeal: @escaping (FoodItem, String) -> Void) {
        self._selectedMeal = State(initialValue: initialMeal)
        self.onLogMeal = onLogMeal
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

    public var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        chainSearchBar
                        chainSelectorBar
                        selectedChainHeader
                        catalogNotice
                        mealSelectorBar

                        ForEach(selectedChain.categories) { category in
                            categorySection(for: category)
                        }

                        Spacer().frame(height: 110)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

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
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(size: 15, weight: .bold)
                .foregroundColor(.secondary)

            TextField("Search chains", text: $chainSearchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .appFont(size: 15, weight: .semibold)

            if !chainSearchText.isEmpty {
                Button {
                    chainSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
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
                        .padding(.vertical, 10)
                        .background(
                            selectedChain.id == chain.id
                            ? Color(chainHex: chain.brandColorHex)
                            : Color.backgroundSecondary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(chainHex: chain.brandColorHex).opacity(selectedChain.id == chain.id ? 0 : 0.35), lineWidth: 1)
                        )
                        .foregroundColor(
                            selectedChain.id == chain.id
                            ? (chain.brandForegroundUsesDarkText ? .black : .white)
                            : .textPrimary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var catalogNotice: some View {
        Label {
            Text("Estimated catalog • updated \(ChainRestaurantCatalog.lastUpdatedDate). Brand menus change, so review the meal before logging.")
                .appFont(size: 12, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield")
                .appFont(size: 13, weight: .semibold)
        }
        .foregroundColor(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectedChainHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(brandColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: selectedChain.iconName)
                    .appFont(size: 19, weight: .bold)
                    .foregroundColor(brandColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedChain.name)
                    .appFont(size: 18, weight: .heavy)
                    .foregroundColor(.textPrimary)

                Text(selectedChain.subtitle)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(selectedChain.ingredientCount)")
                .appFont(size: 17, weight: .heavy)
                .foregroundColor(brandColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(brandColor.opacity(0.12), in: Capsule())
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(brandColor.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Meal Selector Bar
    private var mealSelectorBar: some View {
        HStack {
            Text("Log to meal:")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(.secondary)

            Spacer()

            Picker("Meal", selection: $selectedMeal) {
                ForEach(["Breakfast", "Lunch", "Dinner", "Snacks"], id: \.self) { meal in
                    Text(meal).tag(meal)
                }
            }
            .pickerStyle(.menu)
            .tint(.brandPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.backgroundSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Section
    private func categorySection(for category: ChainCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.title.uppercased())
                .appFont(size: 12, weight: .bold)
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(category.ingredients) { ingredient in
                    ingredientRow(for: ingredient)
                }
            }
        }
    }

    private func ingredientRow(for ingredient: ChainIngredient) -> some View {
        let isSelected = selections[ingredient.id] != nil
        let currentPortion = selections[ingredient.id]?.portion ?? .regular

        return VStack(spacing: 10) {
            Button {
                toggleIngredient(ingredient)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(isSelected ? .brandPrimary : .secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ingredient.name)
                            .appFont(size: 15, weight: .semibold)
                            .foregroundColor(.textPrimary)

                        Text(ingredient.servingDescription)
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(ingredient.calories.rounded())) cal")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(.textPrimary)

                        Text("\(Int(ingredient.protein.rounded()))g P • \(Int(ingredient.carbs.rounded()))g C • \(Int(ingredient.fat.rounded()))g F")
                            .appFont(size: 11, weight: .medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                switch ingredient.controlStyle {
                case .portion:
                    HStack(spacing: 8) {
                        Text("Portion:")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.secondary)

                        Spacer()

                        ForEach(ChainMealPortion.allCases) { portion in
                            Button {
                                updatePortion(for: ingredient, to: portion)
                            } label: {
                                Text(portion.title)
                                    .appFont(size: 12, weight: .bold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        currentPortion == portion
                                        ? Color.brandPrimary.opacity(0.2)
                                        : Color.backgroundPrimary,
                                        in: Capsule()
                                    )
                                    .foregroundColor(
                                        currentPortion == portion
                                        ? .brandPrimary
                                        : .textPrimary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 32)

                case .stepper(let unit):
                    HStack(spacing: 8) {
                        Text("Quantity (\(unit)):")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: 14) {
                            Button {
                                decrementCount(for: ingredient)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .appFont(size: 22, weight: .bold)
                                    .foregroundColor((selections[ingredient.id]?.count ?? 1) > 1 ? .brandPrimary : .gray.opacity(0.4))
                            }
                            .disabled((selections[ingredient.id]?.count ?? 1) <= 1)
                            .buttonStyle(.plain)

                            Text("\(selections[ingredient.id]?.count ?? 1)")
                                .appFont(size: 14, weight: .heavy)
                                .foregroundColor(.textPrimary)
                                .frame(minWidth: 24)

                            Button {
                                incrementCount(for: ingredient)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .appFont(size: 22, weight: .bold)
                                    .foregroundColor(canIncrement(ingredient) ? .brandPrimary : .gray.opacity(0.4))
                            }
                            .disabled(!canIncrement(ingredient))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 32)

                case .fixed:
                    EmptyView()
                }
            }
        }
        .padding(13)
        .background(
            isSelected
            ? Color.brandPrimary.opacity(0.08)
            : Color.backgroundSecondary,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected
                    ? Color.brandPrimary.opacity(0.4)
                    : Color.clear,
                    lineWidth: 1.5
                )
        )
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
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(totalCalories.rounded())) cal")
                        .appFont(size: 20, weight: .heavy)
                        .foregroundColor(.textPrimary)

                    Text("\(selections.count) items selected")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    macroBadge(label: "P", grams: totalProtein, color: .green)
                    macroBadge(label: "C", grams: totalCarbs, color: .orange)
                    macroBadge(label: "F", grams: totalFat, color: .blue)
                }
            }

            Button {
                logCustomMeal()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Review meal for \(selectedMeal)")
                }
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    selections.isEmpty
                    ? Color.gray.opacity(0.5)
                    : Color.brandPrimary,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .disabled(selections.isEmpty)
        }
        .padding(16)
        .background(
            Color.backgroundSecondary
                .shadow(color: .black.opacity(0.15), radius: 10, y: -4)
        )
    }

    private func macroBadge(label: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .appFont(size: 11, weight: .heavy)
                .foregroundColor(color)
            Text("\(Int(grams.rounded()))g")
                .appFont(size: 12, weight: .bold)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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
