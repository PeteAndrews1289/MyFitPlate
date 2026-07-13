import Foundation

public enum WeekInMotionObservationTone: String, Equatable, Sendable {
    case neutral
    case positive
    case attention
}

public enum WeekInMotionObservationKind: String, Equatable, Sendable {
    case quiet
    case trainingCoverage = "training_coverage"
    case recovery
    case hardDayFuel = "hard_day_fuel"
    case trust
    case progress
    case connected
    case diaryCoverage = "diary_coverage"
}

public struct WeekInMotionObservation: Equatable, Sendable {
    public let kind: WeekInMotionObservationKind
    public let title: String
    public let text: String
    public let basis: String
    public let tone: WeekInMotionObservationTone

    public init(
        kind: WeekInMotionObservationKind,
        title: String,
        text: String,
        basis: String,
        tone: WeekInMotionObservationTone
    ) {
        self.kind = kind
        self.title = title
        self.text = text
        self.basis = basis
        self.tone = tone
    }
}

/// Editorial projection of `WeeklyRecap`. It preserves the recap's explicit denominators and
/// emits one bounded observation rather than a composite score or open-ended recommendation.
public struct WeekInMotion: Equatable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let days: [WeeklyRecapDay]
    public let headline: String
    public let trainingSummary: String
    public let fuelSummary: String
    public let recoverySummary: String
    public let trustSummary: String
    public let trainingCoverage: WeeklyRecapProgress
    public let diaryCoverage: WeeklyRecapProgress
    public let recoveryProgress: WeeklyRecapProgress
    public let trustProgress: WeeklyRecapProgress
    public let observation: WeekInMotionObservation

    public init(
        weekStart: Date,
        weekEnd: Date,
        days: [WeeklyRecapDay],
        headline: String,
        trainingSummary: String,
        fuelSummary: String,
        recoverySummary: String,
        trustSummary: String,
        trainingCoverage: WeeklyRecapProgress,
        diaryCoverage: WeeklyRecapProgress,
        recoveryProgress: WeeklyRecapProgress,
        trustProgress: WeeklyRecapProgress,
        observation: WeekInMotionObservation
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.days = days
        self.headline = headline
        self.trainingSummary = trainingSummary
        self.fuelSummary = fuelSummary
        self.recoverySummary = recoverySummary
        self.trustSummary = trustSummary
        self.trainingCoverage = trainingCoverage
        self.diaryCoverage = diaryCoverage
        self.recoveryProgress = recoveryProgress
        self.trustProgress = trustProgress
        self.observation = observation
    }
}

public enum WeekInMotionBuilder {
    public static func build(from recap: WeeklyRecap) -> WeekInMotion {
        let trainingCoverage = WeeklyRecapProgress(
            completed: recap.trainingDaysLogged,
            eligible: recap.trainingDays
        )
        let diaryCoverage = WeeklyRecapProgress(completed: recap.daysLogged, eligible: 7)

        return WeekInMotion(
            weekStart: recap.weekStart,
            weekEnd: recap.weekEnd,
            days: recap.days,
            headline: recap.story.headline,
            trainingSummary: trainingSummary(recap),
            fuelSummary: fuelSummary(recap),
            recoverySummary: recoverySummary(recap),
            trustSummary: trustSummary(recap),
            trainingCoverage: trainingCoverage,
            diaryCoverage: diaryCoverage,
            recoveryProgress: recap.recoveryFuelAdherence,
            trustProgress: recap.trustReview,
            observation: observation(recap)
        )
    }

    private static func trainingSummary(_ recap: WeeklyRecap) -> String {
        guard recap.trainingDays > 0 else {
            return "No strength sessions or runs were recorded."
        }
        let strength = recap.workoutsCompleted == 1
            ? "1 strength session"
            : "\(recap.workoutsCompleted) strength sessions"
        let runs = recap.runCount == 1 ? "1 run" : "\(recap.runCount) runs"
        return "\(recap.trainingDays) active \(dayWord(recap.trainingDays)); \(strength) and \(runs)."
    }

    private static func fuelSummary(_ recap: WeeklyRecap) -> String {
        if recap.trainingDays > 0 {
            return "Food was logged on \(recap.trainingDaysLogged) of \(recap.trainingDays) training \(dayWord(recap.trainingDays))."
        }
        return "Food was logged on \(recap.daysLogged) of 7 days."
    }

