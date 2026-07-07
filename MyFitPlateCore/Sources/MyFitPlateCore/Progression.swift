import Foundation

/// A next-session suggestion for one lift, derived from how the last session actually went.
public struct ProgressionSuggestion: Equatable, Sendable {
    public enum Move: String, Equatable, Sendable {
        case addWeight   // had reps in reserve — go up in load
        case addRep      // close to target effort — squeeze another rep at the same load
        case hold        // near-max effort or missed the rep goal — repeat and consolidate
    }

    public let move: Move
    public let referenceWeight: Double
    public let suggestedWeight: Double
    public let suggestedReps: Int
    public let headline: String
    public let rationale: String

    public init(move: Move, referenceWeight: Double, suggestedWeight: Double, suggestedReps: Int, headline: String, rationale: String) {
        self.move = move
        self.referenceWeight = referenceWeight
        self.suggestedWeight = suggestedWeight
        self.suggestedReps = suggestedReps
        self.headline = headline
        self.rationale = rationale
    }
}

public enum ProgressionRules {

    /// Suggest the next working-set target from the last session's top working set.
    /// - Parameters:
    ///   - previous: last session's completed exercise (nil → no suggestion).
    ///   - targetReps: the low end of the rep goal (0 means "no explicit target", e.g. AMRAP).
    ///   - weightIncrement: smallest sensible load jump for this lift.
    public static func suggest(
        previous: CompletedExercise?,
        targetReps: Int,
        weightIncrement: Double = 5
    ) -> ProgressionSuggestion? {
        guard let previous else { return nil }
        let working = previous.sets.filter { $0.isWorkingSet && $0.weight > 0 && $0.reps > 0 }
        // Reference off the heaviest set, breaking ties toward more reps.
        guard let top = working.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }

        let goal = max(targetReps, 1)
        let hitReps = top.reps >= goal
        let rpe = top.effort?.normalizedRPE

        func fmtWeight(_ w: Double) -> String {
            w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
        }
        let inc = fmtWeight(weightIncrement)

        // Missed the rep goal → don't add load, earn the reps first.
        if !hitReps {
            return ProgressionSuggestion(
                move: .hold,
                referenceWeight: top.weight,
                suggestedWeight: top.weight,
                suggestedReps: goal,
                headline: "Repeat \(fmtWeight(top.weight))",
                rationale: "You hit \(top.reps) of \(goal) reps last time — lock in the reps before adding weight."
            )
        }

        // Hit the reps. Let effort decide how aggressive the jump is.
        switch rpe {
        case .some(let value) where value >= 9:
            return ProgressionSuggestion(
                move: .hold,
                referenceWeight: top.weight,
                suggestedWeight: top.weight,
                suggestedReps: top.reps,
                headline: "Repeat \(fmtWeight(top.weight))",
                rationale: "Last set was near-max effort — consolidate before going heavier."
            )
        case .some(let value) where value >= 8:
            return ProgressionSuggestion(
                move: .addRep,
                referenceWeight: top.weight,
                suggestedWeight: top.weight,
                suggestedReps: top.reps + 1,
                headline: "Add a rep",
                rationale: "You had about a rep left — same weight, one more rep."
            )
        default:
            // Reps in reserve (RPE ≤ ~7.5) or no effort logged but reps hit → add load.
            return ProgressionSuggestion(
                move: .addWeight,
                referenceWeight: top.weight,
                suggestedWeight: top.weight + weightIncrement,
                suggestedReps: goal,
                headline: "Add \(inc)",
                rationale: rpe == nil
                    ? "You hit your reps — try \(fmtWeight(top.weight + weightIncrement))."
                    : "You left reps in reserve — go up to \(fmtWeight(top.weight + weightIncrement))."
            )
        }
    }

    /// Parse the low end of a rep target string ("8-12" → 8, "5" → 5, "AMRAP" → 0).
    public static func targetRepsLowEnd(_ target: String) -> Int {
        let digits = target.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}
