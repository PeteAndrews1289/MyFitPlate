import Foundation

/// A preference, never a second diary counter. Legacy totals remain available until review.
public struct LoggingHabitPreferences: Codable, Equatable {
    public enum Rule: String, Codable, CaseIterable { case anyEntry, reviewedComplete }
    public var version = 2
    public var reviewed = false
    public var rule = Rule.anyEntry
    public var hidden = false
    public var paused = false
    public init() {}
}
public struct LoggingHabitDay: Equatable, Identifiable {
    public enum State: String { case entry, complete, partial, open, grace, noEntry }
    public let date: Date
    public let state: State
    public let qualifiesForRule: Bool
    public let isGraceDay: Bool
    public var id: Date { date }
}
public struct LoggingHabitSummary: Equatable {
    public let count: Int
    public let days: [LoggingHabitDay]
    public let reachedHistoryBoundary: Bool
}
public struct LoggingHabitStreak: Equatable {
    public let count: Int
    public let qualifyingDates: [Date]
    public let graceDates: [Date]
}
public enum LoggingHabitRules {
    /// Canonical diary keys describe civil days. Travel must not move a saved entry
    /// to the preceding day just because its old midnight is now in another zone.
    public static func civilDate(for log: DailyLog, calendar: Calendar = .current) -> Date? {
        guard log.date.timeIntervalSince1970.isFinite else { return nil }
        if let id = log.id, let context = DiaryDayContext(userID: "habit-projection", date: log.date,
            timeZone: calendar.timeZone, dayKey: id) {
            return calendar.startOfDay(for: context.displayDate)
        }
        return calendar.startOfDay(for: log.date)
    }
    /// Version 2 permits at most one missed qualifying day in the current chain.
    /// An unqualified today stays open and does not consume that allowance.
    public static func streak(loggedDays: [Date], today: Date = Date(), calendar: Calendar = .current) -> LoggingHabitStreak {
        let now = calendar.startOfDay(for: today)
        let days = Set(loggedDays.filter { $0.timeIntervalSince1970.isFinite }.map { calendar.startOfDay(for: $0) }.filter { $0 <= now })
        guard let first = days.min(), let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return .init(count: 0, qualifyingDates: [], graceDates: [])
        }
        var cursor = days.contains(now) ? now : yesterday
        var qualified: [Date] = [], grace: [Date] = []
        while cursor >= first {
            if days.contains(cursor) { qualified.append(cursor) } else {
                guard grace.isEmpty, let previous = calendar.date(byAdding: .day, value: -1, to: cursor), days.contains(previous) else { break }
                grace.append(cursor)
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        return .init(count: qualified.count, qualifyingDates: qualified, graceDates: grace)
    }
    public static func make(logs: [DailyLog], preferences: LoggingHabitPreferences, today: Date = Date(),
                            from start: Date, calendar: Calendar = .current) -> LoggingHabitSummary {
        let now = calendar.startOfDay(for: today), first = calendar.startOfDay(for: start)
        guard first <= now else { return .init(count: 0, days: [], reachedHistoryBoundary: false) }
        var byDate: [Date: DailyLog] = [:]
        for log in logs {
            guard let date = civilDate(for: log, calendar: calendar), (first...now).contains(date) else { continue }
            byDate[date] = log
        }
        func qualifies(_ date: Date) -> Bool {
            guard let log = byDate[date] else { return false }
            return preferences.rule == .anyEntry ? !log.meals.flatMap(\.foodItems).isEmpty : NutritionDayEvidence.isComplete(log, now: today, calendar: calendar)
        }
        let qualifying = byDate.keys.filter(qualifies)
        let reviewed = streak(loggedDays: qualifying, today: today, calendar: calendar)
        let count = preferences.paused ? 0 : preferences.reviewed ? reviewed.count : LoggingStreak.currentStreak(loggedDays: qualifying, today: today, calendar: calendar)
        let graceDates: Set<Date>
        if preferences.paused { graceDates = [] } else if preferences.reviewed { graceDates = Set(reviewed.graceDates) } else if LoggingStreak.isOnGraceDay(loggedDays: qualifying, today: today, calendar: calendar), let yesterday = calendar.date(byAdding: .day, value: -1, to: now) { graceDates = [yesterday] } else { graceDates = [] }
        var days: [LoggingHabitDay] = [], cursor = first
        while cursor <= now {
            let log = byDate[cursor]
            let state: LoggingHabitDay.State
            if let log, NutritionDayEvidence.isComplete(log, now: today, calendar: calendar) { state = .complete } else if let log, !log.meals.flatMap(\.foodItems).isEmpty { state = NutritionDayEvidence.status(of: log) == .partial ? .partial : .entry } else if cursor == now { state = .open } else if graceDates.contains(cursor) { state = .grace } else { state = .noEntry }
            days.append(.init(date: cursor, state: state, qualifiesForRule: qualifies(cursor), isGraceDay: graceDates.contains(cursor)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        let boundary = preferences.reviewed ? reviewed.qualifyingDates.contains(first) : count > 0 && qualifying.contains(first) && count >= qualifying.count
        return .init(count: count, days: days, reachedHistoryBoundary: !preferences.paused && boundary)
    }
}
public final class LoggingHabitStore {
    public static let scope = "logging-habit-preferences-v2"
    private let store: EditorDraftStore
    public init(store: EditorDraftStore = .init()) { self.store = store }
    public func load(userID: String) throws -> LoggingHabitPreferences {
        let value = try store.load(LoggingHabitPreferences.self, userID: userID, scope: Self.scope)?.value ?? .init()
        guard value.version == 2 else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    public func save(_ value: LoggingHabitPreferences, expected: LoggingHabitPreferences, userID: String) throws {
        guard value.version == 2, try load(userID: userID) == expected else { throw CocoaError(.fileWriteFileExists) }
        try store.save(value, userID: userID, scope: Self.scope)
    }
}
