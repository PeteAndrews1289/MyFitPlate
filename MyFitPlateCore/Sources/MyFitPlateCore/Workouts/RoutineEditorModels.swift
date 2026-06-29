import Foundation
import SwiftUI

public enum RoutineMoveDirection {
    case up
    case down
}

public struct ExercisePickerDraft {
    public let name: String
    public let category: String?
    public let type: ExerciseType

    public init(name: String, category: String?, type: ExerciseType) {
        self.name = name
        self.category = category
        self.type = type
    }
}

public struct ExercisePickerEntry: Identifiable, Comparable {
    public var id: String { "\(category)-\(name)" }
    public let name: String
    public let category: String

    public init(name: String, category: String) {
        self.name = name
        self.category = category
    }

    public static func < (lhs: ExercisePickerEntry, rhs: ExercisePickerEntry) -> Bool {
        if lhs.category == rhs.category {
            return lhs.name < rhs.name
        }
        return lhs.category < rhs.category
    }
}

public struct RoutineEditorExerciseSpec: Identifiable {
    public var id: String { name }
    public let name: String
    public let category: String?
    public let type: ExerciseType

    public init(name: String, category: String?, type: ExerciseType) {
        self.name = name
        self.category = category
        self.type = type
    }
}

public struct RoutineEditorTemplate: Identifiable {
    public let id = UUID()
    public let name: String
    public let subtitle: String
    public let icon: String
    public let color: Color
    public let exercises: [RoutineEditorExerciseSpec]

    public static let templates: [RoutineEditorTemplate] = [
        RoutineEditorTemplate(
            name: "Push Day",
            subtitle: "Chest, shoulders, triceps",
            icon: "arrow.up.forward.circle.fill",
            color: .brandPrimary,
            exercises: [
                RoutineEditorExerciseSpec(name: "Barbell Bench Press", category: "Chest", type: .strength),
                RoutineEditorExerciseSpec(name: "Dumbbell Shoulder Press", category: "Shoulders", type: .strength),
                RoutineEditorExerciseSpec(name: "Incline Dumbbell Bench Press", category: "Chest", type: .strength),
                RoutineEditorExerciseSpec(name: "Triceps Pushdown (Cable)", category: "Triceps", type: .strength)
            ]
        ),
        RoutineEditorTemplate(
            name: "Pull Day",
            subtitle: "Back, biceps, rear delts",
            icon: "arrow.down.backward.circle.fill",
            color: .accentPositive,
            exercises: [
                RoutineEditorExerciseSpec(name: "Pull-up", category: "Back", type: .strength),
                RoutineEditorExerciseSpec(name: "Barbell Bent-over Row", category: "Back", type: .strength),
                RoutineEditorExerciseSpec(name: "Face Pull", category: "Shoulders", type: .strength),
                RoutineEditorExerciseSpec(name: "Dumbbell Curl", category: "Biceps", type: .strength)
            ]
        ),
        RoutineEditorTemplate(
            name: "Lower Body",
            subtitle: "Squat, hinge, single leg",
            icon: "figure.strengthtraining.traditional",
            color: .orange,
            exercises: [
                RoutineEditorExerciseSpec(name: "Barbell Back Squat", category: "Legs", type: .strength),
                RoutineEditorExerciseSpec(name: "Romanian Deadlift (RDL)", category: "Legs", type: .strength),
                RoutineEditorExerciseSpec(name: "Bulgarian Split Squat", category: "Legs", type: .strength),
                RoutineEditorExerciseSpec(name: "Standing Calf Raise", category: "Legs", type: .strength)
            ]
        ),
        RoutineEditorTemplate(
            name: "Conditioning",
            subtitle: "Short cardio and core finisher",
            icon: "heart.fill",
            color: .red,
            exercises: [
                RoutineEditorExerciseSpec(name: "Rowing Machine", category: "Cardio", type: .cardio),
                RoutineEditorExerciseSpec(name: "Jump Rope", category: "Cardio", type: .cardio),
                RoutineEditorExerciseSpec(name: "Plank", category: "Abs & Core", type: .flexibility),
                RoutineEditorExerciseSpec(name: "Burpees", category: "Cardio", type: .cardio)
            ]
        )
    ]
}

public enum RoutineEditorDefaults {
    public static func defaults(for type: ExerciseType) -> (sets: Int, target: String, rest: Int) {
        switch type {
        case .strength:
            return (3, "8-12", 90)
        case .cardio:
            return (1, "20 min", 0)
        case .flexibility:
            return (3, "45 sec", 30)
        }
    }

    public static func setTarget(for type: ExerciseType, target: String) -> String {
        let trimmedTarget = target.trimmed
        guard !trimmedTarget.isEmpty else {
            return defaults(for: type).target
        }

        switch type {
        case .strength:
            let lower = trimmedTarget.lowercased()
            if lower.contains("rep") || lower.contains("amrap") || lower.contains("sec") || lower.contains("min") {
                return trimmedTarget
            }
            return "\(trimmedTarget) reps"
        case .cardio, .flexibility:
            return trimmedTarget
        }
    }

    public static func inferredType(name: String, category: String?) -> ExerciseType {
        if category == "Cardio" {
            return .cardio
        }

        let lower = name.lowercased()
        if lower.contains("run") || lower.contains("cycling") || lower.contains("bike") || lower.contains("elliptical") || lower.contains("row") || lower.contains("swim") || lower.contains("jump rope") || lower.contains("burpee") || lower.contains("stair") {
            return .cardio
        }

        if lower.contains("plank") || lower.contains("yoga") || lower.contains("stretch") || lower.contains("mobility") {
            return .flexibility
        }

        return .strength
    }

    public static func restLabel(_ seconds: Int) -> String {
        if seconds <= 0 { return "No rest" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
    }
}

public extension ExerciseType {
    var shortTitle: String {
        switch self {
        case .strength: return "Strength"
        case .cardio: return "Cardio"
        case .flexibility: return "Mobility"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "heart.fill"
        case .flexibility: return "figure.flexibility"
        }
    }

    var color: Color {
        switch self {
        case .strength: return .brandPrimary
        case .cardio: return .red
        case .flexibility: return .blue
        }
    }

    var targetLabel: String {
        switch self {
        case .strength: return "Target Reps"
        case .cardio: return "Target Duration or Distance"
        case .flexibility: return "Target Hold"
        }
    }

    var targetPlaceholder: String {
        switch self {
        case .strength: return "8-12"
        case .cardio: return "20 min or 2 miles"
        case .flexibility: return "45 sec"
        }
    }

    var restPresets: [Int] {
        switch self {
        case .strength: return [60, 90, 120, 180]
        case .cardio: return [0, 30, 60, 90]
        case .flexibility: return [0, 15, 30, 45]
        }
    }
}

public extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension Array where Element == String {
    var nilIfEmpty: [String]? {
        isEmpty ? nil : self
    }
}
