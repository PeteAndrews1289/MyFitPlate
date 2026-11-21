import MyFitPlateCore
import SwiftUI

struct TrainingFuelIndividualInputsView: View {
    @Binding var inputs: TrainingFuelPersonalInputs?
    let session: TrainingFuelSession
    let weightHistory: [(id: String, date: Date, weight: Double)]
    let now: Date
    @State private var expanded: Bool

    init(inputs: Binding<TrainingFuelPersonalInputs?>, session: TrainingFuelSession,
         weightHistory: [(id: String, date: Date, weight: Double)], now: Date, initiallyExpanded: Bool = false) {
        _inputs = inputs; self.session = session; self.weightHistory = weightHistory; self.now = now
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var estimate: TrainingFuelDemandPreview? {
        inputs.map { TrainingFuelIndividualEstimateRules.preview(session: session, inputs: $0, now: now) }
    }
    private var eligibleWeight: (id: String, date: Date, weight: Double)? {
        weightHistory.filter { !$0.id.isEmpty && $0.weight.isFinite && (30...300).contains($0.weight * 0.45359237) &&
            $0.date <= now && now.timeIntervalSince($0.date) <= 30 * 24 * 60 * 60 }.max { $0.date < $1.date }
    }
    var body: some View {
        DisclosureGroup("Personalize this estimate", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Use reviewed personal inputs", isOn: Binding(get: { inputs != nil }, set: { inputs = $0 ? .init() : nil }))
                    .accessibilityIdentifier("fuel_personalize")
                if inputs != nil {
                    Text("General adult training guidance. Daily protein intake matters more than precise timing. This does not assess your health or prescribe a requirement.").font(.caption).foregroundStyle(.secondary)
                    Toggle("I am an adult and want general training estimates", isOn: binding(\.adultConfirmed, fallback: false))
                        .accessibilityIdentifier("fuel_adult_confirm")
                    if let weight = eligibleWeight {
                        Button("Use \((weight.weight * 0.45359237).formatted(.number.precision(.fractionLength(1)))) kg measured \(weight.date.formatted(date: .abbreviated, time: .omitted))") {
                            inputs?.bodyMass = .init(kilograms: weight.weight * 0.45359237, measurementID: weight.id, measuredAt: weight.date, confirmedAt: now)
                            inputs?.reviewedProteinGrams = nil
                        }.accessibilityIdentifier("fuel_confirm_weight")
                        Text("Choose this only if the measurement is still representative. Profile defaults are not used.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No supported measurement from the last 30 days. Log a current weight to use a bodyweight reference; the general plan remains available.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let range = estimate?.bodyMassProteinReference {
                        Text("One protein serving reference: \(number(range.lower))–\(number(range.upper)) g for your confirmed weight. The commonly described serving range is 20–40 g; it is shown separately.").font(.subheadline)
                        Stepper(value: Binding(get: { Int(inputs?.reviewedProteinGrams ?? ceil(range.lower)) }, set: { inputs?.reviewedProteinGrams = Double($0) }),
                            in: Int(ceil(range.lower))...Int(floor(range.upper))) {
                            Text("Choose \(number(inputs?.reviewedProteinGrams ?? ceil(range.lower))) g across this plan")
                        }.accessibilityIdentifier("fuel_chosen_protein")
                        Text("One chosen amount is split across before and after. This is not a complete daily target or evidence that separate meals are covered.").font(.caption).foregroundStyle(.secondary)
                    } else if inputs?.bodyMass != nil {
                        Text("The measurement or confirmation is outside this version's supported bounds. Review it again before using an individual reference.").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("I know when I last ate", isOn: Binding(get: { inputs?.lastMealAt != nil }, set: { inputs?.lastMealAt = $0 ? now.addingTimeInterval(-7_200) : nil }))
                    if inputs?.lastMealAt != nil {
                        DatePicker("Last meal", selection: Binding(get: { inputs?.lastMealAt ?? now }, set: { inputs?.lastMealAt = $0 }),
                            in: now.addingTimeInterval(-86_400)...now, displayedComponents: [.date, .hourAndMinute])
                        Text("Consider the size and timing of that meal. This time alone does not subtract food or prove a recovery need.").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Food tolerance preference", selection: binding(\.tolerance, fallback: .noPreference)) {
                        Text("No preference stated").tag(TrainingFuelPersonalInputs.Tolerance.noPreference)
                        Text("Lighter foods preferred").tag(TrainingFuelPersonalInputs.Tolerance.lighterFoods)
                        Text("Practiced during-run strategy").tag(TrainingFuelPersonalInputs.Tolerance.practicedDuringRun)
                    }
                    if session.kind == .run {
                        Picker("During-run carbohydrate", selection: Binding(get: { inputs?.duringCarbsPerHour ?? 0 }, set: { inputs?.duringCarbsPerHour = $0 == 0 ? nil : $0 })) {
                            Text("Not planned").tag(0.0)
                            Text("I use 30 g per hour").tag(30.0)
                            Text("I use 45 g per hour").tag(45.0)
                            Text("I use 60 g per hour").tag(60.0)
                        }.accessibilityIdentifier("fuel_during_rate")
                        Text("Optional for 75–150-minute runs within one day, using a practiced strategy. Other durations and overnight runs need separate review; no fluid or sodium target is inferred.").font(.caption).foregroundStyle(.secondary)
                        if let grams = estimate?.requestedDuringCarbGrams {
                            Text("During-run choice: \(number(grams)) g before the daily budget is applied.")
                        } else if inputs?.duringCarbsPerHour != nil {
                            Text("This during-run choice is outside the supported timing or needs adult and practiced-strategy confirmation. No during target will be added.").foregroundStyle(AppPalette.caution).font(.caption)
                        }
                    }
                    Text("This version supports confirmed measurements of 30–300 kg from the last 30 days, with confirmation in the past 24 hours. These are software bounds, not health thresholds.").font(.caption).foregroundStyle(.secondary)
                    Link("Why these reference ranges? ISSN nutrient timing", destination: URL(string: "https://link.springer.com/article/10.1186/s12970-017-0189-4")!)
                    Link("AIS endurance carbohydrate guidance", destination: URL(string: "https://www.ausport.gov.au/ais/nutrition/supplements/group_a/sports-foods2/sports-drink/how-and-when-do-i-use-it")!)
                }
            }.padding(.top, 8)
        }
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<TrainingFuelPersonalInputs, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { inputs?[keyPath: keyPath] ?? fallback }, set: { inputs?[keyPath: keyPath] = $0 })
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}