    private static func recoverySummary(_ recap: WeeklyRecap) -> String {
        if recap.recoveryFuelAdherence.eligible > 0 {
            let pending = recap.recoveryFuelPendingRuns > 0
                ? " \(recap.recoveryFuelPendingRuns) additional \(windowWord(recap.recoveryFuelPendingRuns)) still open."
                : ""
            return "\(recoveryCoverageText(recap)).\(pending)"
        }
        if recap.recoveryFuelPendingRuns > 0 {
            return "\(recap.recoveryFuelPendingRuns) run recovery \(windowWord(recap.recoveryFuelPendingRuns)) still open and unscored."
        }
        return "No completed run recovery window was available to assess."
    }

    private static func trustSummary(_ recap: WeeklyRecap) -> String {
        guard recap.trustReview.eligible > 0 else {
            return "No logged food entries required Trust review."
        }
        return "\(recap.trustReview.completed) of \(recap.trustReview.eligible) review-needed entries were confirmed or corrected."
    }

    private static func observation(_ recap: WeeklyRecap) -> WeekInMotionObservation {
        if !recap.hasAnyActivity {
            return WeekInMotionObservation(
                kind: .quiet,
                title: "Quiet week",
                text: "No food, strength sessions, or runs were recorded in this seven-day window.",
                basis: "Based only on MyFitPlate diary and training history.",
                tone: .neutral
            )
        }

        if recap.trainingDays > 0, recap.trainingDaysLogged < recap.trainingDays {
            return WeekInMotionObservation(
                kind: .trainingCoverage,
                title: "Training-day coverage",
                text: "Food appears in the diary on \(recap.trainingDaysLogged) of \(recap.trainingDays) recorded training \(dayWord(recap.trainingDays)).",
                basis: "A day counts only when a strength session or run was recorded.",
                tone: .attention
            )
        }

        if recap.recoveryFuelAdherence.eligible > 0,
           recap.recoveryFuelAdherence.completed < recap.recoveryFuelAdherence.eligible {
            return WeekInMotionObservation(
                kind: .recovery,
                title: "Recovery follow-through",
                text: "\(recoveryCoverageText(recap)).",
                basis: "Only timestamped food inside a completed recovery window is counted.",
                tone: .attention
            )
        }

        if recap.demandingStrengthFuelAdherence.eligible > 0,
           recap.demandingStrengthFuelAdherence.completed < recap.demandingStrengthFuelAdherence.eligible {
            return WeekInMotionObservation(
                kind: .hardDayFuel,
                title: "Hard-day fuel",
                text: "Both nutrition targets were logged on \(recap.demandingStrengthFuelAdherence.completed) of \(recap.demandingStrengthFuelAdherence.eligible) assessable hard strength \(dayWord(recap.demandingStrengthFuelAdherence.eligible)).",
                basis: "Hard days use the existing working-set and recorded-effort rule.",
                tone: .attention
            )
        }

        if recap.trustReview.eligible > 0, recap.trustReview.completed < recap.trustReview.eligible {
            return WeekInMotionObservation(
                kind: .trust,
                title: "Trust coverage",
                text: "\(recap.trustReview.eligible - recap.trustReview.completed) review-needed food \(entryWord(recap.trustReview.eligible - recap.trustReview.completed)) remained unresolved.",
                basis: "Only entries already marked as requiring review are included.",
                tone: .attention
            )
        }

        let records = recap.personalRecords + recap.runRecordCount
        if records > 0 {
            return WeekInMotionObservation(
                kind: .progress,
                title: "Progress in context",
                text: "\(records) recorded \(recordWord(records)) beat comparable prior history.",
                basis: "First attempts create a baseline and are not counted as records.",
                tone: .positive
            )
        }

        if recap.trainingDays > 0, recap.trainingDaysLogged == recap.trainingDays {
            return WeekInMotionObservation(
                kind: .connected,
                title: "Connected week",
                text: "Every recorded training day also had food in the diary.",
                basis: "Coverage confirms presence, not nutrient quality or timing.",
                tone: .positive
            )
        }

        return WeekInMotionObservation(
            kind: .diaryCoverage,
            title: "Diary coverage",
            text: "Food was logged on \(recap.daysLogged) of 7 days.",
            basis: "A day counts when at least one food item is present.",
            tone: .neutral
        )
    }

    private static func dayWord(_ count: Int) -> String { count == 1 ? "day" : "days" }
    private static func recoveryCoverageText(_ recap: WeeklyRecap) -> String {
        "\(recap.recoveryFuelAdherence.completed) of \(recap.recoveryFuelAdherence.eligible) assessed runs had both recovery targets logged"
    }
    private static func windowWord(_ count: Int) -> String { count == 1 ? "window is" : "windows are" }
    private static func entryWord(_ count: Int) -> String { count == 1 ? "entry" : "entries" }
    private static func recordWord(_ count: Int) -> String { count == 1 ? "result" : "results" }
}
