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
                accent: AppPalette.energy
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

struct FoodTrustSummaryCard: View {
    let item: FoodItem
    let descriptor: FoodSourceDescriptor
    let evaluation: FoodTrustEvaluation
    let metadata: FoodSourceMetadata?
    let isSavingCorrection: Bool
    let resolution: FoodTrustResolution?
    let onOpenReceipt: () -> Void
    let onAction: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var passport: FoodTrustPassport {
        FoodTrustPassport.evaluate(item: item, descriptor: descriptor, metadata: metadata)
    }

    private var tint: Color {
        switch evaluation.level {
        case .excellent, .strong: .accentPositiveText
        case .review: AppPalette.caution
        case .low: evaluation.requiresCorrection ? AppPalette.critical : AppPalette.caution
        }
    }

    private var agreementText: String {
        let evidenceCount = metadata?.validatedCrossVerificationEvidence.count ?? 0
        guard evidenceCount > 0 else { return "No independent comparison" }
        return "\(evidenceCount + 1) sources agree"
    }

    private var nutrientCoverageText: String {
        "\(item.reportedVitaminMineralCount) of \(MicronutrientKey.vitaminAndMineralKeys.count) nutrients reported"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Button(action: onOpenReceipt) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            summaryIdentity
                            summaryEvidence
                        }
                    } else {
                        HStack(alignment: .center, spacing: AppSpacing.row) {
                            summaryIdentity
                            Spacer(minLength: AppSpacing.compact)
                            summaryEvidence
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("food_trust_summary")
            .accessibilityLabel("Food Trust, \(evaluation.label)")
            .accessibilityHint("Opens the complete evidence receipt")

            if let resolution {
                Label(resolution.title, systemImage: "checkmark.circle.fill")
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.brandText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle = evaluation.action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: AppSpacing.compact) {
                        if isSavingCorrection {
                            ProgressView()
                        } else {
                            Image(systemName: actionTitle == "Fix data" ? "pencil" : "slider.horizontal.3")
                        }
                        Text(isSavingCorrection ? "Saving correction" : actionTitle)
                    }
                }
                .buttonStyle(AppActionButtonStyle(
                    evaluation.requiresCorrection ? .destructive : .secondary
                ))
                .disabled(isSavingCorrection)
                .accessibilityIdentifier("food_trust_action")
            }
        }
        .appSurface(.quiet)
    }

    private var summaryIdentity: some View {
        HStack(alignment: .center, spacing: AppSpacing.row) {
            Image(systemName: "checkmark.shield.fill")
                .appFont(size: 18, weight: .bold)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Food Trust")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(evaluation.label)
                    .appTextRole(.secondary)
                    .foregroundStyle(tint)
            }
        }
    }

    private var summaryEvidence: some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(passport.coreNutrition.state.label)
                    .appTextRole(.caption)
                    .foregroundStyle(tint)
                Text("\(agreementText) · \(nutrientCoverageText)")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Image(systemName: "chevron.right")
                .appFont(size: 12, weight: .bold)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

struct FoodNutrientProfileCard: View {
    let nutrients: AdjustedServingNutrition
    let onOpenProfile: () -> Void
    let onScanLabel: () -> Void

    private let previewLimit = 6

    private var reportedKeys: [MicronutrientKey] {
        MicronutrientKey.vitaminAndMineralKeys
            .filter { nutrients.micronutrientValue(for: $0) != nil }
            .sorted { lhs, rhs in
                percentDailyValue(for: lhs) > percentDailyValue(for: rhs)
            }
    }

