import MyFitPlateCore
import SwiftUI

struct StrengthEquipmentSetupView: View {
    let exerciseName: String
    let hasCompletedSets: Bool
    let offersGymProfiles: Bool
    let onSave: (StrengthEquipment?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var kind: StrengthEquipment.Kind
    @State private var unit: StrengthEquipment.Unit
    @State private var meaning: StrengthEquipment.LoadingMeaning
    @State private var equipmentName: String
    @State private var weightsText: String
    @State private var barText: String
    @State private var platesText: String
    @State private var rangeStart = "5"
    @State private var rangeEnd = "100"
    @State private var rangeStep = "5"
    @State private var errorMessage: String?
    @State private var showingGymPicker = false
    @State private var profileReference: StrengthGymProfileReference?
    @State private var canonicalFields: [EquipmentField: CanonicalSnapshot]
    @FocusState private var focusedField: String?
    private let original: StrengthEquipment?

    private enum EquipmentField: String, CaseIterable, Hashable {
        case weights, plates, bar, rangeStart, rangeEnd, rangeStep
    }

    private struct CanonicalSnapshot {
        let text: String
        let unit: StrengthEquipment.Unit
        let pounds: [Double]
    }

    init(exerciseName: String, equipment: StrengthEquipment?, hasCompletedSets: Bool = false, offersGymProfiles: Bool = true,
         onSave: @escaping (StrengthEquipment?) throws -> Void) {
        self.exerciseName = exerciseName
        self.hasCompletedSets = hasCompletedSets
        self.offersGymProfiles = offersGymProfiles
        self.onSave = onSave
        original = equipment
        let displayUnit = equipment?.unit ?? .lb
        _kind = State(initialValue: equipment?.kind ?? .fixedWeights)
        _unit = State(initialValue: displayUnit)
        _meaning = State(initialValue: equipment?.loadingMeaning ?? .asLogged)
        _equipmentName = State(initialValue: equipment?.name ?? "")
        _profileReference = State(initialValue: equipment?.gymProfile)
        let weights = equipment?.availableWeights ?? Array(stride(from: 5.0, through: 100.0, by: 5))
        let bar = equipment?.barWeight ?? 45
        let plates = equipment?.plates ?? [45, 25, 10, 5, 2.5]
        let weightsText = Self.weightList(weights, unit: displayUnit)
        let barText = Self.number(displayUnit.displayWeight(bar))
        let platesText = Self.weightList(plates, unit: displayUnit)
        _weightsText = State(initialValue: weightsText)
        _barText = State(initialValue: barText)
        _platesText = State(initialValue: platesText)
        _canonicalFields = State(initialValue: [
            .weights: CanonicalSnapshot(text: weightsText, unit: displayUnit, pounds: weights),
            .bar: CanonicalSnapshot(text: barText, unit: displayUnit, pounds: [bar]),
            .plates: CanonicalSnapshot(text: platesText, unit: displayUnit, pounds: plates),
            .rangeStart: CanonicalSnapshot(text: "5", unit: displayUnit, pounds: [displayUnit.storedWeight(5)]),
            .rangeEnd: CanonicalSnapshot(text: "100", unit: displayUnit, pounds: [displayUnit.storedWeight(100)]),
            .rangeStep: CanonicalSnapshot(text: "5", unit: displayUnit, pounds: [displayUnit.storedWeight(5)])
        ])
    }

    private var equipment: StrengthEquipment? {
        let weights = canonicalValues(for: .weights)
        let bar = canonicalValues(for: .bar)?.first
        let plates = canonicalValues(for: .plates)
        if kind == .fixedWeights && weights == nil { return nil }
        if kind == .barbell && (bar == nil || plates == nil) { return nil }
        let name = equipmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = StrengthEquipment(kind: kind, unit: unit, loadingMeaning: meaning,
                                          name: name.isEmpty ? nil : name, availableWeights: meaning == .bodyweightOnly ? [0] : weights ?? [],
                                          barWeight: bar ?? 0, plates: plates ?? [], gymProfile: profileReference)
        return candidate.isValid ? candidate : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exerciseName).appTextRole(.control)
                    if original == nil {
                        Text(offersGymProfiles
                             ? "Match your targets to the weights you can actually use. This setup is remembered on this device for this exercise and routine."
                             : "Configure this implement, then save the gym profile to keep its inventory. Changes here stay in the profile draft until that save.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }
                if original != nil { availableEquipmentSection }
                Section("Quick setup") { presets }
                Section {
                    Picker("Units", selection: unitBinding) {
                        Text("lb").tag(StrengthEquipment.Unit.lb)
                        Text("kg").tag(StrengthEquipment.Unit.kg)
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("equipment_units")
                    weightMeaningMenu
                    Text(meaningExplanation).appTextRole(.secondary).foregroundStyle(.secondary)
                } header: {
                    Text("How you record weight")
                } footer: {
                    Text("Switching units converts the same weights.")
                }
                if offersGymProfiles {
                    Section("Saved gyms") {
                        Button("Use saved gym equipment") { showingGymPicker = true }
                            .frame(minHeight: 44).accessibilityIdentifier("equipment_open_gyms")
                        if let profileReference {
                            Text("\(profileReference.profileName) · \(profileReference.implementName)")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        Text("This keeps a snapshot for this exercise. Changing the gym library later does not change this session.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                if original == nil { availableEquipmentSection }
                Section("Available loads") {
                    if let equipment {
                        Text(loadSummary(equipment)).appTextRole(.secondary)
                            .accessibilityIdentifier("equipment_load_summary")
                    } else {
                        Text("Review the available weights to preview your loads.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    Text("Your entered results stay yours. These weights constrain automatic targets and quick weight adjustments.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                if original != nil, offersGymProfiles {
                    Section {
                        Button("Use manual loads") { save(nil) }
                            .accessibilityIdentifier("equipment_manual")
                        Text("This clears your remembered setup. Future sessions use your program's defaults.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityIdentifier("strength_equipment_form")
            .disabled(hasCompletedSets)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas)
            .navigationTitle("Equipment setup").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(hasCompletedSets ? "Done" : "Cancel") { dismiss() } }
                if focusedField != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { focusedField = nil }
                            .accessibilityIdentifier("equipment_finish_edit")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }.accessibilityIdentifier("equipment_keyboard_done")
                }
            }
            // A moving footer can cover the focused multiline field as the keyboard
            // appears. Finish the edit with Done before showing the save action.
            .safeAreaInset(edge: .bottom) { if focusedField == nil { footer } }
            .onChange(of: kind) { _, _ in focusedField = nil }
            .sheet(isPresented: $showingGymPicker) {
                StrengthGymEquipmentPickerView { selected in
                    kind = selected.kind; unit = selected.unit; meaning = selected.loadingMeaning
                    equipmentName = selected.name ?? ""; profileReference = selected.gymProfile
                    setCanonical(selected.availableWeights, for: .weights)
                    setCanonical([selected.barWeight], for: .bar)
                    setCanonical(selected.plates, for: .plates)
                    focusedField = nil
                }
            }
        }
    }

    private var availableEquipmentSection: some View {
        Section("Available equipment") {
            Picker("Equipment", selection: $kind) {
                Text("Fixed weights").tag(StrengthEquipment.Kind.fixedWeights)
                Text("Bar + plates").tag(StrengthEquipment.Kind.barbell)
            }.accessibilityIdentifier("equipment_kind")
            TextField("Optional equipment name", text: $equipmentName)
                .textInputAutocapitalization(.words).autocorrectionDisabled()
                .focused($focusedField, equals: "name")
                .accessibilityIdentifier("equipment_name")
            Text("Name a specific machine or rack when its weights should have their own history.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            if kind == .fixedWeights { fixedWeights } else { barbellWeights }
        }
    }

    private var weightMeaningMenu: some View {
        Menu {
            Picker("Weight means", selection: $meaning) {
                ForEach(StrengthEquipment.LoadingMeaning.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack {
                Text("Weight means")
                Spacer()
                Text(meaning.title).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").appTextRole(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weight means")
        .accessibilityValue(meaning.title)
        .accessibilityIdentifier("equipment_meaning")
    }

    private var presets: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: AppSpacing.row))
         : AnyLayout(HStackLayout(spacing: AppSpacing.row))) {
            Button("Dumbbells") { preset(.fixedWeights, machine: false) }
                .accessibilityIdentifier("equipment_preset_dumbbells")
            Button("Machine") { preset(.fixedWeights, machine: true) }
                .accessibilityIdentifier("equipment_preset_machine")
            Button("Barbell") { preset(.barbell, machine: false) }
                .accessibilityIdentifier("equipment_preset_barbell")
        }
        .buttonStyle(.bordered)
        .tint(AppPalette.text)
        .frame(minHeight: 44)
    }

    private var meaningExplanation: String {
        switch meaning {
        case .asLogged: return "Keep the meaning used in your past entries. Saved numbers are not reinterpreted."
        case .total: return "Record the full external load, including the bar when used. A new convention needs new comparable history."
        case .perHand: return "Record the weight of one dumbbell or implement. A new convention needs new comparable history."
        case .assistance: return "Record the assistance supplied by the machine. Less assistance represents a harder effort; previous total or added loads are separate history."
        case .bodyweightOnly: return "Record repetitions with zero external load. Bodyweight is not counted as lifted external weight."
        case .added: return "Record only the added external load, leaving bodyweight out. A new convention needs new comparable history."
        }
    }

    private var fixedWeights: some View {
        Group {
            listHeading("Weights (\(unit.rawValue))", text: fieldBinding(.weights), focus: "weights", identifier: "equipment_clear_weights")
            TextField("For example, 5 10 15 20", text: fieldBinding(.weights), axis: .vertical)
                .lineLimit(2...5).keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focusedField, equals: "weights")
                .accessibilityLabel("Available weights in \(unit.rawValue)")
                .accessibilityIdentifier("equipment_weights")
            Text("Enter every available weight in \(unit.rawValue), separated by spaces or semicolons. For dumbbells, list the weight of one dumbbell.")
                .appTextRole(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Build a weight range") {
                rangeField("From", value: fieldBinding(.rangeStart), identifier: "equipment_range_start")
                rangeField("Through", value: fieldBinding(.rangeEnd), identifier: "equipment_range_end")
                rangeField("Step", value: fieldBinding(.rangeStep), identifier: "equipment_range_step")
                Button("Use range", action: applyRange).accessibilityIdentifier("equipment_use_range")
            }
        }
    }

    private var barbellWeights: some View {
        Group {
            rangeField("Bar weight", value: fieldBinding(.bar), identifier: "equipment_bar_weight")
            listHeading("Plate pairs (\(unit.rawValue))", text: fieldBinding(.plates), focus: "plates", identifier: "equipment_clear_plates")
            TextField("For example, 45 25 10 5 2.5", text: fieldBinding(.plates), axis: .vertical)
                .lineLimit(2...5).keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focusedField, equals: "plates")
                .accessibilityLabel("Plate pairs in \(unit.rawValue)")
                .accessibilityIdentifier("equipment_plates")
            Text("List one plate size for each matching pair, in \(unit.rawValue). Enter a size twice when you have two pairs. The bar is included in the total load.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }
    }

    private func listHeading(_ title: String, text: Binding<String>, focus: String, identifier: String) -> some View {
        HStack {
            Text(title).appTextRole(.secondary)
            Spacer(minLength: AppSpacing.row)
            Button {
                text.wrappedValue = ""
                focusedField = focus
            } label: {
                Text("Clear").appTextRole(.secondary)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(text.wrappedValue.isEmpty)
            .accessibilityLabel("Clear \(title.lowercased())").accessibilityIdentifier(identifier)
        }
    }

    private func rangeField(_ label: String, value: Binding<String>, identifier: String) -> some View {
        LabeledContent("\(label) (\(unit.rawValue))") {
            TextField(label, text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .focused($focusedField, equals: identifier)
                .frame(minHeight: 44).accessibilityLabel("\(label) in \(unit.rawValue)").accessibilityIdentifier(identifier)
        }
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.compact) {
            if hasCompletedSets {
                Text("Equipment is fixed after this exercise has completed sets. Review it before logging your first set in the next session.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            } else if let errorMessage {
                Text(errorMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("equipment_error")
            } else if equipment == nil {
                Text("Enter valid weights and review the equipment before saving.")
                    .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("equipment_validation")
            }
            Button(offersGymProfiles ? "Save equipment" : "Use implement") { save(equipment) }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(equipment == nil || hasCompletedSets).accessibilityIdentifier("equipment_save")
        }.padding(AppSpacing.row).background(AppPalette.canvas)
    }

    private var unitBinding: Binding<StrengthEquipment.Unit> {
        Binding(get: { unit }, set: { next in
            guard next != unit else { return }
            let values = Dictionary(uniqueKeysWithValues: EquipmentField.allCases.compactMap { field -> (EquipmentField, [Double])? in
                guard let pounds = canonicalValues(for: field) else { return nil }
                return (field, pounds)
            })
            guard kind == .fixedWeights ? values[.weights] != nil : values[.plates] != nil && values[.bar] != nil else {
                errorMessage = "Finish entering valid weights before changing units."
                return
            }
            unit = next
            for (field, pounds) in values { setCanonical(pounds, for: field) }
            errorMessage = nil
        })
    }

    /// Formatting is display-only. Reuse exact values until a person edits that field.
    private func canonicalValues(for field: EquipmentField) -> [Double]? {
        let text = text(for: field)
        if let saved = canonicalFields[field], saved.unit == unit, saved.text == text { return saved.pounds }
        if field == .weights || field == .plates { return parsedWeights(text) }
        return StrengthSetEntryRules.weight(from: text).map { [unit.storedWeight($0)] }
    }

    private func fieldBinding(_ field: EquipmentField) -> Binding<String> {
        Binding(get: { text(for: field) }, set: { value in
            guard value != text(for: field) else { return }
            canonicalFields[field] = nil
            setText(value, for: field)
        })
    }

    private func setCanonical(_ pounds: [Double], for field: EquipmentField) {
        let text = Self.weightList(pounds, unit: unit)
        setText(text, for: field)
        canonicalFields[field] = CanonicalSnapshot(text: text, unit: unit, pounds: pounds)
    }

    private func text(for field: EquipmentField) -> String {
        switch field {
        case .weights: return weightsText
        case .plates: return platesText
        case .bar: return barText
        case .rangeStart: return rangeStart
        case .rangeEnd: return rangeEnd
        case .rangeStep: return rangeStep
        }
    }

    private func setText(_ text: String, for field: EquipmentField) {
        switch field {
        case .weights: weightsText = text
        case .plates: platesText = text
        case .bar: barText = text
        case .rangeStart: rangeStart = text
        case .rangeEnd: rangeEnd = text
        case .rangeStep: rangeStep = text
        }
    }

    private func parsedWeights(_ text: String) -> [Double]? {
        let parts = text.split { $0.isWhitespace || $0 == ";" }
        guard parts.count <= 256 else { return nil }
        var values: [Double] = []
        for part in parts {
            guard let value = StrengthSetEntryRules.weight(from: String(part)) else { return nil }
            values.append(unit.storedWeight(value))
        }
        return values
    }

    private func applyRange() {
        guard let start = canonicalValues(for: .rangeStart)?.first,
              let end = canonicalValues(for: .rangeEnd)?.first,
              let step = canonicalValues(for: .rangeStep)?.first,
              step > 0, end >= start, (end - start) / step < 100 else {
            errorMessage = "Choose a positive step and a range of at most 100 weights."
            return
        }
        let count = Int((((end - start) / step) + 0.000000001).rounded(.down))
        setCanonical((0...count).map { start + Double($0) * step }, for: .weights)
        errorMessage = nil
    }

    private func preset(_ kind: StrengthEquipment.Kind, machine: Bool) {
        profileReference = nil
        self.kind = kind
        let metric = unit == .kg
        if kind == .barbell {
            setCanonical([unit.storedWeight(metric ? 20 : 45)], for: .bar)
            let plates = metric ? [20.0, 15, 10, 5, 2.5, 1.25] : [45.0, 25, 10, 5, 2.5]
            setCanonical(plates.map(unit.storedWeight), for: .plates)
        } else {
            let start = metric && !machine ? 2.0 : 5.0
            let end = machine ? (metric ? 100.0 : 200.0) : (metric ? 50.0 : 100.0)
            let step = metric && !machine ? 2.0 : 5.0
            setCanonical(stride(from: start, through: end, by: step).map(unit.storedWeight), for: .weights)
        }
        errorMessage = nil
    }

    private func loadSummary(_ equipment: StrengthEquipment) -> String {
        let loads = equipment.attainableLoads
        guard let first = loads.first, let last = loads.last else { return "Review your available weights." }
        return "\(loads.count.formatted()) loads · \(Self.number(unit.displayWeight(first)))–\(Self.number(unit.displayWeight(last))) \(unit.rawValue)"
    }

    private func save(_ value: StrengthEquipment?) {
        guard !hasCompletedSets else { return }
        focusedField = nil
        do { try onSave(value); dismiss() } catch { errorMessage = error.localizedDescription }
    }

    private static func weightList(_ pounds: [Double], unit: StrengthEquipment.Unit) -> String {
        pounds.map { number(unit.displayWeight($0)) }.joined(separator: " ")
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }
}
