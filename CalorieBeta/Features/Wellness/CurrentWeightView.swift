import SwiftUI

struct CurrentWeightView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var weight = ""
    @State private var entryDate = Date()
    @FocusState private var weightFieldFocused: Bool

    private var unit: String { BodyUnits.weightUnit(metric: useMetric) }

    private var enteredValue: Double? {
        guard let value = Double(weight), value > 0 else { return nil }
        return value
    }

    private var lastEntry: (date: Date, weight: Double)? {
        guard let last = goalSettings.weightHistory.sorted(by: { $0.date < $1.date }).last else { return nil }
        return (last.date, last.weight)
    }

    private var changeFromLastEntry: Double? {
        guard let entered = enteredValue, let last = lastEntry else { return nil }
        return BodyUnits.weightToLbs(entered, metric: useMetric) - last.weight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Body Trend",
                        title: "Log Weight",
                        subtitle: "Use the same conditions when possible so the long-term trend stays meaningful."
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Measurement",
                            subtitle: lastEntryDescription
                        )

                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                            TextField("0.0", text: $weight)
                                .keyboardType(.decimalPad)
                                .focused($weightFieldFocused)
                                .appTextRole(.display)
                                .foregroundStyle(AppPalette.text)
                                .monospacedDigit()
                                .accessibilityLabel("Weight in \(unit)")

                            Text(unit)
                                .appTextRole(.control)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }

                        changeContext
                    }
                    .appSurface(.emphasized)

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Entry Date",
                            subtitle: "Backdate the measurement when you are adding it later."
                        )

                        DatePicker(
                            "Measurement date",
                            selection: $entryDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { weightFieldFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save Weight") {
                    saveWeight()
                    dismiss()
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(enteredValue == nil)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(AppPalette.separator).frame(height: 1)
                }
                .accessibilityIdentifier("weight_entry_save")
            }
            .onAppear {
                weight = String(
                    format: "%.1f",
                    BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric)
                )
                weightFieldFocused = true
            }
        }
        .tint(AppPalette.brand)
        .accessibilityIdentifier("weight_entry_screen")
    }

    private var lastEntryDescription: String {
        guard let lastEntry else { return "Your first entry becomes the start of the trend." }
        let value = BodyUnits.weightDisplayValue(lbs: lastEntry.weight, metric: useMetric)
        return "Last logged \(String(format: "%.1f", value)) \(unit) on \(lastEntry.date.formatted(.dateTime.month(.abbreviated).day()))."
    }

    @ViewBuilder
    private var changeContext: some View {
        if let change = changeFromLastEntry, abs(change) >= 0.05 {
            let isDown = change < 0
            Label(
                "\(String(format: "%.1f", abs(BodyUnits.weightDisplayValue(lbs: change, metric: useMetric)))) \(unit) since the last entry",
                systemImage: isDown ? "arrow.down.right" : "arrow.up.right"
            )
            .appTextRole(.secondary)
            .foregroundStyle(isDown ? Color.accentPositive : Color.orange)
            .fixedSize(horizontal: false, vertical: true)
        } else if enteredValue != nil {
            Label("In line with your last entry", systemImage: "equal")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private func saveWeight() {
        guard let value = enteredValue else { return }
        goalSettings.updateUserWeight(
            BodyUnits.weightToLbs(value, metric: useMetric),
            date: entryDate
        )
    }
}
