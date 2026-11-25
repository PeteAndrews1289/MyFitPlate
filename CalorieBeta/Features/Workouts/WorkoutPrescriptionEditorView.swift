import MyFitPlateCore
import SwiftUI

struct WorkoutPrescriptionEditorView: View {
    let exerciseType: ExerciseType
    let set: ExerciseSet
    let onSave: (ExerciseSet) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WorkoutPrescription.Kind
    @State private var lower: String
    @State private var upper: String
    @State private var written: String
    @State private var notes: String
    @State private var usesEffort: Bool
    @State private var effortScale: SetEffort.Scale
    @State private var effortValue: String
    @State private var usesPercentage: Bool
    @State private var percentage: String
    @State private var referenceName: String
    @State private var referenceWeight: String
    @State private var referenceDate: Date

    init(exerciseType: ExerciseType, set: ExerciseSet, onSave: @escaping (ExerciseSet) -> Void) {
        self.exerciseType = exerciseType; self.set = set; self.onSave = onSave
        let target = set.prescription ?? WorkoutPrescription.legacy(set.target, type: exerciseType)
            ?? WorkoutPrescription(kind: .manual, originalText: set.target)
        _kind = State(initialValue: target.kind)
        _lower = State(initialValue: target.lowerBound.map(Self.editableNumber) ?? "")
        _upper = State(initialValue: target.upperBound.map(Self.editableNumber) ?? "")
        _written = State(initialValue: target.originalText ?? set.target ?? "")
        _notes = State(initialValue: target.notes ?? "")
        _usesEffort = State(initialValue: target.effort != nil)
        _effortScale = State(initialValue: target.effort?.scale ?? .rpe)
        _effortValue = State(initialValue: target.effort.map { Self.editableNumber($0.value) } ?? "8")
        _usesPercentage = State(initialValue: target.loadPercentage != nil)
        _percentage = State(initialValue: target.loadPercentage.map(Self.editableNumber) ?? "75")
        _referenceName = State(initialValue: target.loadReference?.label ?? "")
        _referenceWeight = State(initialValue: target.loadReference.map { Self.editableNumber($0.weightPounds) } ?? "")
        _referenceDate = State(initialValue: target.loadReference?.date ?? Date())
    }

    private var availableKinds: [WorkoutPrescription.Kind] {
        switch exerciseType {
        case .strength: [.repetitions, .amrap, .manual]
        case .cardio: [.duration, .distance, .manual]
        case .flexibility: [.duration, .manual]
        }
    }

    private var target: WorkoutPrescription {
        WorkoutPrescription(kind: kind,
            lowerBound: StrengthSetEntryRules.weight(from: lower), upperBound: upper.trimmed.isEmpty ? nil : StrengthSetEntryRules.weight(from: upper),
            effort: usesEffort ? SetEffort(scale: effortScale, value: StrengthSetEntryRules.weight(from: effortValue) ?? .nan) : nil,
            notes: notes.trimmed.isEmpty ? nil : notes, originalText: kind == .manual ? written : set.target,
            loadPercentage: usesPercentage ? StrengthSetEntryRules.weight(from: percentage) ?? .nan : nil,
            loadReference: usesPercentage ? .init(label: referenceName, weightPounds: StrengthSetEntryRules.weight(from: referenceWeight) ?? .nan,
                                                  date: referenceDate) : nil)
    }

