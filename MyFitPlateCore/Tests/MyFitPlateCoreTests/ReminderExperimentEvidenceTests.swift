import XCTest
@testable import MyFitPlateCore

final class ReminderExperimentEvidenceTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }
    private func fixture() throws -> (MealExperiment, WorkoutSessionLog) {
        let exercise = RoutineExercise(id: "press", name: "Press", sets: [ExerciseSet(id: "set", target: "8", reps: 8, weight: 100)], targetSets: 1)
        let routine = WorkoutRoutine(id: "routine", userID: "owner", name: "Upper", dateCreated: start, exercises: [exercise])
        let program = WorkoutProgram(id: "program", userID: "owner", name: "Plan", dateCreated: start,
            routines: [routine], startDate: start, daysOfWeek: Array(1...7), currentProgressIndex: 0)
        let experiment = try MealExperimentRules.create(program: program, routineID: "routine",
            mealA: .init(id: "oats", name: "Oats", calories: 300), mealB: .init(id: "toast", name: "Toast", calories: 300),
            minutesBefore: 90, startsWithA: true, now: start, calendar: calendar)
        let session = WorkoutSessionLog(id: "accepted", date: start.addingTimeInterval(3_600), routineID: "routine",
            completedExercises: [.init(id: "performed", exerciseName: "Press", exercise: exercise,
                sets: [.init(id: "completed", reps: 8, weight: 100)])],
            programContext: .init(programID: "program", slotIndex: experiment.trials[0].slot))
        return (experiment, session)
    }
    private func evidence(_ values: [ReminderExperimentEvidence]) -> ReminderEvidence {
        var result = ReminderEvidence(goals: .init(calories: 2_000, protein: 120, carbs: 200, fats: 60), waterGoal: 64)
        result.experimentCheckIns = values; return result
    }
    func testDefaultOffThenOneExactSessionReminderUsesSharedBudgetAndKeepsStableFireTime() throws {
        let (experiment, session) = try fixture(), now = start.addingTimeInterval(3_660)
        let eligible = ReminderExperimentEvidence.eligible(ownerID: "owner", experiments: [experiment], sessions: [session], now: now)
        XCTAssertEqual(eligible.count, 1)
        var record = ReminderAccountRecord()
        XCTAssertFalse(record.preferences[.experimentCheckIn].enabled)
        XCTAssertTrue(ReminderPolicy.decisions(ownerID: "owner", record: record, evidence: evidence(eligible), now: now, calendar: calendar).isEmpty)
        record.preferences[.experimentCheckIn].enabled = true
        let first = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "owner", record: record, evidence: evidence(eligible), now: now, calendar: calendar).first)
        XCTAssertEqual(first.state, .ready)
        XCTAssertEqual(first.candidate.target.experimentSessionID, session.id)
        record.decisions[first.id] = first
        let second = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "owner", record: record, evidence: evidence(eligible), now: now.addingTimeInterval(60), calendar: calendar).first)
        XCTAssertEqual(first.candidate.fingerprint, second.candidate.fingerprint, "Foreground refresh cannot push back or duplicate the same invitation.")
        record.preferences.maximumPerDay = 1
        record.reservations = [.init(key: "other", dayKey: "2026-11-04", kind: .dailyLog, reservedAt: now)]
        XCTAssertEqual(ReminderPolicy.decisions(ownerID: "owner", record: record, evidence: evidence(eligible), now: now, calendar: calendar).first?.state, .suppressed)
    }
    func testAnsweredSkippedConflictedWrongProgramLegacyExpiredAndAmbiguousSessionsAreIneligible() throws {
        let (experiment, session) = try fixture(), now = start.addingTimeInterval(3_660)
        func eligible(_ experiment: MealExperiment, _ sessions: [WorkoutSessionLog]) -> [ReminderExperimentEvidence] {
            ReminderExperimentEvidence.eligible(ownerID: "owner", experiments: [experiment], sessions: sessions, now: now)
        }
        var changed = experiment; changed.trials[0].skipped = true
        XCTAssertTrue(eligible(changed, [session]).isEmpty)
        changed = try MealExperimentRules.recording(in: experiment, trialID: experiment.trials[0].id, session: session,
            energy: 4, comfort: 4, minutesBefore: 90, confounders: [], now: now)
        XCTAssertTrue(eligible(changed, [session]).isEmpty)
        let observation = try XCTUnwrap(changed.trials[0].observation)
        changed = experiment; changed.trials[0].conflictingObservations = [observation]
        XCTAssertTrue(eligible(changed, [session]).isEmpty)
        var other = session; other.programContext = .init(programID: "foreign", slotIndex: experiment.trials[0].slot)
        XCTAssertTrue(eligible(experiment, [other]).isEmpty)
        other.programContext = nil
        XCTAssertTrue(eligible(experiment, [other]).isEmpty)
        other = session; other.id = "second-copy"
        XCTAssertTrue(eligible(experiment, [session, other]).isEmpty)
        XCTAssertTrue(ReminderExperimentEvidence.eligible(ownerID: "owner", experiments: [experiment], sessions: [session], now: session.date.addingTimeInterval(48 * 3_600)).isEmpty)
    }
    func testNotificationActionRejectsOtherAccountAndCorrectedSourceWithoutRecordingAnObservation() throws {
        let (experiment, session) = try fixture(), now = start.addingTimeInterval(3_660)
        var record = ReminderAccountRecord(); record.preferences[.experimentCheckIn].enabled = true
        let source = evidence(ReminderExperimentEvidence.eligible(ownerID: "owner", experiments: [experiment], sessions: [session], now: now))
        let candidate = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "owner", record: record, evidence: source, now: now, calendar: calendar).first?.candidate)
        XCTAssertTrue(ReminderPolicy.actionIsCurrent(candidate, ownerID: "owner", preferences: record.preferences, evidence: source, now: now, calendar: calendar))
        XCTAssertFalse(ReminderPolicy.actionIsCurrent(candidate, ownerID: "other", preferences: record.preferences, evidence: source, now: now, calendar: calendar))
        var correction = session; correction.correctionRevisionID = "changed"
        let revised = evidence(ReminderExperimentEvidence.eligible(ownerID: "owner", experiments: [experiment], sessions: [correction], now: now))
        XCTAssertFalse(ReminderPolicy.actionIsCurrent(candidate, ownerID: "owner", preferences: record.preferences, evidence: revised, now: now, calendar: calendar))
        XCTAssertTrue(experiment.trials.allSatisfy { $0.observation == nil })
    }
}