    private var previewKeys: [MicronutrientKey] {
        Array(reportedKeys.prefix(previewLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                AppSectionHeader(title: "Micronutrients")
                Spacer(minLength: AppSpacing.compact)
                Text("\(reportedKeys.count)/\(MicronutrientKey.vitaminAndMineralKeys.count) reported")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("food_nutrient_profile_summary")

            if previewKeys.isEmpty {
                missingDataState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(previewKeys.enumerated()), id: \.element) { index, key in
                        nutrientRow(for: key)
                        if index < previewKeys.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }

                Button(action: onOpenProfile) {
                    HStack(spacing: AppSpacing.compact) {
                        Text("Explore nutrient profile")
                        Spacer()
                        Text("\(reportedKeys.count) reported")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .appFont(size: 12, weight: .bold)
                    }
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .accessibilityIdentifier("food_nutrient_profile_open")

                Text("Missing values are unknown, not zero. % Daily Value is a general label reference, not a personal target.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface(.quiet)
    }

    private var missingDataState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: "circle.dotted")
                    .appFont(size: 17, weight: .bold)
                    .foregroundStyle(AppPalette.caution)
                    .frame(width: 38, height: 38)
                    .background(AppPalette.caution.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("No vitamin or mineral detail reported")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                    Text("This source supplied calories and macros only. MyFitPlate will not treat missing nutrients as zero.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Scan Nutrition Label", action: onScanLabel)
                .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .accessibilityIdentifier("food_nutrient_profile_missing")
    }

    private func nutrientRow(for key: MicronutrientKey) -> some View {
        let amount = nutrients.micronutrientValue(for: key) ?? 0
        let percent = key.percentDailyValue(for: amount) ?? 0
        let tint = nutrientTint(for: key)

        return HStack(spacing: AppSpacing.row) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    Text(key.displayName)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                    Spacer(minLength: AppSpacing.compact)
                    Text("\(formattedAmount(amount)) \(key.unit)")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.text)
                    Text(formattedPercent(percent))
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48, alignment: .trailing)
                }

                ProgressView(value: min(percent / 100, 1))
                    .tint(tint)
            }
            .padding(.vertical, AppSpacing.compact)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.displayName)
        .accessibilityValue("\(formattedAmount(amount)) \(key.unit), \(formattedPercent(percent))")
    }

    private func percentDailyValue(for key: MicronutrientKey) -> Double {
        guard let amount = nutrients.micronutrientValue(for: key) else { return 0 }
        return key.percentDailyValue(for: amount) ?? 0
    }
}

struct FoodNutrientProfileSheet: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case vitamins = "Vitamins"
        case minerals = "Minerals"

        var id: String { rawValue }
    }

    let foodName: String
    let servingDescription: String
    let nutrients: AdjustedServingNutrition
    let onScanLabel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filter: Filter = .all

    private var reportedCount: Int {
        MicronutrientKey.vitaminAndMineralKeys.filter {
            nutrients.micronutrientValue(for: $0) != nil
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    coverageHeader

                    Picker("Nutrient category", selection: $filter) {
                        ForEach(Filter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("food_nutrient_profile_filter")

                    ForEach(visibleCategories, id: \.self) { category in
                        categorySection(category)
                    }

                    missingCoverage

                    Button {
                        dismiss()
                        onScanLabel()
                    } label: {
                        Label("Scan Nutrition Label", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Nutrient profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var coverageHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(foodName)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
            Text(servingDescription)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)

            HStack(spacing: AppSpacing.group) {
                ZStack {
                    Circle()
                        .stroke(AppPalette.separator, lineWidth: 7)
                    Circle()
                        .trim(
                            from: 0,
                            to: CGFloat(reportedCount) / CGFloat(MicronutrientKey.vitaminAndMineralKeys.count)
                        )
                        .stroke(
                            AppPalette.brand,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(reportedCount)")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(reportedCount) of \(MicronutrientKey.vitaminAndMineralKeys.count) fields reported")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                    Text("Reported values stay distinct from fields this source did not supply.")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .appSurface(.interpreted)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("food_nutrient_profile_coverage")
    }

    private var visibleCategories: [MicronutrientCategory] {
        switch filter {
        case .all: [.vitamin, .mineral]
        case .vitamins: [.vitamin]
        case .minerals: [.mineral]
        }
    }

    private func keys(for category: MicronutrientCategory) -> [MicronutrientKey] {
        switch category {
        case .vitamin: MicronutrientKey.vitaminKeys
        case .mineral: MicronutrientKey.mineralKeys
        case .other: [.fiber]
        }
    }

    private func categorySection(_ category: MicronutrientCategory) -> some View {
        let reported = keys(for: category).filter {
            nutrients.micronutrientValue(for: $0) != nil
        }

        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.displayName)
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text("\(reported.count) reported")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }

            if reported.isEmpty {
                Text("No \(category.displayName.lowercased()) were reported by this source.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.compact)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(reported.enumerated()), id: \.element) { index, key in
                        detailedNutrientRow(for: key)
                        if index < reported.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .appSurface(.quiet)
    }

    private func detailedNutrientRow(for key: MicronutrientKey) -> some View {
        let amount = nutrients.micronutrientValue(for: key) ?? 0
        let percent = key.percentDailyValue(for: amount) ?? 0
        let tint = nutrientTint(for: key)

        return HStack(spacing: AppSpacing.row) {
            Image(systemName: key.category == .vitamin ? "sparkles" : "hexagon.fill")
                .appFont(size: 12, weight: .bold)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                    Text(key.displayName)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                    Spacer(minLength: AppSpacing.compact)
                    Text("\(formattedAmount(amount)) \(key.unit)")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.text)
                    Text(formattedPercent(percent))
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48, alignment: .trailing)
                }
                ProgressView(value: min(percent / 100, 1))
                    .tint(tint)
            }
            .padding(.vertical, AppSpacing.compact)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(key.displayName)
        .accessibilityValue("\(formattedAmount(amount)) \(key.unit), \(formattedPercent(percent))")
    }

    private var missingCoverage: some View {
        let missing = visibleCategories.flatMap(keys).filter {
            nutrients.micronutrientValue(for: $0) == nil
        }

        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Not reported")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
            Text(missing.isEmpty ? "Every field in this view has reported data." : missing.map(\.displayName).joined(separator: " · "))
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Missing means the source did not provide a value; MyFitPlate does not count it as zero. % Daily Value uses the general U.S. label reference.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appSurface(.interpreted)
    }
}

private func nutrientTint(for key: MicronutrientKey) -> Color {
    if key == .sodium { return AppPalette.caution }
    switch key.category {
    case .vitamin: return AppPalette.effort
    case .mineral: return AppPalette.recovery
    case .other: return AppPalette.brandText
    }
}

private func formattedAmount(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}

private func formattedPercent(_ value: Double) -> String {
    "\(Int(value.rounded()).formatted())% DV"
}

struct FoodDetailLoadingCard: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(AppPalette.effort)

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
                .foregroundColor(AppPalette.caution)
                .frame(width: 34, height: 34)
                .background(AppPalette.caution.opacity(0.12), in: Circle())

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
        .background(AppPalette.caution.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LabelScanFailureCard: View {
    let retry: () -> Void
    let continueManually: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("Label details were not clear enough", systemImage: "doc.text.viewfinder")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text("Try a flatter, brighter photo with the full Nutrition Facts panel visible. Your current serving and nutrient values have not been changed.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.compact) {
                Button("Try Another Photo", action: retry)
                    .buttonStyle(AppActionButtonStyle(.secondary, fillsWidth: false))
                Button("Edit Manually", action: continueManually)
                    .buttonStyle(AppActionButtonStyle(.ghost, fillsWidth: false))
            }
        }
        .appSurface(.quiet)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.caution.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("label_scan_failure")
    }
}

struct FoodDetailLabelScanCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(AppPalette.effort)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.effort.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                    .foregroundColor(AppPalette.effort)
                    .frame(width: 38, height: 38)
                    .background(AppPalette.effort.opacity(0.10), in: Circle())

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
                    .foregroundColor(AppPalette.effort)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityHint("Saves this food as the match for this barcode.")
    }
}

