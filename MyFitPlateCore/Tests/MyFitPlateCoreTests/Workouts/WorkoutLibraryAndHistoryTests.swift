import XCTest
@testable import MyFitPlateCore

@MainActor
final class WorkoutLibraryAndHistoryTests: XCTestCase {
    private let userID = "library-history-test"
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func program(progress: Int = 39) throws -> WorkoutProgram {
        let routines = (0..<4).map { index in
            WorkoutRoutine(id: "routine-\(index)", userID: userID, name: "Day \(index)", dateCreated: date,
                exercises: [RoutineExercise(id: "exercise-\(index)", name: "Squat", sets: [ExerciseSet(target: "8 reps")])])
        }
        var program = WorkoutProgram(id: "owner-phul", userID: userID, name: "PHUL", dateCreated: date,
            routines: routines, startDate: date, daysOfWeek: [2, 3, 5, 6], currentProgressIndex: progress, skippedIndices: [2, 9, 20])
        program.trainingBlock = try WorkoutBlockRules.createRepeatingBlock(for: program)
        return program
    }

    func testArchiveRestoreOnlyChangesArchiveMetadataAndRefusesActiveOrLinkedDraft() throws {
        let original = try program(); let fingerprint = try WorkoutBlockRules.fingerprint(original)
        XCTAssertThrowsError(try WorkoutLibraryRules.archiving(original, archived: true, activeProgramID: original.id))
        XCTAssertThrowsError(try WorkoutLibraryRules.archiving(original, archived: true, activeProgramID: "other", hasLinkedDraft: true))
        let archived = try WorkoutLibraryRules.archiving(original, archived: true, activeProgramID: "other", now: date)
        XCTAssertEqual(archived.archivedAt, date)
        XCTAssertEqual(archived.currentProgressIndex, 39)
        let restored = try WorkoutLibraryRules.archiving(archived, archived: false, activeProgramID: "other")
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(restored), fingerprint)
        XCTAssertEqual(try WorkoutBlockRules.fingerprint(original), fingerprint)
    }

    func testServiceCannotArchiveItsActivePlanAndRestoreKeepsProgress() async throws {
        let repository = MockWorkoutRepository(); let auth = MockAuthService(); auth.currentUserID = userID
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = repository
        let suite = "library-service-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = WorkoutService(defaults: defaults); let original = try program()
        service.userPrograms = [original]; service.activeProgram = original
        let rejected = await service.setProgramArchived(original, archived: true)
        XCTAssertFalse(rejected); XCTAssertTrue(repository.archiveSavedPrograms.isEmpty)
        service.activeProgram = nil
        let archived = await service.setProgramArchived(original, archived: true)
        XCTAssertTrue(archived); XCTAssertNotNil(service.userPrograms[0].archivedAt)
        XCTAssertEqual(service.userPrograms[0].currentProgressIndex, 39)
        let restored = await service.setProgramArchived(service.userPrograms[0], archived: false)
        XCTAssertTrue(restored); XCTAssertNil(service.userPrograms[0].archivedAt)
        XCTAssertEqual(service.userPrograms[0].currentProgressIndex, 39)
    }

    func testScheduleEditFreezesEveryPassedDateWithoutChangingLogsProgressOrSkips() throws {
        let original = try program(); var proposal = original
        proposal.startDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: original.startDate!))
        proposal.daysOfWeek = [1, 3, 4, 7]
        let saved = try WorkoutLibraryRules.preservingPassedDates(in: proposal, from: original)
        for index in 0..<39 { XCTAssertEqual(saved.date(forSlot: index), original.date(forSlot: index)) }
        XCTAssertNotEqual(saved.date(forSlot: 39), original.date(forSlot: 39))
        XCTAssertEqual(saved.currentProgressIndex, 39)
        XCTAssertEqual(saved.skippedIndices, original.skippedIndices)
        XCTAssertEqual(saved.slotDateSnapshots?.count, 39)
        XCTAssertNil(original.slotDateSnapshots)
        XCTAssertThrowsError(try WorkoutLibraryRules.preservingPassedDates(in: proposal, from: original, protectedSlots: [39]))
        proposal.daysOfWeek = [2, 5]
        XCTAssertThrowsError(try WorkoutLibraryRules.preservingPassedDates(in: proposal, from: original))
    }

    func testDelayedQueuedScheduleAndTitleCannotRewindNewerCompletionOrDropItsHistoricalDate() throws {
        let original = try program(); var queued = original
        queued.startDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: original.startDate!))
        var latest = original; latest.currentProgressIndex = 40; latest.skippedIndices?.append(39)
        let merged = try WorkoutLibraryRules.mergingQueuedProgram(queued, with: latest)
        XCTAssertEqual(merged.currentProgressIndex, 40)
        XCTAssertTrue(merged.skippedIndices?.contains(39) == true)
        XCTAssertEqual(merged.date(forSlot: 39), latest.date(forSlot: 39))
        XCTAssertEqual(merged.slotDateSnapshots?.count, 40)
    }

    func testArchiveOnlyOutboxOverlayKeepsConcurrentMetadataAndOrdinaryWritesKeepArchive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("archive-outbox-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let outbox = WorkoutOutbox(fileURL: folder.appendingPathComponent("outbox.json"))
        let old = try program(); var archive = old; archive.archivedAt = date
        let intent = try WorkoutPendingWrite(userID: userID, collection: .programs, documentID: old.id!, value: archive, programArchiveIntent: true)
        try outbox.append(intent)
        var latest = old; latest.name = "Newer reviewed title"; latest.currentProgressIndex = 40
        let overlay: [WorkoutProgram] = try outbox.overlay([latest], userID: userID, collection: .programs, id: { $0.id })
        XCTAssertEqual(overlay[0].name, latest.name)
        XCTAssertEqual(overlay[0].currentProgressIndex, 40)
        XCTAssertEqual(overlay[0].archivedAt, date)
        let staleMetadata = try WorkoutPendingWrite(userID: userID, collection: .programs, documentID: old.id!, value: old)
        try outbox.append(staleMetadata)
        let staleOverlay: [WorkoutProgram] = try outbox.overlay([latest], userID: userID, collection: .programs, id: { $0.id })
        XCTAssertEqual(staleOverlay[0].archivedAt, date)
        XCTAssertEqual(staleOverlay[0].currentProgressIndex, 40)
        var restore = old; restore.archivedAt = nil
        try outbox.append(WorkoutPendingWrite(userID: userID, collection: .programs, documentID: old.id!, value: restore, programArchiveIntent: true))
        let restored: [WorkoutProgram] = try outbox.overlay([latest], userID: userID, collection: .programs, id: { $0.id })
        XCTAssertNil(restored[0].archivedAt)
        XCTAssertEqual(restored[0].currentProgressIndex, 40)
    }

    func testOldOutboxRecordAndProgramDecodeWithoutInventedArchiveOrDateSnapshots() throws {
        let original = try program()
        let write = try WorkoutPendingWrite(userID: userID, collection: .programs, documentID: original.id!, value: original)
        let restored = try JSONDecoder().decode(WorkoutPendingWrite.self, from: JSONEncoder().encode(write))
        XCTAssertNil(restored.programArchiveIntent)
        let program = try JSONDecoder().decode(WorkoutProgram.self, from: XCTUnwrap(restored.payload))
        XCTAssertNil(program.archivedAt); XCTAssertNil(program.slotDateSnapshots)
        XCTAssertEqual(program.currentProgressIndex, 39)
    }

    func testFreshSuccessorNeverBorrowsArchivedStatusOrPassedDateSnapshots() throws {
        var original = try program(); original.archivedAt = date
        original.slotDateSnapshots = [WorkoutSlotDateSnapshot(slotIndex: 0, date: date)]
        let next = try WorkoutProgramSuccessorRules.prepare(from: original)
        XCTAssertNil(next.archivedAt); XCTAssertNil(next.slotDateSnapshots)
        XCTAssertEqual(next.currentProgressIndex, 0)
    }

    private func logs(_ count: Int) -> [WorkoutSessionLog] {
        (0..<count).map { index in
            let exercise = RoutineExercise(id: "squat", name: "Squat", sets: [])
            return WorkoutSessionLog(id: String(format: "session-%04d", index), date: date,
                routineID: "routine", completedExercises: [CompletedExercise(exerciseName: "Squat", exercise: exercise,
                    sets: [CompletedSet(reps: 8, weight: Double(index + 1))])])
        }
    }

    func testCompleteHistoryTraverses501TiedDatesWithoutDuplicatesOr200SessionCap() async throws {
        let repository = MockWorkoutRepository(); repository.mockFetchHistoryResult = logs(501)
        repository.mockFetchHistoryResult.append(repository.mockFetchHistoryResult[0])
        let all = try await repository.fetchCompleteWorkoutHistory(userID: userID, pageSize: 50)
        XCTAssertEqual(all.count, 501)
        XCTAssertEqual(Set(all.compactMap(\.id)).count, 501)
        XCTAssertEqual(all.last?.id, "session-0000")
        XCTAssertEqual(repository.historyPageRequests, 11)
    }

    func testCachedPagesRemainVisibleButCannotEstablishCompleteAnalyticsCoverage() async throws {
        let repository = MockWorkoutRepository(); repository.mockFetchHistoryResult = logs(10); repository.historyPagesFromCache = true
        let page = try await repository.fetchWorkoutHistoryPage(userID: userID, cursor: nil, pageSize: 50)
        XCTAssertEqual(page.logs.count, 10); XCTAssertTrue(page.isFromCache)
        do { _ = try await repository.fetchCompleteWorkoutHistory(userID: userID); XCTFail("Cached data cannot establish completeness") } catch {}
    }

    func testHistoryCursorIsOwnerBoundAndRetainsExactTimestampComponents() throws {
        let cursor = try WorkoutHistoryCursor(userID: userID, upperBound: date.addingTimeInterval(1),
            lastSeconds: 1_700_000_000, lastNanoseconds: 123_456_789, lastDocumentID: "session")
        let decoded = try JSONDecoder().decode(WorkoutHistoryCursor.self, from: JSONEncoder().encode(cursor))
        XCTAssertEqual(decoded.lastNanoseconds, 123_456_789)
        XCTAssertThrowsError(try decoded.validate(userID: "other"))
        XCTAssertThrowsError(try WorkoutHistoryCursor(userID: userID, upperBound: date, lastSeconds: 1_700_000_000,
            lastNanoseconds: -1, lastDocumentID: "session"))
    }

    func testExerciseTrendsIncludeEarlierHistoryBeyondThirtyAndTwoHundredSessions() async throws {
        let repository = MockWorkoutRepository(); repository.mockFetchHistoryResult = logs(501)
        let auth = MockAuthService(); auth.currentUserID = userID
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = repository
        let service = WorkoutAnalyticsService()
        let trends = await service.fetchTrends(for: "Squat", userID: userID)
        XCTAssertEqual(trends.count, 501)
        XCTAssertTrue(service.historyCoverageMessage?.contains("501") == true)
    }
    func testFutureDatedRecordsStayVisibleForCorrectionButCannotPoisonTrendsOrUseLast() async throws {
        let repository = MockWorkoutRepository(); var records = logs(2)
        records[0].date = date; records[1].date = Date.distantFuture
        records[1].completedExercises[0].sets[0].weight = 9_999
        repository.mockFetchHistoryResult = records
        let auth = MockAuthService(); auth.currentUserID = userID
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = repository
        let all = try await repository.fetchCompleteWorkoutHistory(userID: userID)
        XCTAssertEqual(all.count, 2, "Future mistakes remain available in History for correction")
        let trends = await WorkoutAnalyticsService().fetchTrends(for: "Squat", userID: userID)
        XCTAssertEqual(trends.count, 1); XCTAssertEqual(trends.first?.value, 1)
        let exercise = records[0].completedExercises[0].exercise
        let eligible = ProgressionRules.history(for: exercise, in: records, routineID: "routine", now: date)
        XCTAssertEqual(eligible.map(\.id), [records[0].id])
    }

    func testScheduleChangeKeepsConservativeLegacyEvidenceOnItsOriginalPassedDay() throws {
        let original = try program()
        let firstDay = try XCTUnwrap(original.date(forSlot: 0))
        let routine = try XCTUnwrap(original.routine(forSlot: 0))
        // A legacy session must occur after this program was created, even when CI uses UTC.
        let completion = max(firstDay, original.dateCreated).addingTimeInterval(1)
        let legacy = WorkoutSessionLog(id: "old-legacy", date: completion,
            routineID: routine.id, completedExercises: [])
        XCTAssertTrue(WorkoutRules.logBelongsToProgram(legacy, program: original))
        var proposal = original
        proposal.startDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 30, to: firstDay))
        let updated = try WorkoutLibraryRules.preservingPassedDates(in: proposal, from: original)
        XCTAssertTrue(WorkoutRules.logBelongsToProgram(legacy, program: updated))
        XCTAssertEqual(WorkoutRules.sessionLogsBySlot(in: updated, sessionLogs: [legacy])[0]?.id, legacy.id)
    }

}
