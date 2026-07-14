import MyFitPlateCore
import SwiftUI

struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var targetFieldIsFocused: Bool

    @State private var targetWeight: String
    private let locksTarget: Bool

    init(initialTargetWeight: Double? = nil, locksTarget: Bool = false) {
        _targetWeight = State(initialValue: initialTargetWeight.map(Self.weightText) ?? "")
        self.locksTarget = locksTarget
    }

    private var parsedTarget: Double? {
        let normalized = targetWeight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private var loadout: PlateLoadout? {
        guard let parsedTarget else { return nil }
        return PlateLoadingRules.loadout(targetWeight: parsedTarget)
    }

    var body: some View {
        NavigationStack {
            AppSheetScaffold(
                title: "Plate Loading",
                subtitle: "Build both sides of a 45 lb bar.",
                dismiss: { dismiss() }
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        targetSection
                        resultSection
                        methodNote
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.group)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { targetFieldIsFocused = false }
                }
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("plate_calculator_screen")
    }

    @ViewBuilder
    private var targetSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Target Weight",
                subtitle: locksTarget
                    ? "Using the weight entered for this set."
                    : "Enter the total weight, including the bar."
            )

            if locksTarget {
                HStack(alignment: .firstTextBaseline) {
                    Text(parsedTarget.map(Self.weightText) ?? "--")
                        .appTextRole(.metric)
                        .monospacedDigit()
                    Text("lb")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .appSurface(.emphasized)
            } else {
                HStack(spacing: AppSpacing.row) {
                    Button(action: { adjustTarget(by: -5) }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .disabled((parsedTarget ?? 0) <= PlateLoadingRules.standardBarWeight)
                    .accessibilityLabel("Decrease target by 5 pounds")

                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        TextField("225", text: $targetWeight)
                            .keyboardType(.decimalPad)
                            .appTextRole(.metric)
                            .monospacedDigit()
                            .focused($targetFieldIsFocused)
                            .accessibilityLabel("Target weight in pounds")
                            .accessibilityIdentifier("plate_calculator_input")

                        Text("lb")
                            .appTextRole(.control)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, AppSpacing.group)
                    .frame(minHeight: 52)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control)
                            .stroke(AppPalette.separator, lineWidth: 1)
                    }

                    Button(action: { adjustTarget(by: 5) }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .accessibilityLabel("Increase target by 5 pounds")
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if targetWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            calculatorMessage(
                icon: "circle.grid.cross",
                title: "Enter a Target",
                message: "The loadout will show the plates needed on each side."
            )
        } else if let target = parsedTarget,
                  target < PlateLoadingRules.standardBarWeight ||
                  target > PlateLoadingRules.maximumSupportedWeight ||
                  !target.isFinite {
            calculatorMessage(
                icon: "exclamationmark.triangle.fill",
                title: "Check the Weight",
                message: "Use a total between 45 and 10,000 lb."
            )
        } else if let loadout {
            loadoutContent(loadout)
        } else {
            calculatorMessage(
                icon: "exclamationmark.triangle.fill",
                title: "Check the Weight",
                message: "Enter a numeric total that includes the 45 lb bar."
            )
        }
    }

    private func loadoutContent(_ loadout: PlateLoadout) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Target",
                    value: "\(Self.weightText(loadout.targetWeight)) lb",
                    accent: AppPalette.brand
                ),
                AppMetricItem(
                    label: "Loaded",
                    value: "\(Self.weightText(loadout.loadedWeight)) lb",
                    accent: .blue
                ),
                AppMetricItem(
                    label: "Fit",
                    value: loadout.isExact ? "Exact" : "\(Self.weightText(loadout.difference)) lb under",
                    accent: loadout.isExact ? .accentPositive : .orange
                )
            ])
            .appSurface(.emphasized)
            .accessibilityIdentifier("plate_calculator_summary")

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Plates Per Side",
                    subtitle: loadout.isExact
                        ? "The requested weight can be loaded exactly."
                        : "The closest supported load is shown; do not treat it as the requested total."
                )

                if loadout.platesPerSide.isEmpty {
                    calculatorMessage(
                        icon: "minus",
                        title: "Bar Only",
                        message: "No plates are needed for a 45 lb total."
                    )
                } else {
                    PlateLoadDiagram(loadout: loadout)

                    VStack(spacing: 0) {
                        ForEach(Array(loadout.platesPerSide.enumerated()), id: \.element.id) { index, plate in
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.group) {
                                Circle()
                                    .fill(PlateLoadDiagram.color(for: plate.weight))
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)

                                Text("\(Self.weightText(plate.weight)) lb plate")
                                    .appTextRole(.control)
                                    .foregroundStyle(AppPalette.text)

                                Spacer(minLength: AppSpacing.compact)

                                Text("\(plate.countPerSide.formatted()) per side")
                                    .appTextRole(.control)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, AppSpacing.group)
                            .padding(.vertical, AppSpacing.row)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(plate.countPerSide) \(Self.weightText(plate.weight)) pound " +
                                "\(plate.countPerSide == 1 ? "plate" : "plates") per side"
                            )

                            if index < loadout.platesPerSide.count - 1 {
                                Divider().padding(.leading, AppSpacing.group)
                            }
                        }
                    }
                    .appSurface(.quiet, padding: 0)
                    .accessibilityIdentifier("plate_calculator_loadout")
                }
            }
        }
    }

    private func calculatorMessage(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(icon == "exclamationmark.triangle.fill" ? Color.orange : AppPalette.brand)
                .frame(width: 36, height: 36)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(message)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet)
    }

    private var methodNote: some View {
        Label {
            Text("Counts are for each side of a standard 45 lb bar. Collars are not included.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func adjustTarget(by amount: Double) {
        let current = parsedTarget ?? PlateLoadingRules.standardBarWeight
        let adjusted = min(
            PlateLoadingRules.maximumSupportedWeight,
            max(PlateLoadingRules.standardBarWeight, current + amount)
        )
        targetWeight = Self.weightText(adjusted)
    }

    fileprivate static func weightText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct PlateLoadDiagram: View {
    let loadout: PlateLoadout

    private var renderedPlates: [Double] {
        Array(loadout.platesPerSide.flatMap { plate in
            Array(repeating: plate.weight, count: plate.countPerSide)
        }.prefix(8))
    }

    private var hiddenPlateCount: Int {
        max(0, loadout.platesPerSide.reduce(0) { $0 + $1.countPerSide } - renderedPlates.count)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(UIColor.systemGray3))
                    .frame(width: 48, height: 18)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(UIColor.systemGray2))
                    .frame(width: 10, height: 42)

                ForEach(Array(renderedPlates.enumerated()), id: \.offset) { _, weight in
                    PlateGlyph(weight: weight)
                }

                if hiddenPlateCount > 0 {
                    Text("+\(hiddenPlateCount)")
                        .appTextRole(.control)
                        .foregroundStyle(.secondary)
                        .padding(.leading, AppSpacing.compact)
                }
            }
            .padding(.horizontal, AppSpacing.group)
            .frame(minHeight: 122)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            loadout.platesPerSide.map {
                "\($0.countPerSide) \(PlateCalculatorView.weightText($0.weight)) pound per side"
            }.joined(separator: ", ")
        )
    }

    static func color(for weight: Double) -> Color {
        switch weight {
        case 45: .blue
        case 35: .yellow
        case 25: .green
        case 10: .gray
        case 5: .orange
        case 2.5: .red
        default: .gray
        }
    }
}

private struct PlateGlyph: View {
    let weight: Double

    private var height: CGFloat {
        switch weight {
        case 45: 104
        case 35: 92
        case 25: 80
        case 10: 66
        case 5: 54
        case 2.5: 46
        default: 60
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(PlateLoadDiagram.color(for: weight))
            .frame(width: max(14, min(24, height / 4.5)), height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
            }
    }
}
