import Foundation
import FirebaseAnalytics

class ExerciseLogStore {
    private weak var dailyLogService: DailyLogService?

    init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    func addExerciseToLog(for userID: String, exercise: LoggedExercise) {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate
        
        service.fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self, let service = self.dailyLogService else { return }
            switch result {
            case .success(var log):
                if log.exercises == nil { log.exercises = [] }
                var exerciseToLog = exercise
                exerciseToLog.date = dateToLog
                log.exercises?.append(exerciseToLog)

                DispatchQueue.main.async {
                    service.publishCurrentDailyLog(log)
                }

                service.updateDailyLog(for: userID, updatedLog: log) { success in
                     Task { @MainActor in
                        if success {
                            Analytics.logEvent("exercise_logged", parameters: [
                                "source": exercise.source,
                                "duration": exercise.durationMinutes ?? 0,
                                "calories": exercise.caloriesBurned
                            ])

                            service.bannerService?.showBanner(title: "Success", message: "\(exercise.name) logged!")
                            service.achievementService?.updateChallengeProgress(for: userID, type: .workoutLogged, amount: 1)
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                        } else {
                             service.bannerService?.showBanner(title: "Error", message: "Failed to log \(exercise.name).", iconName: "xmark.circle.fill", iconColor: .red)
                        }
                    }
                }
            case .failure(let error):
                AppLog.data.error("Failed to fetch log for adding exercise: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in
                    service.bannerService?.showBanner(title: "Error", message: "Could not fetch log to add exercise.", iconName: "xmark.circle.fill", iconColor: .red)
                }
            }
        }
    }

    func deleteExerciseFromLog(for userID: String, exerciseID: String) {
        guard let service = dailyLogService else { return }
        let dateToLog = service.activelyViewedDate
        
        service.fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self, let service = self.dailyLogService else { return }
            switch result {
            case .success(var log):
                let initialCount = log.exercises?.count ?? 0
                var exerciseName: String?
                 if let exToRemove = log.exercises?.first(where: { $0.id == exerciseID }) {
                     exerciseName = exToRemove.name
                 }
                log.exercises?.removeAll { $0.id == exerciseID }
                if (log.exercises?.count ?? 0) < initialCount {

                    DispatchQueue.main.async {
                        service.publishCurrentDailyLog(log)
                    }

                    service.updateDailyLog(for: userID, updatedLog: log) { success in
                         Task { @MainActor in
                            if success {
                                 service.bannerService?.showBanner(title: "Deleted", message: "\(exerciseName ?? "Exercise") removed.")
                                NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                             } else {
                                service.bannerService?.showBanner(title: "Error", message: "Failed to delete exercise.", iconName: "xmark.circle.fill", iconColor: .red)
                            }
                        }
                    }
                }
            case .failure(let error):
                AppLog.data.error("Failed to fetch log for deleting exercise: \(error.localizedDescription, privacy: .public)")
             Task { @MainActor in
                 service.bannerService?.showBanner(title: "Error", message: "Could not fetch log to delete exercise.", iconName: "xmark.circle.fill", iconColor: .red)
             }
            }
        }
    }

    func addOrUpdateHealthKitWorkouts(for userID: String, exercises: [LoggedExercise], date: Date, completion: (() -> Void)? = nil) {
        guard let service = dailyLogService else {
            completion?()
            return
        }
        let dateToLog = Calendar.current.startOfDay(for: date)

        service.fetchLogInternal(for: userID, date: dateToLog) { [weak self] result in
            guard let self = self, let service = self.dailyLogService else {
                completion?()
                return
            }
            switch result {
            case .success(var log):
                if log.exercises == nil {
                    log.exercises = []
                }

                log.exercises?.removeAll { $0.source == "HealthKit" }
                log.exercises?.append(contentsOf: exercises)

                DispatchQueue.main.async {
                    if Calendar.current.isDate(log.date, inSameDayAs: service.activelyViewedDate) {
                        service.publishCurrentDailyLog(log)
                    }
                }

                service.updateDailyLog(for: userID, updatedLog: log) { success in
                    DispatchQueue.main.async {
                         if success {
                            Analytics.logEvent("healthkit_sync_workouts", parameters: [
                                "count": exercises.count
                            ])
                            NotificationCenter.default.post(name: .didUpdateExerciseLog, object: nil)
                         }
                         completion?()
                    }
                }
            case .failure(let error):
                AppLog.health.error("Failed to fetch log for HealthKit workout sync: \(error.localizedDescription, privacy: .public)")
                completion?()
            }
        }
    }
}
