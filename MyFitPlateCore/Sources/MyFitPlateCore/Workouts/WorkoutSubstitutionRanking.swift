import Foundation

public struct WorkoutSubstitutionSuggestion: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let score: Int
    public let reasons: [String]
    public let patternVersion: Int
}

/// Curated broad movement roles, never a claim of identical technique, tissue load
/// or suitability for pain. Missing metadata remains unknown rather than fuzzy matched.
public enum WorkoutSubstitutionRanking {
    public enum Intent: String, CaseIterable, Identifiable, Sendable {
        case preserveRole = "Keep this movement role"
        case availableSetup = "Prefer a mapped gym setup"
        case preferredMovement = "Prefer saved favorites"
        public var id: String { rawValue }
    }
    public static let patternVersion = 1
    public static let patterns: [String: [String]] = [
        "Horizontal press": ["Barbell Bench Press", "Dumbbell Bench Press", "Push-up", "Machine Chest Press", "Smith Machine Bench Press", "Close-Grip Bench Press"],
        "Incline press": ["Incline Barbell Bench Press", "Incline Dumbbell Bench Press", "Incline Machine Chest Press"],
        "Decline press": ["Decline Barbell Bench Press", "Decline Dumbbell Bench Press"],
        "Chest adduction": ["Dumbbell Fly", "Incline Dumbbell Fly", "Cable Crossover", "Machine Fly (Pec Deck)"],
        "Vertical press": ["Barbell Overhead Press (Military Press)", "Dumbbell Shoulder Press", "Machine Shoulder Press", "Arnold Press", "Smith Machine Overhead Press"],
        "Vertical pull": ["Pull-up", "Assisted Pull-up", "Chin-up", "Lat Pulldown", "Assisted Chin-up (Machine)"],
        "Horizontal pull": ["Barbell Bent-over Row", "Pendlay Row", "Dumbbell Row", "T-Bar Row", "Seated Cable Row", "Inverted Row", "Chest-Supported Row Machine", "Smith Machine Bent-over Row"],
        "Hip hinge": ["Deadlift (Conventional)", "Sumo Deadlift", "Romanian Deadlift", "Good Mornings"],
        "Squat": ["Barbell Back Squat", "Barbell Front Squat", "Bodyweight Squat", "Goblet Squat (Dumbbell/Kettlebell)", "Hack Squat"],
        "Split stance": ["Bulgarian Split Squat", "Walking Lunge", "Reverse Lunge"],
        "Elbow flexion": ["Barbell Curl", "Dumbbell Curl", "Hammer Curl", "Preacher Curl", "Concentration Curl", "Incline Dumbbell Curl", "Cable Curl", "Machine Bicep Curl", "Machine Preacher Curl", "Reverse Barbell Curl"],
        "Elbow extension": ["Skull Crusher (Lying Triceps Extension)", "Triceps Pushdown (Cable)", "Overhead Triceps Extension (Dumbbell/Cable)", "Triceps Kickback", "Triceps Extension Machine"],
        "Lateral raise": ["Dumbbell Lateral Raise", "Cable Lateral Raise", "Machine Lateral Raise"],
        "Rear shoulder": ["Dumbbell Rear Delt Fly", "Reverse Pec Deck (Rear Delt Machine)", "Face Pull"],
        "Shoulder elevation": ["Barbell Shrug", "Dumbbell Shrug"],
        "Trunk hold": ["Plank", "Side Plank"]
    ]

    public static func pattern(for name: String) -> String? {
        guard let canonical = WorkoutMovementCatalog.canonicalName(name) else { return nil }
        return patterns.keys.sorted().first { patterns[$0]?.contains(canonical) == true }
    }

    public static func suggestions(
        for source: RoutineExercise, gym: StrengthGymProfile? = nil,
        confirmedMovements: [String: StrengthEquipment] = [:], favorites: Set<String> = [],
        reason: WorkoutSubstitutionProvenance.Reason = .preference, intent: Intent = .preserveRole, limit: Int = 12) -> [WorkoutSubstitutionSuggestion] {
        let sourceName = WorkoutMovementCatalog.canonicalName(source.name) ?? source.name
        let sourcePattern = pattern(for: sourceName)
        let category = ExerciseList.entries.first { $0.name == sourceName }?.category
        let authored = Set((source.alternatives ?? []).compactMap(WorkoutMovementCatalog.canonicalName))
        let validGym = gym.flatMap { $0.isValid ? $0 : nil }
        return ExerciseList.entries.compactMap { entry -> WorkoutSubstitutionSuggestion? in
            guard entry.name != sourceName else { return nil }
            let samePattern = sourcePattern != nil && sourcePattern == pattern(for: entry.name)
            guard authored.contains(entry.name) || samePattern || (category != nil && entry.category == category) else { return nil }
            let sameType = RoutineEditorDefaults.inferredType(name: entry.name, category: entry.category) == source.type
            guard sameType || authored.contains(entry.name) else { return nil }
            var score = sameType ? 10 : -100
            var reasons: [String] = []
            if authored.contains(entry.name) { score += 180; reasons.append("Listed by this plan") }
            if samePattern { score += intent == .preserveRole ? 100 : 60; reasons.append("Same broad role: \(sourcePattern ?? "")") } else { reasons.append("Same primary category; movement role needs review") }
            if sameType { reasons.append("Keeps the measurement type; review the target and intent") }
            let key = WorkoutMovementSelectionStore.key(name: entry.name, identity: WorkoutMovementCatalog.identity(for: entry.name))
            if favorites.contains(key) { score += intent == .preferredMovement ? 110 : 30; reasons.append("Your saved favorite") }
            if let setup = confirmedMovements[entry.name], setup.isValid,
               let reference = setup.gymProfile, let validGym,
               reference.profileID == validGym.id, reference.revisionID == validGym.revisionID,
               validGym.equipment(for: reference.implementID) == setup {
                score += intent == .availableSetup ? 150 : 90; reasons.append("Exact movement/setup already mapped in \(validGym.name)")
                if reason == .occupied || reason == .unavailable,
                   source.loadEquipment?.gymProfile?.profileID == reference.profileID,
                   source.loadEquipment?.gymProfile?.implementID == reference.implementID {
                    score -= 160; reasons.append("Uses the implement you are replacing; confirm it is usable")
                }
            } else if WorkoutPlanningEligibility.isEligible(entry.name, for: .floorOnly) {
                score += 55; reasons.append("Floor-only catalog movement")
            } else if let validGym {
                let bar = ExerciseList.equipment(for: entry.name) == .barbell
                let hasCandidateImplement = validGym.implements.contains { bar ? $0.equipment.kind == .barbell : $0.equipment.kind == .fixedWeights }
                score += hasCandidateImplement ? 10 : -50
                reasons.append(hasCandidateImplement ? "Some implement inventory is listed; exact movement, bench and attachments are unconfirmed" : "No matching implement class listed in this gym")
            } else { reasons.append("Equipment availability unconfirmed") }
            return WorkoutSubstitutionSuggestion(name: entry.name, score: score, reasons: reasons, patternVersion: patternVersion)
        }.sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
            .prefix(max(0, min(30, limit))).map { $0 }
    }
}
