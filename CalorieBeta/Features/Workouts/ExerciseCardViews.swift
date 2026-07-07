import MyFitPlateCore

import SwiftUI
import ActivityKit

struct ExerciseCardView: View {
    @Binding var exercise: RoutineExercise
    @ObservedObject var restTimer: RestTimer
    @Binding var isAutoRestEnabled: Bool
    var routineName: String
    var previousPerformance: CompletedExercise?
    var onAddNote: () -> Void
    var onSwap: () -> Void
    var onViewHistory: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onRemove: (() -> Void)?
    var supersetPosition: SupersetRules.Position = .standalone
    var onToggleSupersetWithNext: (() -> Void)?

    /// True when this exercise is supersetted with the one after it — the point of a
    /// superset is that you don't rest here, you go straight to the paired lift.
    private var isLinkedToNext: Bool { supersetPosition.isInSuperset && !supersetPosition.isLastInGroup }
    private var suppressAutoRest: Bool { isLinkedToNext }

    @State private var showingTargetRepsEditor = false
    @State private var targetRepsInput = ""

    private var completedSetCount: Int {
        exercise.sets.filter(\.isCompleted).count
    }

    private var totalSetCount: Int {
        exercise.sets.count
    }

    private var exerciseProgress: Double {
        guard totalSetCount > 0 else { return 0 }
        return min(Double(completedSetCount) / Double(totalSetCount), 1)
    }

    private var typeChip: (title: String, icon: String, color: Color) {
        switch exercise.type {
        case .strength:
            return ("Strength", "dumbbell.fill", .blue)
        case .cardio:
            return ("Cardio", "heart.fill", .red)
        case .flexibility:
            return ("Mobility", "figure.cooldown", .cyan)
        }
    }

