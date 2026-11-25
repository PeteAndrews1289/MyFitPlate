import SwiftUI

@MainActor
struct CurrentWeightView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var weight = ""
    @State private var entryDate: Date
    @StateObject private var saveSession = WeightSaveSession(userID: DIContainer.shared.authService.currentUserID)
    @State private var seeded = false
    private var isSaving: Bool { saveSession.isSaving }
    @State private var saveError: String?
    @FocusState private var weightFieldFocused: Bool

    init(initialDate: Date = Date()) { _entryDate = State(initialValue: min(initialDate, Date())) }

    private var unit: String { saveSession.draft?.unit ?? BodyUnits.weightUnit(metric: useMetric) }
    private var entryUsesMetric: Bool { saveSession.draft.map { $0.unit == "kg" } ?? useMetric }

    private var enteredValue: Double? {
        let normalized = weight.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    private var lastEntry: (date: Date, weight: Double)? {
        guard let last = goalSettings.weightHistory.sorted(by: { $0.date < $1.date }).last else { return nil }
        return (last.date, last.weight)
    }

    private var changeFromLastEntry: Double? {
        guard let entered = enteredValue, let last = lastEntry else { return nil }
        return BodyUnits.weightToLbs(entered, metric: entryUsesMetric) - last.weight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text(lastEntryDescription)
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                            TextField("0.0", text: $weight)
                                .keyboardType(.decimalPad)
                                .focused($weightFieldFocused)
                                .appTextRole(.display)
                                .foregroundStyle(AppPalette.text)
                                .monospacedDigit()
                                .accessibilityLabel("Weight in \(unit)")
                                .accessibilityIdentifier("weight_entry_value")

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
                        Divider()
                        DatePicker(
                            "Measurement date",
                            selection: $entryDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .appTextRole(.control)
                        .accessibilityIdentifier("weight_entry_date")
                    }
                    .appSurface(.quiet)

                    Text("Similar conditions make your trend easier to compare. Daily fluctuations are normal.")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSaving || saveSession.draft != nil)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { weightFieldFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.compact) {
                    if let error = saveSession.errorMessage {
                        Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                            .accessibilityIdentifier("weight_entry_error")
                    }
                    Button(isSaving ? "Saving…" : saveSession.draft == nil ? "Save weight" : "Retry saving") {
                        saveWeight()
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(enteredValue == nil || isSaving)
                    .accessibilityIdentifier("weight_entry_save")
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(AppPalette.separator).frame(height: 1)
                }
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                if let draft = saveSession.draft {
                    weight = String(format: "%.1f", draft.enteredValue)
                    entryDate = draft.date
                } else { weight = String(
                    format: "%.1f",
                    BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: entryUsesMetric)
                ) }
                weightFieldFocused = true
            }
        }
        .interactiveDismissDisabled(isSaving)
        .alert("Couldn't save weight", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .tint(AppPalette.brandText)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weight_entry_screen")
    }

    private var lastEntryDescription: String {
        guard let lastEntry else { return "Your first entry becomes the start of the trend." }
        let value = BodyUnits.weightDisplayValue(lbs: lastEntry.weight, metric: entryUsesMetric)
        return "Last logged \(String(format: "%.1f", value)) \(unit) on \(lastEntry.date.formatted(.dateTime.month(.abbreviated).day()))."
    }

    @ViewBuilder
    private var changeContext: some View {
        if let change = changeFromLastEntry, abs(change) >= 0.05 {
            let isDown = change < 0
            Label(
                "\(String(format: "%.1f", abs(BodyUnits.weightDisplayValue(lbs: change, metric: entryUsesMetric)))) \(unit) since the last entry",
                systemImage: isDown ? "arrow.down.right" : "arrow.up.right"
            )
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if enteredValue != nil, lastEntry != nil {
            Label("In line with your last entry", systemImage: "equal")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private func saveWeight() {
        guard !isSaving, let value = enteredValue else { return }
        saveSession.save(weightLbs: BodyUnits.weightToLbs(value, metric: entryUsesMetric), enteredValue: value,
                         unit: unit, date: entryDate, using: goalSettings) { accepted in
            if accepted { dismiss() }
        }
    }
}
