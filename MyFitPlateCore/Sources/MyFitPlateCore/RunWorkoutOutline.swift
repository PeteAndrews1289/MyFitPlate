import Foundation

/// Authoring structure; recordings execute its exact bounded expansion. A group
/// edit never mutates the plan snapshot already held by a recorder or result.
public indirect enum RunWorkoutOutlineItem: Codable, Equatable, Identifiable {
    case step(RunWorkoutStep)
    case group(RunWorkoutOutlineGroup)

    public var id: String {
        switch self {
        case .step(let step): return step.id
        case .group(let group): return group.id
        }
    }
}

public struct RunWorkoutOutlineGroup: Codable, Equatable, Identifiable {
    public let id: String
    public var repetitions: Int
    public var children: [RunWorkoutOutlineItem]

    public init(id: String = UUID().uuidString, repetitions: Int, children: [RunWorkoutOutlineItem]) {
        self.id = id
        self.repetitions = repetitions
        self.children = children
    }
}

public enum RunWorkoutOutline {
    /// At most three nested groups and 150 executed steps. Source identities must
    /// be unique; each repetition gets a deterministic derived identity.
    public static func expanded(_ outline: [RunWorkoutOutlineItem]) throws -> [RunWorkoutStep] {
        var identities = Set<String>()
        try validate(outline, groupDepth: 0, identities: &identities)
        var expanded: [RunWorkoutStep] = []
        try append(outline, prefix: "", output: &expanded)
        guard !expanded.isEmpty else { throw invalid("Add at least one step.") }
        return expanded
    }

    private static func validate(_ outline: [RunWorkoutOutlineItem], groupDepth: Int, identities: inout Set<String>) throws {
        guard !outline.isEmpty, outline.count <= 150 else { throw invalid("A group needs 1–150 steps or groups.") }
        for item in outline {
            guard !item.id.isEmpty, item.id.count <= 160, identities.insert(item.id).inserted,
                  identities.count <= 150 else { throw invalid("Steps and groups need distinct identities, with at most 150 authored items.") }
            if case .group(let group) = item {
                guard groupDepth < 3, (1...50).contains(group.repetitions) else {
                    throw invalid("Use up to three nested groups, each repeated 1–50 times.")
                }
                try validate(group.children, groupDepth: groupDepth + 1, identities: &identities)
            }
        }
    }

    private static func append(_ items: [RunWorkoutOutlineItem], prefix: String, output: inout [RunWorkoutStep]) throws {
        for item in items {
            switch item {
            case .step(let step):
                guard output.count < 150 else { throw invalid("This outline expands beyond 150 steps. Reduce the repeats.") }
                output.append(RunWorkoutStep(id: prefix + step.id, kind: step.kind, title: step.title, goal: step.goal, target: step.target))
            case .group(let group):
                for repetition in 1...group.repetitions {
                    try append(group.children, prefix: "\(prefix)\(group.id).\(repetition)/", output: &output)
                }
            }
        }
    }

    private static func invalid(_ message: String) -> RunWorkoutPlanStore.SaveError { .invalidPlan(message) }
}