    private var displayedNote: String? {
        if let sessionNote = exercise.notes, !sessionNote.isEmpty {
            return sessionNote
        }
        return PinnedNotesManager.shared.getPinnedNote(for: exercise.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 12) {
                    Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .background(typeChip.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Label(typeChip.title, systemImage: typeChip.icon)
                                .appFont(size: 11, weight: .bold)
                                .foregroundColor(typeChip.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(typeChip.color.opacity(0.10), in: Capsule())

                            Text("\(completedSetCount)/\(totalSetCount) sets")
                                .appFont(size: 11, weight: .bold)
                                .foregroundColor(Color(UIColor.secondaryLabel))

                            if supersetPosition.isInSuperset, let label = supersetPosition.groupLabel {
                                Label("Superset \(label)", systemImage: "link")
                                    .appFont(size: 11, weight: .bold)
                                    .foregroundColor(.brandPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandPrimary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(exercise.name)
                            .appFont(size: 20, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    exerciseMenu
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(typeChip.color.opacity(0.10))

                        Capsule()
                            .fill(typeChip.color)
                            .frame(width: geometry.size.width * CGFloat(exerciseProgress))
                            .animation(.easeInOut(duration: 0.2), value: exerciseProgress)
                    }
                }
                .frame(height: 6)

                if let note = displayedNote {
                    HStack(spacing: 4) {
                        if PinnedNotesManager.shared.isNotePinned(for: exercise.name) {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                        }
                        Text(note)
                    }
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            switch exercise.type {
            case .strength:
                StrengthExerciseView(
                    exercise: $exercise,
                    previousPerformance: previousPerformance,
                    onSetComplete: { completedIndex in
                        // Auto-fill logic
                        let nextIndex = completedIndex + 1
                        if nextIndex < exercise.sets.count {
                            let completedSet = exercise.sets[completedIndex]
                            if !exercise.sets[nextIndex].isCompleted && exercise.sets[nextIndex].weight == 0 && exercise.sets[nextIndex].reps == 0 {
                                exercise.sets[nextIndex].weight = completedSet.weight
                                exercise.sets[nextIndex].reps = completedSet.reps
                            }
                        }

                        // Auto-start rest timer — but not between the exercises inside a
                        // superset; you go straight to the paired lift and rest after the last.
                        if isAutoRestEnabled && !suppressAutoRest {
                            restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds), routineName: routineName)
                        }
                    }
                )
            case .cardio:
                CardioExerciseView(exercise: $exercise)
            case .flexibility:
                FlexibilityExerciseView(exercise: $exercise)
            }

            Button {
                exercise.sets.append(ExerciseSet())
            } label: {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
        .background(Color.backgroundSecondary.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(supersetPosition.isInSuperset ? Color.brandPrimary.opacity(0.45) : typeChip.color.opacity(0.08),
                        lineWidth: supersetPosition.isInSuperset ? 1.5 : 1)
        )
    }

    private var exerciseMenu: some View {
        HStack(spacing: 8) {
            if restTimer.timeRemaining > 0 {
                Text(restTimer.formattedTime())
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
            } else {
                Button {
                    restTimer.start(duration: TimeInterval(exercise.restTimeInSeconds), routineName: routineName)
                } label: {
                    Image(systemName: "timer")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.brandPrimary.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button("Add Warmup Sets") {
                    let newWarmupSet = ExerciseSet(isWarmup: true)
                    exercise.sets.insert(newWarmupSet, at: 0)
                }
                Button("Add/Edit Note", action: onAddNote)
                if exercise.type == .strength {
                    Button {
                        targetRepsInput = exercise.targetReps
                        showingTargetRepsEditor = true
                    } label: {
                        Label("Edit Target Reps", systemImage: "pencil")
                    }
                }
                Button("Swap Exercise", action: onSwap)
                Button("View Demo & History", action: onViewHistory)
                Toggle("Auto-Rest Timer", isOn: $isAutoRestEnabled)
                if let onToggleSupersetWithNext {
                    Button(action: onToggleSupersetWithNext) {
                        Label(isLinkedToNext ? "Break superset" : "Superset with next", systemImage: "link")
                    }
                }
                if onMoveUp != nil || onMoveDown != nil {
                    Divider()
                    if let onMoveUp {
                        Button(action: onMoveUp) {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                    }
                    if let onMoveDown {
                        Button(action: onMoveDown) {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                    }
                }
                if let onRemove {
                    Divider()
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 32, height: 32)
                    .background(Color.backgroundPrimary.opacity(0.72), in: Circle())
            }
        }
        .alert("Edit Target Reps", isPresented: $showingTargetRepsEditor) {
            TextField("e.g. 8-12", text: $targetRepsInput)
            Button("Save") { exercise.targetReps = targetRepsInput }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved to your routine for future workouts.")
        }
    }
}

struct StrengthExerciseView: View {
    @Binding var exercise: RoutineExercise
    var previousPerformance: CompletedExercise?
    var onSetComplete: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let previousPerformance {
                StrengthProgressionCoachCard(previousPerformance: previousPerformance, targetReps: exercise.targetReps)
            }

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, _ in
                StrengthSetRow(
                    set: $exercise.sets[index],
                    setIndex: index + 1,
                    previousSet: previousPerformance?.sets.indices.contains(index) == true ? previousPerformance?.sets[index] : nil,
                    onComplete: {
                        onSetComplete(index)
                    }
                )
            }
            .onDelete(perform: deleteStrengthSet)
        }
    }

    private func deleteStrengthSet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: offsets)
    }
}

private struct StrengthProgressionCoachCard: View {
    let previousPerformance: CompletedExercise
    var targetReps: String = "8-12"

    /// Autoregulated next-session move derived from last time's top working set + effort.
    private var suggestion: ProgressionSuggestion? {
        ProgressionRules.suggest(
            previous: previousPerformance,
            targetReps: ProgressionRules.targetRepsLowEnd(targetReps)
        )
    }

    private var bestSet: CompletedSet? {
        previousPerformance.sets
            .filter { $0.weight > 0 || $0.reps > 0 }
            .max { lhs, rhs in
                (lhs.weight * Double(max(lhs.reps, 1))) < (rhs.weight * Double(max(rhs.reps, 1)))
            }
    }

    private var guidanceText: String {
        guard let bestSet else {
            return "No prior working set found. Build the first set conservatively and let form guide the jump."
        }

        if bestSet.weight > 0 && bestSet.reps > 0 {
            return "Last best: \(String(format: "%g", bestSet.weight)) lb x \(bestSet.reps). Repeat clean reps first, then add a rep or a small weight jump if it moves well."
        }

        if bestSet.reps > 0 {
            return "Last best: \(bestSet.reps) reps. Match that first, then add one rep if form stays clean."
        }

        return "Use the prior session as a guide and keep the first working set smooth."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(.blue)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                if let suggestion {
                    HStack(spacing: 6) {
                        Text("Next")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text(suggestion.headline)
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.brandPrimary.opacity(0.12), in: Capsule())
                    }
                    Text(suggestion.rationale)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Progression")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text(guidanceText)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.backgroundPrimary.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CardioExerciseView: View {
    @Binding var exercise: RoutineExercise

    var body: some View {
        VStack {
            HStack {
                Text("SET").frame(maxWidth: .infinity, alignment: .leading)
                Text("TARGET").frame(maxWidth: .infinity, alignment: .leading)
                Text("DISTANCE").frame(maxWidth: .infinity, alignment: .center)
                Text("TIME").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(width: 30)
            }
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.secondary)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, _ in
                CardioSetRow(set: $exercise.sets[index], setIndex: index + 1)
            }
            .onDelete(perform: deleteCardioSet)
        }
    }

    private func deleteCardioSet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: offsets)
    }
}

