import Foundation

public struct RunHistoryScope: Equatable {
    public enum Period: String, CaseIterable { case all, week, month, year }
    public enum Environment: String, CaseIterable { case all, outdoor, indoor }
    public var period: Period = .all
    public var environment: Environment = .all
    /// Exact source display name, not a guessed device/brand grouping.
    public var source: String?
    public var query = ""
    public var selectedWeek: Date
    public init(selectedWeek: Date = Date()) { self.selectedWeek = selectedWeek }

    public func filtered(_ runs: [Run], now: Date = Date(), calendar: Calendar = .current) -> [Run] {
        let interval: DateInterval?
        switch period {
        case .all: interval = nil
        case .week: interval = calendar.dateInterval(of: .weekOfYear, for: selectedWeek)
        case .month: interval = calendar.dateInterval(of: .month, for: now)
        case .year: interval = calendar.dateInterval(of: .year, for: now)
        }
        let tokens = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(whereSeparator: \.isWhitespace)
        return runs.filter { run in
            guard run.startDate.timeIntervalSinceReferenceDate.isFinite,
                  interval.map({ run.startDate >= $0.start && run.startDate < $0.end }) ?? true,
                  environment == .all || (environment == .indoor ? run.isIndoor : !run.isIndoor),
                  source == nil || run.source.displayName == source else { return false }
            let text = [run.source.displayName, run.isIndoor ? "indoor treadmill" : "outdoor",
                        run.workoutResult?.planName ?? run.scheduledContext?.plan.name ?? "Open run",
                        DiaryDayContext.dayKey(for: run.startDate, timeZone: calendar.timeZone) ?? "",
                        run.startDate.formatted(date: .abbreviated, time: .omitted)].joined(separator: " ").lowercased()
            return tokens.allSatisfy { text.contains($0) }
        }.sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate > $1.startDate }
    }

    public static func sources(in runs: [Run]) -> [String] { Array(Set(runs.map { $0.source.displayName })).sorted() }
}
