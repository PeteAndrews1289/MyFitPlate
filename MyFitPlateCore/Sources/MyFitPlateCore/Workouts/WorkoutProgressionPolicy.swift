import Foundation

/// Explicit future-session policy. Missing values retain the legacy conservative evaluator.
public struct WorkoutProgressionPolicy: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case conservativeDouble, linear, percentage, bodyweight, assistance
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .conservativeDouble: "Double progression"
            case .linear: "Linear load progression"
            case .percentage: "Authored percentage targets"
            case .bodyweight: "Bodyweight repetitions"
            case .assistance: "Reduce assistance"
            }
        }
    }
    public var version: Int
    public var kind: Kind
    public var incrementPounds: Double
    public init(kind: Kind = .conservativeDouble, incrementPounds: Double = 5) {
        version = 1; self.kind = kind; self.incrementPounds = incrementPounds
    }
    public var isValid: Bool { version == 1 && incrementPounds.isFinite && (0.25...100).contains(incrementPounds) }
    public func validationMessage(for exercise: RoutineExercise) -> String? {
        guard isValid else { return "Use a supported policy and a load step between 0.25 and 100 lb." }
        switch kind {
        case .assistance:
            return exercise.loadEquipment?.loadingMeaning == .assistance ? nil : "Choose an assistance equipment convention before using this policy."
        case .bodyweight:
            return exercise.loadEquipment?.loadingMeaning == .bodyweightOnly ? nil : "Choose bodyweight-only equipment before using this policy."
        case .percentage:
            return exercise.sets.filter { $0.resolvedSetType == .normal }.allSatisfy {
                $0.prescription?.validationMessage == nil && $0.prescription?.resolvedWeightPounds != nil
            } ? nil : "Give every working set a valid percentage and named reference."
        case .linear, .conservativeDouble:
            return exercise.loadEquipment?.loadingMeaning == .assistance || exercise.loadEquipment?.loadingMeaning == .bodyweightOnly
                ? "Choose the matching assistance or bodyweight policy for this convention." : nil
        }
    }
}