struct FlexibilityExerciseView: View {
    @Binding var exercise: RoutineExercise

    var body: some View {
        VStack {
            HStack {
                Text("SET").frame(maxWidth: .infinity, alignment: .leading)
                Text("TARGET").frame(maxWidth: .infinity, alignment: .leading)
                Text("SECONDS").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(width: 30)
            }
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.secondary)

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, _ in
                FlexibilitySetRow(set: $exercise.sets[index], setIndex: index + 1)
            }
            .onDelete(perform: deleteFlexibilitySet)
        }
    }

    private func deleteFlexibilitySet(at offsets: IndexSet) {
        exercise.sets.remove(atOffsets: offsets)
    }
}

struct SwapExerciseView: View {
    @Binding var exercise: RoutineExercise
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var infoTitle = ""
    @State private var infoText = ""
    @State private var showingInfo = false

    /// Muscle group of the exercise being swapped, if it's a known exercise.
    /// Used to lead with same-group options so a back row doesn't surface chest first.
    private var swappedCategory: String? {
        ExerciseList.category(for: exercise.name)
    }

    private var suggested: [String] {
        let alts = (exercise.alternatives ?? []).filter { $0 != exercise.name }
        guard let group = swappedCategory else { return alts }
        // Same-muscle-group alternatives first (an AI-generated plan can list off-group swaps).
        let sameGroup = alts.filter { ExerciseList.category(for: $0) == group }
        let others = alts.filter { ExerciseList.category(for: $0) != group }
        return sameGroup + others
    }

    private var filteredCategories: [(category: String, exercises: [String])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let group = swappedCategory
        return ExerciseList.categorizedExercises
            .map { (category: $0.key, exercises: $0.value) }
            .map { pair -> (category: String, exercises: [String]) in
                let matches = query.isEmpty ? pair.exercises : pair.exercises.filter { $0.lowercased().contains(query) }
                return (pair.category, matches.filter { $0 != exercise.name })
            }
            .filter { !$0.exercises.isEmpty }
            .sorted { lhs, rhs in
                // Lead with the muscle group being worked, then fall back to alphabetical.
                if let group {
                    if lhs.category == group { return true }
                    if rhs.category == group { return false }
                }
                return lhs.category < rhs.category
            }
    }

