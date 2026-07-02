import SwiftUI

struct FoodDetailHeroCard: View {
    let foodName: String
    let servingDescription: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(FoodEmojiMapper.getEmoji(for: foodName))
                .appFont(size: 34)
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(foodName)
                    .appFont(size: 24, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(servingDescription, systemImage: "scalemass.fill")
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct FoodDetailMacroGrid: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            FoodDetailMacroTile(title: "Calories", value: "\(Int(calories.rounded()))", unit: "cal", icon: "flame.fill", color: .orange)
            FoodDetailMacroTile(title: "Protein", value: String(format: "%.1f", protein), unit: "g", icon: "bolt.fill", color: .accentProtein)
            FoodDetailMacroTile(title: "Carbs", value: String(format: "%.1f", carbs), unit: "g", icon: "leaf.fill", color: .accentCarbs)
            FoodDetailMacroTile(title: "Fat", value: String(format: "%.1f", fats), unit: "g", icon: "drop.fill", color: .accentFats)
        }
    }
}

struct FoodDetailMacroTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(unit)
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Text(title)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FoodDetailLoadingCard: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

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
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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

struct FoodDetailBarcodeCorrectionCard: View {
    let fixAction: () -> Void
    let rememberAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Barcode match")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Fix the match or save this version for future scans.")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button(action: fixAction) {
                    Label("Fix", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FoodDetailCorrectionButtonStyle(tint: .brandPrimary, isFilled: true))

                Button(action: rememberAction) {
                    Label("Remember", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FoodDetailCorrectionButtonStyle(tint: .brandPrimary, isFilled: false))
                .accessibilityHint("Saves this food as the match for this barcode.")
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FoodDetailCorrectionButtonStyle: ButtonStyle {
    let tint: Color
    let isFilled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 13, weight: .bold)
            .foregroundColor(isFilled ? .white : tint)
            .padding(.vertical, 10)
            .background(
                (isFilled ? tint : tint.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct FoodDataSanityCard: View {
    let findings: [FoodDataSanity.Finding]
    let fixAction: () -> Void

    private var hasWarning: Bool {
        findings.contains { $0.severity == .warning }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: hasWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(hasWarning ? .orange : .blue)
                    .frame(width: 42, height: 42)
                    .background((hasWarning ? Color.orange : Color.blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(hasWarning ? "This data looks off" : "Worth a quick look")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("MyFitPlate checks every food against nutrition math.")
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(findings) { finding in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: finding.severity == .warning ? "exclamationmark.circle.fill" : "info.circle")
                            .appFont(size: 11, weight: .bold)
                            .foregroundColor(finding.severity == .warning ? .orange : Color(UIColor.secondaryLabel))
                            .padding(.top, 1)

                        Text(finding.message)
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if hasWarning {
                Button(action: fixAction) {
                    Label("Fix This Data", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FoodDetailCorrectionButtonStyle(tint: .orange, isFilled: true))
                .accessibilityHint("Opens an editor to correct this food's nutrition data.")
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            doubleValue(fats) != nil
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
            .navigationTitle("Fix Food")
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
                .foregroundColor(.brandPrimary)
                .frame(width: 42, height: 42)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                correctionTextField(title: "Fat", text: $fats, unit: "g", keyboard: .decimalPad)
            }

            correctionTextField(title: "Fiber", text: $fiber, unit: "g", keyboard: .decimalPad)
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
            saturatedFat: serving.saturatedFat,
            polyunsaturatedFat: serving.polyunsaturatedFat,
            monounsaturatedFat: serving.monounsaturatedFat,
            fiber: doubleValue(fiber) ?? serving.fiber,
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
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }
}

struct FoodDetailActionBar: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isEnabled)
        }
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
