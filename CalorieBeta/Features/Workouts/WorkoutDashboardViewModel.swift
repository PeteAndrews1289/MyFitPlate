import MyFitPlateCore

import SwiftUI

struct TrainingReadinessBrief {
    let status: String
    let message: String
    let icon: String
    let role: AppSignalRole
    let signals: [TrainingSignal]
}

struct TrainingSignal: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let icon: String
    let role: AppSignalRole
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

        let totalWorkoutsInProgram = program.totalSlots
        guard progressIndex < totalWorkoutsInProgram else { return nil }

        let routineIndex = progressIndex % program.routines.count
        guard routineIndex < program.routines.count else { return nil }

        guard let routine = program.routine(forSlot: progressIndex) else { return nil }
        let weekNumber = (progressIndex / daysPerWeek) + 1
        let dayNumber = (progressIndex % daysPerWeek) + 1
        let title = "Start Week \(weekNumber) · Day \(dayNumber)"

        return (program, routine, title)
    }

    func trainingBrief(todayLog: DailyLog?, goalSettings: GoalSettings) -> TrainingReadinessBrief {
        let calories = todayLog?.totalCalories() ?? 0
        let protein = todayLog?.totalMacros().protein ?? 0
        let proteinGoal = max(goalSettings.protein, 1)
        let water = todayLog?.waterTracker?.totalOunces ?? 0
        let waterGoal = max(goalSettings.waterGoal, 1)
        let loggedWorkouts = todayLog?.exercises?.count ?? 0

        let hasFood = calories > 0 || protein > 0
        let status = loggedWorkouts > 0 ? "Activity recorded" : hasFood || water > 0 ? "Today's logged fuel" : "No fuel recorded yet"
        let message = "These are your logged amounts, not a readiness assessment. Missing entries do not mean you have not eaten or hydrated."
        let icon = loggedWorkouts > 0 ? "checkmark.circle" : "list.bullet.clipboard"
        let role: AppSignalRole = .current

        return TrainingReadinessBrief(
            status: status,
            message: message,
            icon: icon,
            role: role,
            signals: [
                TrainingSignal(title: "Fuel", value: calories > 0 ? "\(Int(calories.rounded()).formatted()) cal" : "Not logged", icon: "flame.fill", role: .caution),
                TrainingSignal(title: "Protein", value: "\(Int(protein.rounded()).formatted()) of \(Int(proteinGoal.rounded()).formatted()) g", icon: "bolt.fill", role: .effort),
                TrainingSignal(title: "Water", value: "\(Int(water.rounded()).formatted()) of \(Int(waterGoal.rounded()).formatted()) oz", icon: "drop.fill", role: .recovery),
                TrainingSignal(title: "Activity", value: loggedWorkouts == 0 ? "Not logged" : "\(loggedWorkouts.formatted()) logged", icon: "figure.run", role: .effort)
            ]
        )
    }

    func completedLogsByIndex(for program: WorkoutProgram) -> [Int: WorkoutSessionLog] {
        WorkoutRules.sessionLogsBySlot(in: program, sessionLogs: sessionLogs)
    }

    func refreshSessionLogs(for program: WorkoutProgram?, workoutService: any WorkoutServicing, expectingAtLeast expectedCount: Int? = nil) async {
        guard let program = program else {
            sessionLogs = []
            return
        }

        let ownerID = DIContainer.shared.authService.currentUserID
        guard case .success(var logs) = await workoutService.fetchSessionLogsResult(for: program) else { return }
        guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == ownerID,
              workoutService.activeProgram?.id == program.id else { return }
        if let expectedCount = expectedCount, logs.count < expectedCount {
            try? await Task.sleep(nanoseconds: 300_000_000)
            let retryLogs = await workoutService.fetchSessionLogs(for: program)
            if retryLogs.count > logs.count {
                logs = retryLogs
            }
        }
        guard !Task.isCancelled, DIContainer.shared.authService.currentUserID == ownerID,
              let latestProgram = workoutService.activeProgram, latestProgram.id == program.id else { return }
        sessionLogs = logs

        _ = await workoutService.reconcileProgramProgress(in: latestProgram, knownLogs: logs)
    }
}