    var body: some View {
        NavigationView {
            List {
                if !suggested.isEmpty && searchText.isEmpty {
                    Section(header: Text("Suggested")) {
                        ForEach(suggested, id: \.self) { swapRow($0) }
                    }
                }
                ForEach(filteredCategories, id: \.category) { group in
                    Section(header: Text(group.category)) {
                        ForEach(group.exercises, id: \.self) { swapRow($0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search any exercise")
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(infoTitle, isPresented: $showingInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(infoText)
            }
        }
    }

    private func swapRow(_ name: String) -> some View {
        HStack {
            Button {
                performSwap(to: name)
            } label: {
                HStack {
                    Text(name).foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let how = ExerciseList.instructions(for: name) {
                Button {
                    infoTitle = name
                    infoText = how
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle").foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to perform \(name)")
            }
        }
    }

    private func performSwap(to newName: String) {
        guard newName != exercise.name else { dismiss(); return }
        let originalName = exercise.name
        // Preserve set count + targets, but mint fresh ids so per-set editing stays correct.
        exercise.sets = exercise.sets.map { ExerciseSet(target: $0.target) }
        var alternatives = exercise.alternatives ?? []
        alternatives.removeAll { $0 == newName }
        if !alternatives.contains(originalName) { alternatives.insert(originalName, at: 0) }
        exercise.name = newName
        exercise.alternatives = alternatives
        dismiss()
    }
}

struct StrengthSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int
    var previousSet: CompletedSet?
    var onComplete: () -> Void

    @State private var weightInput: String
    @State private var repsInput: String
    @State private var isPersonalBest = false
    @State private var showingPlateMath = false

    private let weightIncrement: Double = 2.5

    /// Whether this row logs effort as RPE or RIR (the user's Settings choice).
    @AppStorage("liftingEffortMetric") private var effortMetricRaw: String = "rpe"
    private var effortScale: SetEffort.Scale { effortMetricRaw == "rir" ? .rir : .rpe }
    private var effortOptions: [Double] {
        effortScale == .rir ? [0, 1, 2, 3, 4, 5] : [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    }
    /// Convert any stored effort into the currently-selected scale, so a set logged as
    /// RPE still reads correctly when the user prefers RIR (and vice-versa).
    private func effortInScale(_ effort: SetEffort) -> Double {
        if effort.scale == effortScale { return effort.value }
        let rpe = effort.normalizedRPE
        return effortScale == .rpe ? rpe : max(0, 10 - rpe)
    }
    private var effortDisplayValue: Double? {
        guard let effort = set.effort else { return nil }
        return effortInScale(effort)
    }
    private func formatEffort(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
    private var setTypeBinding: Binding<SetType> {
        Binding(get: { set.resolvedSetType }, set: { set.setKind($0) })
    }
    private var setTypeColor: Color {
        switch set.resolvedSetType {
        case .warmup: return .orange
        case .drop: return .brandPrimary
        case .failure: return .red
        case .normal: return .textPrimary
        }
    }

    private var targetText: String {
        self.set.target ?? "Work set"
    }

    private var setLabel: String {
        switch set.resolvedSetType {
        case .warmup: return "Warm-up"
        case .drop: return "Drop set"
        case .failure: return "Failure"
        case .normal: return "Set \(setIndex)"
        }
    }

    private var targetSummary: String {
        let summary = targetTextBeforeProgression()
        return summary.isEmpty ? "Work set" : summary
    }

    private var targetGuidance: String? {
        let normalized = normalizedTargetText()
        guard let range = normalized.range(of: "Progression:", options: .caseInsensitive) else {
            return nil
        }

        let guidance = normalized[range.lowerBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return guidance.isEmpty ? nil : guidance
    }

    private var previousText: String {
        guard let previousSet else { return "No prior set" }
        var text = "Last \(formatWeight(previousSet.weight)) lb x \(previousSet.reps)"
        if let effort = previousSet.effort {
            text += " · \(effortScale == .rir ? "RIR" : "RPE") \(formatEffort(effortInScale(effort)))"
        }
        return text
    }

    private var completionIcon: String {
        return set.isCompleted ? "checkmark.circle.fill" : "circle"
    }

    init(set: Binding<ExerciseSet>, setIndex: Int, previousSet: CompletedSet?, onComplete: @escaping () -> Void) {
        self._set = set
        self.setIndex = setIndex
        self.previousSet = previousSet
        self.onComplete = onComplete

        self._weightInput = State(initialValue: set.wrappedValue.weight > 0 ? String(format: "%g", set.wrappedValue.weight) : "")
        self._repsInput = State(initialValue: set.wrappedValue.reps > 0 ? "\(set.wrappedValue.reps)" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                setTypeMenu

                Text(targetSummary)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                Button(action: fillFromPrevious) {
                    Text(previousText)
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(previousSet == nil ? Color(UIColor.tertiaryLabel) : .textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.backgroundSecondary.opacity(0.78), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(previousSet == nil)
                .accessibilityLabel(previousSet == nil ? "No prior set" : "Fill from \(previousText)")
            }

            if let targetGuidance {
                Text(targetGuidance)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .bottom, spacing: 10) {
                weightInputGroup
                repsInputGroup
                effortInputGroup
                completeButton
            }
        }
        .padding(12)
        .background(Color.backgroundPrimary.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(set.isCompleted ? Color.accentPositive.opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .onChange(of: set.weight) { _, newWeight in
            let currentInputWeight = Double(weightInput) ?? 0
            if newWeight != currentInputWeight {
                weightInput = newWeight > 0 ? String(format: "%g", newWeight) : ""
            }
        }
        .onChange(of: set.reps) { _, newReps in
            let currentInputReps = Int(repsInput) ?? 0
            if newReps != currentInputReps {
                repsInput = newReps > 0 ? "\(newReps)" : ""
            }
        }
        .onAppear {
            // Pre-fill an untouched set from last session's matching set, so a repeat is
            // just "tap the check" instead of starting blank (and risking a 0x0 log).
            guard !set.isCompleted, let previousSet else { return }
            if set.weight == 0 {
                set.weight = previousSet.weight
                weightInput = previousSet.weight > 0 ? String(format: "%g", previousSet.weight) : ""
            }
            if set.reps == 0 {
                set.reps = previousSet.reps
                repsInput = previousSet.reps > 0 ? "\(previousSet.reps)" : ""
            }
        }
    }

    private var weightInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Lbs")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))

                Spacer(minLength: 0)

                Button(action: { showingPlateMath = true }) {
                    Label("Plates", systemImage: "circle.grid.cross")
                        .labelStyle(.iconOnly)
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plate math")
                .accessibilityHint("Shows which plates to load for this weight.")
            }

            HStack(spacing: 6) {
                setAdjustButton(systemName: "minus", label: "Decrease weight") {
                    adjustWeight(by: -weightIncrement)
                }

                TextField("0", text: $weightInput)
                    .accessibilityLabel("Weight")
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .appFont(size: 18, weight: .bold)
                    .frame(height: 44)
                    .background(Color.backgroundSecondary.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: weightInput) {
                        let newWeight = Double(weightInput) ?? 0
                        set.weight = newWeight
                        checkIfPersonalBest(newWeight: newWeight, newRps: set.reps)
                    }

                setAdjustButton(systemName: "plus", label: "Increase weight") {
                    adjustWeight(by: weightIncrement)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingPlateMath) {
            PlateMathVisualizer(totalWeight: set.weight)
        }
    }

    private var repsInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reps")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 6) {
                setAdjustButton(systemName: "minus", label: "Decrease reps") {
                    adjustReps(by: -1)
                }

                TextField("0", text: $repsInput)
                    .accessibilityLabel("Reps")
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .appFont(size: 18, weight: .bold)
                    .frame(height: 44)
                    .background(Color.backgroundSecondary.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: repsInput) {
                        let newReps = Int(repsInput) ?? 0
                        set.reps = newReps
                        checkIfPersonalBest(newWeight: set.weight, newRps: newReps)
                    }

                setAdjustButton(systemName: "plus", label: "Increase reps") {
                    adjustReps(by: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var completeButton: some View {
        VStack(spacing: 6) {
            Text("Done")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            Button(action: toggleCompletion) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: completionIcon)
                        .foregroundColor(set.isCompleted ? .accentPositive : Color(UIColor.secondaryLabel))
                        .font(.system(size: 34, weight: .semibold))

                    if isPersonalBest {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption2)
                            .offset(x: 3, y: -4)
                            .accessibilityLabel("Personal best")
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(setLabel)")
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
        }
        .frame(width: 48)
    }

    private var setTypeMenu: some View {
        Menu {
            Picker("Set type", selection: setTypeBinding) {
                Label("Working set", systemImage: "circle.fill").tag(SetType.normal)
                Label("Warm-up", systemImage: "flame").tag(SetType.warmup)
                Label("Drop set", systemImage: "arrow.down.circle").tag(SetType.drop)
                Label("To failure", systemImage: "bolt.circle").tag(SetType.failure)
            }
        } label: {
            HStack(spacing: 3) {
                Text(setLabel)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(setTypeColor)
                Image(systemName: "chevron.down")
                    .appFont(size: 9, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .accessibilityLabel("Set type: \(setLabel)")
        .accessibilityHint("Change between working, warm-up, drop, or failure set.")
    }

    private var effortInputGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(effortScale == .rir ? "RIR" : "RPE")
                .appFont(size: 11, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            Menu {
                Button("Not logged") { set.effort = nil }
                ForEach(effortOptions, id: \.self) { value in
                    Button(formatEffort(value)) {
                        set.effort = SetEffort(scale: effortScale, value: value)
                    }
                }
            } label: {
                Text(effortDisplayValue.map(formatEffort) ?? "–")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(effortDisplayValue == nil ? Color(UIColor.tertiaryLabel) : .textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.backgroundSecondary.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel(effortScale == .rir ? "Reps in reserve" : "Rate of perceived exertion")
            .accessibilityValue(effortDisplayValue.map(formatEffort) ?? "Not logged")
        }
        .frame(width: 60)
    }

    private func setAdjustButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(width: 32, height: 44)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func fillFromPrevious() {
        guard let prev = previousSet else { return }
        self.weightInput = String(format: "%g", prev.weight)
        self.repsInput = "\(prev.reps)"
        HapticManager.instance.feedback(.light)
    }

    private func normalizedTargetText() -> String {
        targetText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func targetTextBeforeProgression() -> String {
        let normalized = normalizedTargetText()
        guard let range = normalized.range(of: "Progression:", options: .caseInsensitive) else {
            return normalized
        }

        return normalized[..<range.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func adjustWeight(by amount: Double) {
        let currentWeight = Double(weightInput) ?? 0
        let newWeight = max(0, currentWeight + amount)
        self.weightInput = String(format: "%g", newWeight)
        HapticManager.instance.feedback(.light)
    }

    private func adjustReps(by amount: Int) {
        let currentReps = Int(repsInput) ?? 0
        let newReps = max(0, currentReps + amount)
        self.repsInput = "\(newReps)"
        HapticManager.instance.feedback(.light)
    }

    private func toggleCompletion() {
        if !set.isCompleted {
            if set.weight == 0, let previousSet {
                set.weight = previousSet.weight
                weightInput = String(format: "%g", previousSet.weight)
            }

            if set.reps == 0, let targetReps = inferredReps(from: set.target) {
                set.reps = targetReps
                repsInput = "\(targetReps)"
            }
        }

        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
            onComplete()
        }
    }

    private func inferredReps(from target: String?) -> Int? {
        guard let target else { return nil }
        return target
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .first
    }

    private func checkIfPersonalBest(newWeight: Double, newRps: Int) {
        guard let previous = previousSet, newRps > 0, newWeight > 0 else {
            isPersonalBest = false
            return
        }

        if newWeight > previous.weight && newRps >= previous.reps {
            isPersonalBest = true
        } else if newWeight == previous.weight && newRps > previous.reps {
            isPersonalBest = true
        } else {
            isPersonalBest = false
        }
    }
}

struct CardioSetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int

    @State private var distanceInput: String
    @State private var timeInput: String

    init(set: Binding<ExerciseSet>, setIndex: Int) {
        self._set = set
        self.setIndex = setIndex
        self._distanceInput = State(initialValue: set.wrappedValue.distance > 0 ? String(format: "%g", set.wrappedValue.distance) : "")
        self._timeInput = State(initialValue: set.wrappedValue.durationInSeconds > 0 ? "\(set.wrappedValue.durationInSeconds / 60)" : "")
    }

    var body: some View {
        HStack {
            Text("\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.target ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("miles", text: $distanceInput)
                .accessibilityLabel("Distance in miles, set \(setIndex)")
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: distanceInput) {
                    set.distance = Double(distanceInput) ?? 0
                }

            TextField("min", text: $timeInput)
                .accessibilityLabel("Duration in minutes, set \(setIndex)")
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: timeInput) {
                    set.durationInSeconds = (Int(timeInput) ?? 0) * 60
                }

            Button(action: toggleCompletion) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
            }
            .frame(width: 30)
            .accessibilityLabel("Complete set \(setIndex)")
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
        }
        .appFont(size: 14)
    }

    private func toggleCompletion() {
        if !set.isCompleted, set.durationInSeconds == 0, let inferredSeconds = inferredDurationSeconds(from: set.target) {
            set.durationInSeconds = inferredSeconds
            timeInput = "\(max(inferredSeconds / 60, 1))"
        }

        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
        }
    }

    private func inferredDurationSeconds(from target: String?) -> Int? {
        guard let target else { return nil }
        let lowercasedTarget = target.lowercased()
        guard let firstNumber = lowercasedTarget.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first else {
            return nil
        }

        return lowercasedTarget.contains("sec") || lowercasedTarget.contains("s") ? firstNumber : firstNumber * 60
    }
}

struct FlexibilitySetRow: View {
    @Binding var set: ExerciseSet
    let setIndex: Int

    @State private var timeInput: String

    init(set: Binding<ExerciseSet>, setIndex: Int) {
        self._set = set
        self.setIndex = setIndex
        self._timeInput = State(initialValue: set.wrappedValue.durationInSeconds > 0 ? "\(set.wrappedValue.durationInSeconds)" : "")
    }

    var body: some View {
        HStack {
            Text("\(setIndex)")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(set.target ?? "-")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("seconds", text: $timeInput)
                .accessibilityLabel("Duration in seconds, set \(setIndex)")
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .center)
                .onChange(of: timeInput) {
                    set.durationInSeconds = Int(timeInput) ?? 0
                }

            Button(action: toggleCompletion) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(set.isCompleted ? .accentPositive : .secondary)
                    .font(.title2)
            }
            .frame(width: 30)
            .accessibilityLabel("Complete set \(setIndex)")
            .accessibilityValue(set.isCompleted ? "Completed" : "Not completed")
        }
        .appFont(size: 14)
    }

    private func toggleCompletion() {
        if !set.isCompleted, set.durationInSeconds == 0, let inferredSeconds = inferredDurationSeconds(from: set.target) {
            set.durationInSeconds = inferredSeconds
            timeInput = "\(inferredSeconds)"
        }

        set.isCompleted.toggle()
        if set.isCompleted {
            HapticManager.instance.feedback(.medium)
        }
    }

    private func inferredDurationSeconds(from target: String?) -> Int? {
        guard let target else { return nil }
        let lowercasedTarget = target.lowercased()
        guard let firstNumber = lowercasedTarget.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first else {
            return nil
        }

        return lowercasedTarget.contains("min") ? firstNumber * 60 : firstNumber
    }
}