final class FoodDetailCorrectionDraft: ObservableObject {
    let originalName: String
    let serving: ServingSizeOption

    @Published var name: String
    @Published var servingDescription: String
    @Published var servingWeight: String
    @Published var calories: String
    @Published var protein: String
    @Published var carbs: String
    @Published var fats: String
    @Published var saturatedFat: String
    @Published var fiber: String
    @Published var micronutrientValues: [MicronutrientKey: String]
    @Published var isMicronutrientsExpanded = false

    init(foodName: String, serving: ServingSizeOption) {
        self.originalName = foodName
        self.serving = serving
        self.name = foodName
        self.servingDescription = serving.description
        self.servingWeight = FoodDetailCorrectionSheet.text(for: serving.servingWeightGrams)
        self.calories = FoodDetailCorrectionSheet.requiredText(for: serving.calories)
        self.protein = FoodDetailCorrectionSheet.requiredText(for: serving.protein)
        self.carbs = FoodDetailCorrectionSheet.requiredText(for: serving.carbs)
        self.fats = FoodDetailCorrectionSheet.requiredText(for: serving.fats)
        self.saturatedFat = FoodDetailCorrectionSheet.text(for: serving.saturatedFat)
        self.fiber = FoodDetailCorrectionSheet.text(for: serving.fiber)
        self.micronutrientValues = Dictionary(
            uniqueKeysWithValues: MicronutrientKey.vitaminAndMineralKeys.map {
                ($0, FoodDetailCorrectionSheet.text(for: FoodDetailCorrectionSheet.value(for: $0, in: serving)))
            }
        )
    }
}

