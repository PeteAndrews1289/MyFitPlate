import SwiftUI

struct StrengthSetInput: Hashable {
    enum Field: Hashable { case weight, reps }
    let setID: String
    let field: Field
}

struct StrengthSetCommand: Equatable {
    enum Action { case increaseWeight, decreaseWeight, increaseReps, decreaseReps, complete }
    let id = UUID()
    let setID: String
    let action: Action
}

private struct WorkoutSetFocusKey: EnvironmentKey {
    static let defaultValue: Binding<StrengthSetInput?>? = nil
}

private struct WorkoutSetCommandKey: EnvironmentKey {
    static let defaultValue: StrengthSetCommand? = nil
}

extension EnvironmentValues {
    var workoutSetFocus: Binding<StrengthSetInput?>? {
        get { self[WorkoutSetFocusKey.self] }
        set { self[WorkoutSetFocusKey.self] = newValue }
    }

    var workoutSetCommand: StrengthSetCommand? {
        get { self[WorkoutSetCommandKey.self] }
        set { self[WorkoutSetCommandKey.self] = newValue }
    }
}
