import SwiftUI

struct FoodDetailHeroCard: View {
    let foodName: String
    let servingDescription: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    foodEmoji
                    foodIdentity
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    foodEmoji
                    foodIdentity
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet, radius: AppRadius.hero)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("food_detail_identity")
    }

    private var foodEmoji: some View {
        Text(FoodEmojiMapper.getEmoji(for: foodName))
            .font(.system(size: 30))
            .frame(width: 54, height: 54)
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator.opacity(0.55), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    private var foodIdentity: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(foodName)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Label(servingDescription, systemImage: "scalemass.fill")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FoodDetailMacroGrid: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double

    var body: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Calories",
                value: "\(Int(calories.rounded()).formatted()) cal",
                accent: .orange
            ),
            AppMetricItem(
                label: "Protein",
                value: "\(macroValue(protein)) g",
                accent: .accentProtein
            ),
            AppMetricItem(
                label: "Carbs",
                value: "\(macroValue(carbs)) g",
                accent: .accentCarbs
            ),
            AppMetricItem(
                label: "Fat",
                value: "\(macroValue(fats)) g",
                accent: .accentFats
            )
        ])
        .appSurface(.quiet)
        .accessibilityIdentifier("food_detail_macro_summary")
    }

    private func macroValue(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return Int(rounded).formatted()
        }
        return rounded.formatted(.number.precision(.fractionLength(1)))
    }
}

struct FoodDetailLoadingCard: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.blue)

            Text("Loading serving options")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Pulling the most accurate nutrition details for this food.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 18)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct FoodDetailNoticeCard: View {
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

struct FoodDetailLabelScanCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Nutrition label looks different?")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Take a label photo to replace these numbers.")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(14)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FoodDetailBarcodeMemoryAction: View {
    let rememberAction: () -> Void

    var body: some View {
        Button(action: rememberAction) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.blue)
                    .frame(width: 38, height: 38)
                    .background(Color.blue.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Use for future scans")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Save this reviewed entry as the match for this barcode.")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                Image(systemName: "bookmark")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityHint("Saves this food as the match for this barcode.")
    }
}

struct FoodDetailCorrectionSheet: View {
    let serving: ServingSizeOption
    let barcode: String?
    let onSave: (String, ServingSizeOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var servingDescription: String
    @State private var servingWeight: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fats: String
    @State private var saturatedFat: String
    @State private var fiber: String

    init(
        foodName: String,
        serving: ServingSizeOption,
        barcode: String?,
        onSave: @escaping (String, ServingSizeOption) -> Void
    ) {
        self.serving = serving
        self.barcode = barcode
        self.onSave = onSave
        self._name = State(initialValue: foodName)
        self._servingDescription = State(initialValue: serving.description)
        self._servingWeight = State(initialValue: Self.text(for: serving.servingWeightGrams))
        self._calories = State(initialValue: Self.requiredText(for: serving.calories))
        self._protein = State(initialValue: Self.requiredText(for: serving.protein))
        self._carbs = State(initialValue: Self.requiredText(for: serving.carbs))
        self._fats = State(initialValue: Self.requiredText(for: serving.fats))
        self._saturatedFat = State(initialValue: Self.text(for: serving.saturatedFat))
        self._fiber = State(initialValue: Self.text(for: serving.fiber))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedServingDescription: String {
        servingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty &&
            !trimmedServingDescription.isEmpty &&
            doubleValue(calories) != nil &&
            doubleValue(protein) != nil &&
            doubleValue(carbs) != nil &&
            doubleValue(fats) != nil &&
            isValidOptionalNumber(servingWeight) &&
            isValidOptionalNumber(saturatedFat) &&
            isValidOptionalNumber(fiber) &&
            saturatedFatValidationMessage == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    correctionHeader
                    identityFields
                    macroFields
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Fix food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let correctedServing else { return }
                        onSave(trimmedName, correctedServing)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var correctionHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil.and.scribble")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.orange)
                .frame(width: 42, height: 42)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Correct barcode match")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                if let barcode {
                    Text("Barcode \(barcode)")
                        .appFont(size: 12, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Serving")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            correctionTextField(title: "Food name", text: $name, keyboard: .default)
            correctionTextField(title: "Serving size", text: $servingDescription, keyboard: .default)
            correctionTextField(title: "Serving weight", text: $servingWeight, unit: "g", keyboard: .decimalPad)
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var macroFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                correctionTextField(title: "Calories", text: $calories, unit: "cal", keyboard: .decimalPad)
                correctionTextField(title: "Protein", text: $protein, unit: "g", keyboard: .decimalPad)
                correctionTextField(title: "Carbs", text: $carbs, unit: "g", keyboard: .decimalPad)
                correctionTextField(title: "Total fat", text: $fats, unit: "g", keyboard: .decimalPad)
                correctionTextField(title: "Saturated fat", text: $saturatedFat, unit: "g", keyboard: .decimalPad)
                correctionTextField(title: "Fiber", text: $fiber, unit: "g", keyboard: .decimalPad)
            }

            if let saturatedFatValidationMessage {
                Label(saturatedFatValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var correctedServing: ServingSizeOption? {
        guard canSave,
              let caloriesValue = doubleValue(calories),
              let proteinValue = doubleValue(protein),
              let carbsValue = doubleValue(carbs),
              let fatsValue = doubleValue(fats) else {
            return nil
        }

        return ServingSizeOption(
            description: trimmedServingDescription,
            servingWeightGrams: doubleValue(servingWeight),
            calories: caloriesValue,
            protein: proteinValue,
            carbs: carbsValue,
            fats: fatsValue,
            saturatedFat: doubleValue(saturatedFat),
            polyunsaturatedFat: serving.polyunsaturatedFat,
            monounsaturatedFat: serving.monounsaturatedFat,
            fiber: doubleValue(fiber),
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

    private func correctionTextField(
        title: String,
        text: Binding<String>,
        unit: String? = nil,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(size: 12, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 6) {
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.textPrimary)

                if let unit {
                    Text(unit)
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .padding(12)
            .background(Color.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private static func text(for value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return String(format: "%g", value)
    }

    private static func requiredText(for value: Double) -> String {
        String(format: "%g", max(0, value))
    }

    private func doubleValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func isValidOptionalNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || doubleValue(trimmed) != nil
    }

    private var saturatedFatValidationMessage: String? {
        guard let saturatedFatValue = doubleValue(saturatedFat),
              let totalFatValue = doubleValue(fats),
              !FoodDataSanity.saturatedFatFitsWithinTotalFat(
                  saturatedFat: saturatedFatValue,
                  totalFat: totalFatValue
              ) else {
            return nil
        }
        return "Saturated fat cannot be greater than total fat."
    }
}

struct FoodDetailActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(!isEnabled)
            .accessibilityIdentifier("food_detail_log_action")
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.row)
            .background(AppPalette.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
    }
}
