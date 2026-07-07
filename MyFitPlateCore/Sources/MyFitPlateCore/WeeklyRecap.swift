import Foundation

/// One week of the user's story, computed from data the app already stores. Powers the
/// "Your week" recap card and its shareable image — the Sunday reason to open the app.
public struct WeeklyRecap: Equatable {
    public let weekStart: Date
    public let weekEnd: Date

    /// Days in the window with at least one food item logged.
    public let daysLogged: Int
    /// Average intake over logged days only (nil when nothing was logged).
    public let averageCalories: Double?
    public let averageProtein: Double?
    public let calorieGoal: Double?

    public let workoutsCompleted: Int
    /// Total weight moved across the week's sessions (lbs · reps).
    public let totalVolume: Double
    /// Exercises where this week's best estimated 1RM beat everything before the week.
    public let personalRecords: Int

    /// Runs in the window — recorded in-app or imported from any watch.
    public let runCount: Int
    public let runMeters: Double

    /// Change across the window (negative = lost weight), nil without enough entries.
    public let weightChange: Double?

    public var hasAnyActivity: Bool {
        daysLogged > 0 || workoutsCompleted > 0 || runCount > 0
    }
}

public enum WeeklyRecapBuilder {

    /// Builds the recap for the 7 days ending at `weekEnding` (inclusive).
    /// - Parameters:
    ///   - dailyLogs: logs overlapping the window (extra days are filtered out).
    ///   - sessionLogs: workout sessions inside the window.
    ///   - priorSessionLogs: history from before the window — the PR baseline.
    ///   - weightHistory: entries spanning the window (and ideally one just before it).
    public static func build(
        weekEnding: Date = Date(),
        calendar: Calendar = .current,
        dailyLogs: [DailyLog],
        sessionLogs: [WorkoutSessionLog],
        priorSessionLogs: [WorkoutSessionLog],
        weightHistory: [(id: String, date: Date, weight: Double)],
        runs: [Run] = [],
        calorieGoal: Double?
    ) -> WeeklyRecap {
        let weekEnd = calendar.startOfDay(for: weekEnding).addingTimeInterval(24 * 60 * 60 - 1)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: weekEnding)) ?? weekEnding

        func inWindow(_ date: Date) -> Bool {
            date >= weekStart && date <= weekEnd
        }

        // Nutrition: one log per distinct day, only days with actual food.
        var seenDays = Set<Date>()
        var loggedDayCalories: [Double] = []
        var loggedDayProtein: [Double] = []
        for log in dailyLogs where inWindow(log.date) {
            let day = calendar.startOfDay(for: log.date)
            guard !seenDays.contains(day) else { continue }
            seenDays.insert(day)

            let foodItems = log.meals.flatMap(\.foodItems)
            guard !foodItems.isEmpty else { continue }
            loggedDayCalories.append(log.totalCalories())
            loggedDayProtein.append(log.totalMacros().protein)
        }

        let daysLogged = loggedDayCalories.count
        let averageCalories = daysLogged > 0 ? loggedDayCalories.reduce(0, +) / Double(daysLogged) : nil
        let averageProtein = daysLogged > 0 ? loggedDayProtein.reduce(0, +) / Double(daysLogged) : nil

        // Training.
        let weekSessions = sessionLogs.filter { inWindow($0.date) }
        let totalVolume = weekSessions.reduce(0.0) { sum, session in
            sum + session.completedExercises.reduce(0.0) { exerciseSum, exercise in
                exerciseSum + exercise.sets.filter(\.isWorkingSet).reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            }
        }

        let personalRecords = personalRecordCount(
            weekSessions: weekSessions,
            priorSessions: priorSessionLogs.filter { $0.date < weekStart }
        )

        // Running.
        let weekRuns = runs.filter { inWindow($0.startDate) }
        let runMeters = weekRuns.reduce(0.0) { $0 + $1.distanceMeters }

        // Weight: last entry in the window vs. the latest entry at or before the window start
        // (falling back to the first in-window entry when there's no prior baseline).
        let sortedWeights = weightHistory.sorted { $0.date < $1.date }
        let inWindowWeights = sortedWeights.filter { inWindow($0.date) }
        var weightChange: Double?
        if let latest = inWindowWeights.last {
            if let baseline = sortedWeights.last(where: { $0.date < weekStart }) {
                weightChange = latest.weight - baseline.weight
            } else if let first = inWindowWeights.first, first.id != latest.id {
                weightChange = latest.weight - first.weight
            }
        }

        return WeeklyRecap(
            weekStart: weekStart,
            weekEnd: weekEnd,
            daysLogged: daysLogged,
            averageCalories: averageCalories,
            averageProtein: averageProtein,
            calorieGoal: calorieGoal,
            workoutsCompleted: weekSessions.count,
            totalVolume: totalVolume,
            personalRecords: personalRecords,
            runCount: weekRuns.count,
            runMeters: runMeters,
            weightChange: weightChange
        )
    }

    /// Epley estimated 1RM — the same yardstick Workout History uses for "top set".
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Number of exercises whose best set this week beats their best in all prior history.
    /// New movements (no prior history) don't count — a first attempt isn't a record.
    static func personalRecordCount(
        weekSessions: [WorkoutSessionLog],
        priorSessions: [WorkoutSessionLog]
    ) -> Int {
        func bestByExercise(_ sessions: [WorkoutSessionLog]) -> [String: Double] {
            var best: [String: Double] = [:]
            for session in sessions {
                for exercise in session.completedExercises {
                    let name = exercise.exerciseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let sessionBest = exercise.sets
                        .filter(\.isWorkingSet)
                        .map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }
                        .max() ?? 0
                    best[name] = max(best[name] ?? 0, sessionBest)
                }
            }
            return best
        }

        let weekBest = bestByExercise(weekSessions)
        let priorBest = bestByExercise(priorSessions)

        return weekBest.filter { name, best in
            guard best > 0, let prior = priorBest[name], prior > 0 else { return false }
            return best > prior
        }.count
    }
}
