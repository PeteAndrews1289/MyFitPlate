import SwiftUI

struct TrainingReadinessBrief {
    let score: Int
    let status: String
    let message: String
    let icon: String
    let color: Color
    let signals: [TrainingSignal]
}

struct TrainingSignal: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let icon: String
    let color: Color
}

@MainActor
class WorkoutDashboardViewModel: ObservableObject {
    @Published var sessionLogs: [WorkoutSessionLog] = []

    func nextWorkoutInfo(for program: WorkoutProgram?) -> (program: WorkoutProgram, routine: WorkoutRoutine, title: String)? {
        guard let program = program,
              let progressIndex = program.currentProgressIndex,
              !program.routines.isEmpty,
              let daysPerWeek = program.daysOfWeek?.count, daysPerWeek > 0 else {
            return nil
        }

        let totalWorkoutsInProgram = daysPerWeek * 12
        guard progressIndex < totalWorkoutsInProgram else { return nil }

        let routineIndex = progressIndex % program.routines.count
        guard routineIndex < program.routines.count else { return nil }

        let routine = program.routines[routineIndex]
        let weekNumber = (progressIndex / daysPerWeek) + 1
        let dayNumber = (progressIndex % daysPerWeek) + 1
        let title = "Start Week \(weekNumber) · Day \(dayNumber)"

        return (program, routine, title)
    }

    func trainingBrief(todayLog: DailyLog?, goalSettings: GoalSettings) -> TrainingReadinessBrief {
        let calories = todayLog?.totalCalories() ?? 0
        let calorieGoal = max(goalSettings.calories ?? 2000, 1)
        let protein = todayLog?.totalMacros().protein ?? 0
        let proteinGoal = max(goalSettings.protein, 1)
        let water = todayLog?.waterTracker?.totalOunces ?? 0
        let waterGoal = max(goalSettings.waterGoal, 1)
        let loggedWorkouts = todayLog?.exercises?.count ?? 0

        let calorieRatio = calories / calorieGoal
        let proteinRatio = protein / proteinGoal
        let waterRatio = water / waterGoal

        var score = 48
        score += calorieRatio >= 0.20 ? 14 : -4
        score += proteinRatio >= 0.35 ? 14 : 0
        score += waterRatio >= 0.35 ? 14 : -3
        score += loggedWorkouts == 0 ? 6 : -6
        score = min(max(score, 25), 95)

        let status: String
        let message: String
        let icon: String
        let color: Color

        if loggedWorkouts > 0 {
            status = "Recovery Mode"
            message = "You already logged activity today. Start another session if it is intentional, or keep the next block easy."
            icon = "moon.zzz.fill"
            color = .blue
        } else if score >= 78 {
            status = "Primed to Train"
            message = "Fuel, hydration, and protein are lining up. This is a good window for a focused session."
            icon = "bolt.fill"
            color = .accentPositive
        } else if waterRatio < 0.25 {
            status = "Hydrate First"
            message = "Log some water before you train. It is the fastest readiness win in the app."
            icon = "drop.fill"
            color = .cyan
        } else if calorieRatio < 0.15 {
            status = "Fuel First"
            message = "You have not logged much food yet. Consider a small meal or snack before a hard session."
            icon = "fork.knife"
            color = .orange
        } else {
            status = "Ready, Build Gradually"
            message = "You are clear to train. Warm up patiently and let the first working set tell you the day."
            icon = "figure.strengthtraining.traditional"
            color = .brandPrimary
        }

        return TrainingReadinessBrief(
            score: score,
            status: status,
            message: message,
            icon: icon,
            color: color,
            signals: [
                TrainingSignal(title: "Fuel", value: calories > 0 ? "\(Int(calories.rounded())) cal" : "Not logged", icon: "flame.fill", color: .orange),
                TrainingSignal(title: "Protein", value: "\(Int(protein.rounded()))/\(Int(proteinGoal.rounded()))g", icon: "bolt.fill", color: .accentProtein),
                TrainingSignal(title: "Water", value: "\(Int(water.rounded()))/\(Int(waterGoal.rounded())) oz", icon: "drop.fill", color: .cyan),
                TrainingSignal(title: "Activity", value: loggedWorkouts == 0 ? "Open" : "\(loggedWorkouts) logged", icon: "figure.run", color: .blue)
            ]
        )
    }

    func completedLogsByIndex(for program: WorkoutProgram) -> [Int: WorkoutSessionLog] {
        let current = program.currentProgressIndex ?? 0
        let skipped = Set(program.skippedIndices ?? [])
        let completedSlots = (0..<current).filter { !skipped.contains($0) }
        let sortedLogs = sessionLogs.sorted { $0.date.dateValue() < $1.date.dateValue() }
        var result: [Int: WorkoutSessionLog] = [:]
        for (slot, log) in zip(completedSlots, sortedLogs) {
            result[slot] = log
        }
        return result
    }

    func refreshSessionLogs(for program: WorkoutProgram?, workoutService: any WorkoutServicing, expectingAtLeast expectedCount: Int? = nil) async {
        guard let program = program else {
            sessionLogs = []
            return
        }

        var logs = await workoutService.fetchSessionLogs(for: program)
        if let expectedCount = expectedCount, logs.count < expectedCount {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let retryLogs = await workoutService.fetchSessionLogs(for: program)
            if retryLogs.count > logs.count {
                logs = retryLogs
            }
        }
        sessionLogs = logs
    }
}