    private var validation: String? {
        if !availableKinds.contains(kind) { return "Choose a target supported by this movement type." }
        if !upper.trimmed.isEmpty && StrengthSetEntryRules.weight(from: upper) == nil { return "Enter a valid upper target or leave it empty." }
        return target.validationMessage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Picker("Measure", selection: $kind) {
                        ForEach(availableKinds, id: \.self) { Text(title($0)).tag($0) }
                    }.accessibilityIdentifier("prescription_kind")
                    .onChange(of: kind) { _, newValue in
                        if newValue != .repetitions && newValue != .amrap { usesPercentage = false }
                    }
                    if kind == .manual {
                        TextField("Written target", text: $written, axis: .vertical)
                            .accessibilityIdentifier("prescription_written")
                    } else if kind == .amrap {
                        Text("Perform as many reps as intended, then record your actual reps in the workout.")
                            .foregroundStyle(.secondary)
                    } else {
                        labelledField(lowerLabel, prompt: "Required", text: $lower, identifier: "prescription_lower")
                        labelledField(upperLabel, prompt: "Leave empty for a single target", text: $upper, identifier: "prescription_upper")
                    }
                }
                if exerciseType == .strength && kind != .manual {
                    Section("Optional load") {
                        Toggle("Percentage of a reference", isOn: $usesPercentage)
                            .accessibilityIdentifier("prescription_use_percentage")
                        if usesPercentage { referenceFields }
                    }
                }
                Section("Optional effort") {
                    Toggle("Prescribe effort", isOn: $usesEffort).accessibilityIdentifier("prescription_use_effort")
                    if usesEffort {
                        Picker("Scale", selection: $effortScale) {
                            Text("RPE").tag(SetEffort.Scale.rpe); Text("RIR").tag(SetEffort.Scale.rir)
                        }.pickerStyle(.segmented)
                        labelledField(effortScale == .rpe ? "RPE, 1–10" : "RIR, 0–10", prompt: "Target effort",
                                      text: $effortValue, identifier: "prescription_effort")
                    }
                    Text("Actual effort is logged during your workout.")
                        .foregroundStyle(.secondary)
                }
                Section("Setup and tempo notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
                if validation == nil {
                    Section("Preview") {
                        Text(target.summary).accessibilityIdentifier("prescription_preview")
                        if let pounds = target.resolvedWeightPounds {
                            Text("Reference load: \(pounds.formatted(.number.precision(.fractionLength(0...2)))) lb")
                            Text("Review the load against the equipment available for this session.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityIdentifier("prescription_editor_form")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Set prescription").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let validation { Text(validation).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
                    Button("Use target") {
                        var updated = set
                        updated.prescription = target; updated.target = target.targetText
                        onSave(updated); dismiss()
                    }
                    .buttonStyle(AppActionButtonStyle(.primary)).disabled(validation != nil)
                    .accessibilityIdentifier("prescription_save")
                }
                .padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.compact).background(.bar)
            }
        }
    }

    private var referenceFields: some View {
        Group {
            labelledField("Percentage, 1–200", prompt: "75", text: $percentage, identifier: "prescription_percentage")
            labelledField("Reference name", prompt: "e.g. Squat training max", text: $referenceName,
                          identifier: "prescription_reference_name", numeric: false)
            labelledField("Reference weight in lb", prompt: "Required", text: $referenceWeight,
                          identifier: "prescription_reference_weight")
            DatePicker("Reference date", selection: $referenceDate, displayedComponents: .date)
        }
    }

    private var lowerLabel: String {
        switch kind {
        case .repetitions: "Minimum reps"
        case .duration: "Minimum seconds"
        case .distance: "Minimum metres"
        default: "Target"
        }
    }

    private var upperLabel: String {
        switch kind {
        case .repetitions: "Maximum reps (optional)"
        case .duration: "Maximum seconds (optional)"
        case .distance: "Maximum metres (optional)"
        default: "Maximum target (optional)"
        }
    }

    private func labelledField(_ label: String, prompt: String, text: Binding<String>, identifier: String, numeric: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).appFont(size: 13, weight: .medium).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(prompt, text: text)
                .keyboardType(numeric ? .decimalPad : .default)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }

    private func title(_ kind: WorkoutPrescription.Kind) -> String {
        switch kind {
        case .repetitions: "Repetitions or range"
        case .duration: "Duration or range"
        case .distance: "Distance or range"
        case .amrap: "AMRAP"
        case .manual: "Written target"
        }
    }

    private static func editableNumber(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }
}
