import CryptoKit
import Foundation

/// Immutable inputs and coverage for an interpretation. Evidence is captured by the
/// app from real records, never supplied by a model's `sourceData` prose.
public struct InsightEvidenceSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Origin: String, Codable, Sendable { case localRules, aiInterpretation }
    public struct Day: Codable, Equatable, Identifiable, Sendable {
        public var id: String { dayKey }
        public let dayKey: String
        public let sourceID: String?
        public let sourceFingerprint: String
        public let date: Date
        public let status: NutritionDayStatus
        public let includedInIntake: Bool
        public let calories: Double?
        public let protein: Double?
        public let carbs: Double?
        public let fats: Double?
        public let waterOunces: Double?
        public let foodIDs: [String]
        public let workoutIDs: [String]
        public let journalIDs: [String]
    }
    public struct SleepNight: Codable, Equatable, Identifiable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let hours: Double
    }
    public let id: UUID
    public let version: Int
    public let ownerID: String
    public let generatedAt: Date
    public let windowStart: Date
    public let windowEnd: Date
    public let timeZoneIdentifier: String
    public let origin: Origin
    public let calculationVersion: String
    public let inputFingerprint: String
    public let calendarDayCount: Int
    public let days: [Day]
    public let sleepNights: [SleepNight]
    public let calorieGoal: Double
    public let proteinGoal: Double

    public var completeFoodDays: Int { days.filter(\.includedInIntake).count }
    public var coverageDescription: String {
        "\(completeFoodDays)/\(calendarDayCount) fully logged food days · \(days.count) days with records · \(sleepNights.count) sleep nights included"
    }
    public var sourceLabel: String { origin == .localRules ? "Calculated from your records" : "AI interpretation of the listed inputs" }

    public init(ownerID: String, logs: [DailyLog], sleepHoursByNight: [Date: Double],
                calorieGoal: Double, proteinGoal: Double, start: Date, end: Date,
                origin: Origin, now: Date = Date(), calendar: Calendar = .current) throws {
        guard !ownerID.isEmpty, start <= end, end <= now,
              [calorieGoal, proteinGoal].allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw InsightEvidenceError.invalid }
        id = UUID(); version = 1; self.ownerID = ownerID; generatedAt = now
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        windowStart = firstDay; windowEnd = lastDay
        timeZoneIdentifier = calendar.timeZone.identifier; self.origin = origin
        calculationVersion = "insight-inputs-v1/complete-day-intake/night-union-sleep"
        self.calorieGoal = calorieGoal; self.proteinGoal = proteinGoal
        calendarDayCount = (calendar.dateComponents([.day], from: windowStart, to: windowEnd).day ?? 0) + 1
        days = try NutritionDayEvidence.days(logs, from: start, through: end, now: now, calendar: calendar).map { log in
            let complete = NutritionDayEvidence.isComplete(log, now: now, calendar: calendar)
            let macros = log.totalMacros()
            let civilDay = NutritionDayReviewRules.displayDate(log, calendar: calendar)
            return Day(dayKey: NutritionDayReviewRules.key(log, timeZone: calendar.timeZone)
                ?? DiaryDayContext.dayKey(for: civilDay, timeZone: calendar.timeZone) ?? "unknown",
                sourceID: log.id, sourceFingerprint: try PlanFingerprint.make(log), date: calendar.startOfDay(for: civilDay), status: NutritionDayEvidence.status(of: log), includedInIntake: complete,
                calories: complete ? log.totalCalories() : nil, protein: complete ? macros.protein : nil,
                carbs: complete ? macros.carbs : nil, fats: complete ? macros.fats : nil,
                waterOunces: log.waterTracker.flatMap { $0.totalOunces.isFinite ? $0.totalOunces : nil },
                foodIDs: log.meals.flatMap(\.foodItems).map(\.id).sorted(),
                workoutIDs: (log.exercises ?? []).map(\.id).sorted(), journalIDs: (log.journalEntries ?? []).map(\.id).sorted())
        }
        sleepNights = sleepHoursByNight.filter {
            let day = calendar.startOfDay(for: $0.key)
            return day >= firstDay && day <= lastDay && $0.value.isFinite && $0.value > 0
        }.map { SleepNight(date: $0.key, hours: $0.value) }.sorted { $0.date < $1.date }
        struct Inputs: Encodable {
            let start: Date; let end: Date; let zone: String; let days: [Day]; let nights: [SleepNight]
            let calories: Double; let protein: Double
        }
        inputFingerprint = try PlanFingerprint.make(Inputs(start: windowStart, end: windowEnd,
            zone: timeZoneIdentifier, days: days, nights: sleepNights, calories: calorieGoal, protein: proteinGoal))
    }

    public func stableInsightID(title: String, category: String, message: String) -> UUID {
        let digest = SHA256.hash(data: Data([ownerID, inputFingerprint, origin.rawValue, title, category, message].joined(separator: "\u{1f}").utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

public enum InsightEvidenceError: LocalizedError {
    case invalid, accountChanged, conflict
    public var errorDescription: String? {
        switch self {
        case .invalid: return "The evidence snapshot could not be created from these records."
        case .accountChanged: return "This evidence belongs to a different account."
        case .conflict: return "The saved insight report changed. The original has been kept."
        }
    }
}

public struct SavedInsightReport: Codable, Equatable, Identifiable {
    public var id: UUID { evidence.id }
    public let evidence: InsightEvidenceSnapshot
    public let insights: [UserInsight]
    public init(evidence: InsightEvidenceSnapshot, insights: [UserInsight]) { self.evidence = evidence; self.insights = insights }
}

@MainActor
public final class InsightReportStore {
    private let store: EditorDraftStore
    private let scope = "insight-reports-v1"
    public init(store: EditorDraftStore = EditorDraftStore()) { self.store = store }
    public func reports(userID: String) throws -> [SavedInsightReport] {
        let reports = try store.load([SavedInsightReport].self, userID: userID, scope: scope)?.value ?? []
        guard reports.allSatisfy({ $0.evidence.ownerID == userID }) else { throw InsightEvidenceError.accountChanged }
        return reports.sorted { $0.evidence.generatedAt > $1.evidence.generatedAt }
    }
    public func record(_ report: SavedInsightReport, currentUserID: String?) throws {
        guard currentUserID == report.evidence.ownerID else { throw InsightEvidenceError.accountChanged }
        guard report.insights.allSatisfy({ $0.evidence?.id == report.id && $0.evidence?.ownerID == report.evidence.ownerID }) else { throw InsightEvidenceError.invalid }
        var values = try reports(userID: report.evidence.ownerID)
        if let saved = values.first(where: { $0.id == report.id }) {
            guard saved == report else { throw InsightEvidenceError.conflict }
            return
        }
        values.append(report)
        try store.save(values, userID: report.evidence.ownerID, scope: scope)
    }
}
