import Foundation
@MainActor
public class ExerciseLogStore {
    private weak var dailyLogService: DailyLogService?

    public init(dailyLogService: DailyLogService) {
        self.dailyLogService = dailyLogService
    }

    public func addExerciseToLog(
        for userID: String, exercise: LoggedExercise, completion: ((Bool) -> Void)? = nil
    ) {
        guard let service = dailyLogService else { completion?(false); return }
        service.saveActivityExercise(for: userID, exercise: exercise) { completion?($0) }
    }

    public func updateExerciseInLog(
        for userID: String, original: LoggedExercise, updated: LoggedExercise,
        completion: @escaping (Bool) -> Void
    ) {
        guard let service = dailyLogService else { completion(false); return }
        service.saveActivityExercise(for: userID, exercise: updated, replacing: original, completion: completion)
    }

    public func deleteExerciseFromLog(
        for userID: String, exerciseID: String, date: Date? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let service = dailyLogService else { completion?(false); return }
        let capturedDate = date ?? service.activelyViewedDate
        service.deleteActivityExercise(for: userID, exerciseID: exerciseID, date: capturedDate, completion: completion)
    }

    public func addOrUpdateHealthKitWorkouts(for userID: String, exercises: [LoggedExercise], date: Date, completion: (() -> Void)? = nil) {
        guard let service = dailyLogService, service.isActiveAccount(userID) else {
            completion?()
            return
        }
        service.syncHealthKitExercises(for: userID, exercises: exercises, date: date) { _ in completion?() }
    }
}