struct FoodDetailCorrectionSheet: View {
    private struct CorrectionChange: Identifiable {
        let id: String
        let title: String
        let before: String
        let after: String
    }

    let serving: ServingSizeOption
    let barcode: String?
    let onCancel: () -> Void
    let onSave: (String, ServingSizeOption) -> Void
    private let originalName: String

    @ObservedObject private var draft: FoodDetailCorrectionDraft

    init(
        draft: FoodDetailCorrectionDraft,
        barcode: String?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, ServingSizeOption) -> Void
    ) {
        self.serving = draft.serving
        self.barcode = barcode
        self.onCancel = onCancel
        self.onSave = onSave
        self.originalName = draft.originalName
        self._draft = ObservedObject(wrappedValue: draft)
    }

    init(
        foodName: String,
        serving: ServingSizeOption,
        barcode: String?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, ServingSizeOption) -> Void
    ) {
        self.init(
            draft: FoodDetailCorrectionDraft(foodName: foodName, serving: serving),
            barcode: barcode,
            onCancel: onCancel,
            onSave: onSave
        )
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedServingDescription: String {
        draft.servingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty &&
            !trimmedServingDescription.isEmpty &&
            doubleValue(draft.calories) != nil &&
            doubleValue(draft.protein) != nil &&
            doubleValue(draft.carbs) != nil &&
            doubleValue(draft.fats) != nil &&
            isValidOptionalNumber(draft.servingWeight) &&
            isValidOptionalNumber(draft.saturatedFat) &&
            isValidOptionalNumber(draft.fiber) &&
            draft.micronutrientValues.values.allSatisfy(isValidOptionalNumber) &&
            saturatedFatValidationMessage == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.group) {
                    correctionHeader
                    identityFields
                    macroFields
                    micronutrientFields
                    if !correctionChanges.isEmpty {
                        changeSummary
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Fix food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let correctedServing else { return }
                        onSave(trimmedName, correctedServing)
                    }
                    .disabled(!canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .flatMap(\.windows)
                            .first(where: \.isKeyWindow)?
                            .endEditing(true)
                    }
                    .accessibilityLabel("Hide keyboard")
                    .accessibilityIdentifier("food_correction_keyboard_done")
                }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("food_correction_sheet")
    }

    private var correctionHeader: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: "pencil.and.scribble")
                .appFont(size: 18, weight: .bold)
                .foregroundStyle(AppPalette.caution)
                .frame(width: 42, height: 42)
                .background(
                    AppPalette.caution.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("Correct food data")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                if let barcode {
                    Text("Barcode \(barcode)")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .appSurface(.interpreted)
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Serving")

            correctionTextField(
                title: "Food name",
                text: $draft.name,
                keyboard: .default,
                identifier: "food_correction_name"
            )
            correctionTextField(
                title: "Serving size",
                text: $draft.servingDescription,
                keyboard: .default,
                identifier: "food_correction_serving"
            )
            correctionTextField(
                title: "Serving weight",
                text: $draft.servingWeight,
                unit: "g",
                keyboard: .decimalPad,
                identifier: "food_correction_weight"
            )
        }
        .appSurface(.quiet)
    }

    private var macroFields: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Core nutrition")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.row) {
                correctionTextField(
                    title: "Calories",
                    text: $draft.calories,
                    unit: "cal",
                    keyboard: .decimalPad,
                    identifier: "food_correction_calories"
                )
                correctionTextField(
                    title: "Protein",
                    text: $draft.protein,
                    unit: "g",
                    keyboard: .decimalPad,
                    identifier: "food_correction_protein"
                )
                correctionTextField(
                    title: "Carbs",
                    text: $draft.carbs,
                    unit: "g",
                    keyboard: .decimalPad,
                    identifier: "food_correction_carbs"
                )
                correctionTextField(
                    title: "Total fat",
                    text: $draft.fats,
                    unit: "g",
                    keyboard: .decimalPad,
                    identifier: "food_correction_fat"
                )
                correctionTextField(
                    title: "Saturated fat",
                    text: $draft.saturatedFat,
                    unit: "g",
                    keyboard: .decimalPad,
                    identifier: "food_correction_saturatedFat"
                )
                correctionTextField(
                    title: "Fiber",
                    text: $draft.fiber,
                    unit: "g",
                    keyboard: .decimalPad,
                    identifier: "food_correction_fiber"
                )
            }

            if let saturatedFatValidationMessage {
                Label(saturatedFatValidationMessage, systemImage: "exclamationmark.circle.fill")
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.critical)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appSurface(.quiet)
    }

    private var micronutrientFields: some View {
        DisclosureGroup(isExpanded: $draft.isMicronutrientsExpanded) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Text("Leave a field blank when the source does not report it. Enter 0 only when the label explicitly reports zero.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                micronutrientCategoryFields(.vitamin)
                micronutrientCategoryFields(.mineral)
            }
            .padding(.top, AppSpacing.row)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    AppSectionHeader(title: "Vitamins & minerals")
                    Text("Optional detailed nutrition")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: AppSpacing.compact)
                Text("\(reportedMicronutrientFieldCount)/\(MicronutrientKey.vitaminAndMineralKeys.count)")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(AppPalette.brand)
        .appSurface(.quiet)
        .accessibilityIdentifier("food_correction_micros")
        .accessibilityValue(draft.isMicronutrientsExpanded ? "Expanded" : "Collapsed")
    }

    private func micronutrientCategoryFields(_ category: MicronutrientCategory) -> some View {
        let keys = category == .vitamin
            ? MicronutrientKey.vitaminKeys
            : MicronutrientKey.mineralKeys

        return VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(category.displayName)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.row) {
                ForEach(keys, id: \.self) { key in
                    correctionTextField(
                        title: key.displayName,
                        text: micronutrientBinding(for: key),
                        unit: key.unit,
                        keyboard: .decimalPad,
                        identifier: "food_correction_\(key.rawValue)"
                    )
                }
            }
        }
    }

    private var changeSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(spacing: AppSpacing.compact) {
                Image(systemName: "arrow.left.arrow.right")
                    .appFont(size: 13, weight: .bold)
                    .foregroundStyle(AppPalette.brandText)
                Text("Changes to Save")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
            }

            ForEach(correctionChanges) { change in
                VStack(alignment: .leading, spacing: 5) {
                    Text(change.title)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(change.before)
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Image(systemName: "arrow.right")
                            .appFont(size: 9, weight: .bold)
                            .foregroundStyle(AppPalette.brandText)
                            .accessibilityHidden(true)
                        Text(change.after)
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.text)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(change.title), \(change.before), changed to \(change.after)")
            }
        }
        .appSurface(.interpreted)
    }

    private var correctionChanges: [CorrectionChange] {
        var changes: [CorrectionChange] = []

        func addText(_ id: String, _ title: String, original: String, current: String) {
            let old = original.trimmingCharacters(in: .whitespacesAndNewlines)
            let new = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard old != new, !new.isEmpty else { return }
            changes.append(CorrectionChange(
                id: id,
                title: title,
                before: old.isEmpty ? "Not reported" : old,
                after: new
            ))
        }

        func addNumber(
            _ id: String,
            _ title: String,
            original: Double?,
            currentText: String,
            unit: String
        ) {
            let current = doubleValue(currentText)
            if let original, let current {
                let tolerance = max(0.0001, abs(original) * 0.00001)
                guard abs(original - current) > tolerance else { return }
            } else if original == nil, current == nil {
                return
            }
            let before = original.map { "\(Self.displayNumber($0)) \(unit)" } ?? "Not reported"
            let after = current.map { "\(Self.displayNumber($0)) \(unit)" } ?? "Not reported"
            changes.append(CorrectionChange(id: id, title: title, before: before, after: after))
        }

        addText("name", "Food name", original: originalName, current: draft.name)
        addText("serving", "Serving", original: serving.description, current: draft.servingDescription)
        addNumber("weight", "Serving weight", original: serving.servingWeightGrams, currentText: draft.servingWeight, unit: "g")
        addNumber("calories", "Calories", original: serving.calories, currentText: draft.calories, unit: "cal")
        addNumber("protein", "Protein", original: serving.protein, currentText: draft.protein, unit: "g")
        addNumber("carbs", "Carbs", original: serving.carbs, currentText: draft.carbs, unit: "g")
        addNumber("fat", "Total fat", original: serving.fats, currentText: draft.fats, unit: "g")
        addNumber("saturated-fat", "Saturated fat", original: serving.saturatedFat, currentText: draft.saturatedFat, unit: "g")
        addNumber("fiber", "Fiber", original: serving.fiber, currentText: draft.fiber, unit: "g")
        for key in MicronutrientKey.vitaminAndMineralKeys {
            addNumber(
                key.rawValue,
                key.displayName,
                original: Self.value(for: key, in: serving),
                currentText: draft.micronutrientValues[key] ?? "",
                unit: key.unit
            )
        }
        return changes
    }

    private var correctedServing: ServingSizeOption? {
        guard canSave,
              let caloriesValue = doubleValue(draft.calories),
              let proteinValue = doubleValue(draft.protein),
              let carbsValue = doubleValue(draft.carbs),
              let fatsValue = doubleValue(draft.fats) else {
            return nil
        }

        return ServingSizeOption(
            description: trimmedServingDescription,
            servingWeightGrams: doubleValue(draft.servingWeight),
            calories: caloriesValue,
            protein: proteinValue,
            carbs: carbsValue,
            fats: fatsValue,
            saturatedFat: doubleValue(draft.saturatedFat),
            polyunsaturatedFat: serving.polyunsaturatedFat,
            monounsaturatedFat: serving.monounsaturatedFat,
            fiber: doubleValue(draft.fiber),
            calcium: micronutrientValue(.calcium),
            iron: micronutrientValue(.iron),
            potassium: micronutrientValue(.potassium),
            sodium: micronutrientValue(.sodium),
            vitaminA: micronutrientValue(.vitaminA),
            vitaminC: micronutrientValue(.vitaminC),
            vitaminD: micronutrientValue(.vitaminD),
            vitaminB12: micronutrientValue(.vitaminB12),
            folate: micronutrientValue(.folate),
            magnesium: micronutrientValue(.magnesium),
            phosphorus: micronutrientValue(.phosphorus),
            zinc: micronutrientValue(.zinc),
            copper: micronutrientValue(.copper),
            manganese: micronutrientValue(.manganese),
            selenium: micronutrientValue(.selenium),
            vitaminB1: micronutrientValue(.vitaminB1),
            vitaminB2: micronutrientValue(.vitaminB2),
            vitaminB3: micronutrientValue(.vitaminB3),
            vitaminB5: micronutrientValue(.vitaminB5),
            vitaminB6: micronutrientValue(.vitaminB6),
            vitaminE: micronutrientValue(.vitaminE),
            vitaminK: micronutrientValue(.vitaminK)
        )
    }

    private func correctionTextField(
        title: String,
        text: Binding<String>,
        unit: String? = nil,
        keyboard: UIKeyboardType,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .appTextRole(.body)
                    .foregroundStyle(AppPalette.text)
                    .accessibilityIdentifier(identifier)

                if let unit {
                    Text(unit)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator.opacity(0.65), lineWidth: 0.5)
            }
        }
    }

    fileprivate static func text(for value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "" }
        return String(format: "%g", value)
    }

    private var reportedMicronutrientFieldCount: Int {
        draft.micronutrientValues.values.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private func micronutrientBinding(for key: MicronutrientKey) -> Binding<String> {
        Binding(
            get: { draft.micronutrientValues[key] ?? "" },
            set: { draft.micronutrientValues[key] = $0 }
        )
    }

    private func micronutrientValue(_ key: MicronutrientKey) -> Double? {
        doubleValue(draft.micronutrientValues[key] ?? "")
    }

    fileprivate static func value(for key: MicronutrientKey, in serving: ServingSizeOption) -> Double? {
        switch key {
        case .fiber: return serving.fiber
        case .calcium: return serving.calcium
        case .iron: return serving.iron
        case .potassium: return serving.potassium
        case .sodium: return serving.sodium
        case .vitaminA: return serving.vitaminA
        case .vitaminC: return serving.vitaminC
        case .vitaminD: return serving.vitaminD
        case .vitaminB12: return serving.vitaminB12
        case .folate: return serving.folate
        case .magnesium: return serving.magnesium
        case .phosphorus: return serving.phosphorus
        case .zinc: return serving.zinc
        case .copper: return serving.copper
        case .manganese: return serving.manganese
        case .selenium: return serving.selenium
        case .vitaminB1: return serving.vitaminB1
        case .vitaminB2: return serving.vitaminB2
        case .vitaminB3: return serving.vitaminB3
        case .vitaminB5: return serving.vitaminB5
        case .vitaminB6: return serving.vitaminB6
        case .vitaminE: return serving.vitaminE
        case .vitaminK: return serving.vitaminK
        }
    }

    fileprivate static func requiredText(for value: Double) -> String {
        String(format: "%g", max(0, value))
    }

    private static func displayNumber(_ value: Double) -> String {
        guard value.isFinite else { return "Invalid" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
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
        guard let saturatedFatValue = doubleValue(draft.saturatedFat),
              let totalFatValue = doubleValue(draft.fats),
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
