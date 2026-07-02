import SwiftUI

// DESIGN.md: one hero (the weight you're entering, big), one filled CTA (Save weight),
// context instead of chrome (your last entry, right where you're typing the new one).
struct CurrentWeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @State private var weight = ""
    @State private var entryDate = Date()
    @Environment(\.dismiss) var dismiss
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
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text("Today's weight")
                            .appFont(size: 13, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("0.0", text: $weight)
                                .keyboardType(.decimalPad)
                                .focused($weightFieldFocused)
                                .appFont(size: 44, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.center)
                                .fixedSize()
                                .monospacedDigit()
                                .accessibilityLabel("Weight in \(unit)")

                            Text(unit)
                                .appFont(size: 17, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }

                        if let change = changeFromLastEntry, abs(change) >= 0.05 {
                            let down = change < 0
                            HStack(spacing: 4) {
                                Image(systemName: down ? "arrow.down.right" : "arrow.up.right")
                                    .appFont(size: 11, weight: .bold)
                                Text("\(String(format: "%.1f", abs(BodyUnits.weightDisplayValue(lbs: change, metric: useMetric)))) \(unit) since your last entry")
                                    .appFont(size: 12, weight: .semibold)
                            }
                            .foregroundColor(down ? .accentPositive : .orange)
                        } else if let last = lastEntry {
                            Text("Last entry \(String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: last.weight, metric: useMetric))) \(unit) · \(last.date.formatted(.dateTime.month(.abbreviated).day()))")
                                .appFont(size: 12, weight: .medium)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .asCard()

                    DatePicker("Date", selection: $entryDate, in: ...Date(), displayedComponents: .date)
                        .appFont(size: 15, weight: .semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .asCard()

                    Button("Save weight") {
                        saveWeight()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(enteredValue == nil)
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                weight = String(format: "%.1f", BodyUnits.weightDisplayValue(lbs: goalSettings.weight, metric: useMetric))
                weightFieldFocused = true
            }
        }
    }

    private func saveWeight() {
        guard let value = enteredValue else { return }
        goalSettings.updateUserWeight(BodyUnits.weightToLbs(value, metric: useMetric), date: entryDate)
    }
}
