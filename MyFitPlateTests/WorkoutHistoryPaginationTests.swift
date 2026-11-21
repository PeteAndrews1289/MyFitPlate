import XCTest
import Combine
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class WorkoutHistoryPaginationTests: XCTestCase {
    private func sessions(_ count: Int = 122) -> [WorkoutSessionLog] {
        let movement = RoutineExercise(id: "bench", name: "Bench Press")
        return (0..<count).map { index in
            let sets = (0..<(14 + (index < 32 ? 1 : 0))).map { set in
                CompletedSet(id: "set-\(index)-\(set)", reps: 10, weight: 100)
            }
            return WorkoutSessionLog(id: "session-\(index)", date: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400), routineID: "routine",
                completedExercises: [CompletedExercise(id: "exercise-\(index)", exerciseName: "Bench Press", exercise: movement, sets: sets)])
        }
    }
    private func cursor(_ logs: [WorkoutSessionLog], at index: Int, owner: String = "owner") throws -> WorkoutHistoryCursor {
        try WorkoutHistoryCursor(userID: owner, upperBound: .distantFuture, lastSeconds: Int64(logs[index].date.timeIntervalSince1970), lastNanoseconds: 0, lastDocumentID: logs[index].id!)
    }
    private func page(_ logs: [WorkoutSessionLog], from offset: Int, owner: String = "owner", cached: Bool = false) throws -> WorkoutHistoryPage {
        let end = min(offset + 50, logs.count)
        return WorkoutHistoryPage(logs: Array(logs[offset..<end]), nextCursor: end < logs.count ? try cursor(logs, at: end - 1, owner: owner) : nil, isFromCache: cached)
    }

    func testEntryProgressivelyLoadsAll122SessionsAndRetains1740SetsAndFullVolume() async throws {
        let logs = sessions()
        var requests: [String] = [], observedCounts: [Int] = []
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { uid, cursor, size in
            XCTAssertEqual(uid, "owner"); XCTAssertEqual(size, 50)
            requests.append(cursor?.lastDocumentID ?? "first")
            let offset = cursor.map { Int($0.lastDocumentID.dropFirst("session-".count))! + 1 } ?? 0
            return try self.page(logs, from: offset)
        }
        let observation = loader.$logs.sink { if !$0.isEmpty { observedCounts.append($0.count) } }
        defer { observation.cancel() }
        await loader.load(force: false)
        XCTAssertEqual(observedCounts, [50, 100, 122], "The first page remains visible while older pages arrive")
        XCTAssertEqual(requests, ["first", "session-49", "session-99"])
        XCTAssertEqual(loader.logs.count, 122)
        XCTAssertEqual(loader.logs.reduce(0) { $0 + WorkoutSetMath.workingSetCount($1) }, 1_740)
        XCTAssertEqual(loader.logs.flatMap(\.completedExercises).flatMap(\.sets).reduce(0.0) { $0 + Double($1.reps) * $1.weight }, 1_740_000)
        XCTAssertTrue(loader.hasCompleteCoverage); XCTAssertFalse(loader.isLoadingMore)
        XCTAssertTrue(loader.coverageText.contains("All 122 dated sessions loaded"))
    }

    func testEarlierPageFailureKeeps50HonestPartialTotalsAndRetryLoadsRemainingWithoutDuplicates() async throws {
        let logs = sessions(); var failEarlier = true
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { _, cursor, _ in
            if cursor != nil && failEarlier { throw WorkoutHistoryReadError.unavailable }
            let offset = cursor.map { Int($0.lastDocumentID.dropFirst("session-".count))! + 1 } ?? 0
            return try self.page(logs, from: offset)
        }
        await loader.load(force: false)
        XCTAssertEqual(loader.logs.count, 50); XCTAssertFalse(loader.hasCompleteCoverage)
        XCTAssertTrue(loader.canLoadEarlier); XCTAssertNotNil(loader.loadError)
        XCTAssertTrue(loader.coverageText.contains("only the loaded sessions"))
        failEarlier = false
        await loader.loadRemaining()
        XCTAssertEqual(loader.logs.count, 122); XCTAssertEqual(Set(loader.logs.compactMap(\.id)).count, 122)
        XCTAssertTrue(loader.hasCompleteCoverage); XCTAssertNil(loader.loadError)
    }

    func testCachedPageDoesNotClaimCompleteHistoryOrAutomaticallyDrainUnconfirmedCache() async throws {
        let logs = sessions(); var reads = 0
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { _, _, _ in
            reads += 1; return try self.page(logs, from: 0, cached: true)
        }
        await loader.load(force: false)
        XCTAssertEqual(reads, 1); XCTAssertEqual(loader.logs.count, 50)
        XCTAssertFalse(loader.hasCompleteCoverage); XCTAssertTrue(loader.cachedCoverage)
        XCTAssertTrue(loader.coverageText.contains("cached sessions"))
    }

    func testAccountSwitchDuringReadCannotPublishPreviousOwnersHistory() async throws {
        let logs = sessions(); var owner = "owner"
        var pending: CheckedContinuation<WorkoutHistoryPage, Never>?
        let loader = WorkoutHistoryLoader(currentUserID: { owner }) { _, _, _ in
            await withCheckedContinuation { pending = $0 }
        }
        let request = Task { await loader.load(force: false) }
        while pending == nil { await Task.yield() }
        owner = "other"
        pending?.resume(returning: try page(logs, from: 0))
        await request.value
        XCTAssertTrue(loader.logs.isEmpty); XCTAssertFalse(loader.isLoading)
        XCTAssertFalse(loader.hasCompleteCoverage); XCTAssertFalse(loader.canLoadEarlier)
    }

    func testRefreshFencesOlderInFlightPageAndKeepsNewerRead() async throws {
        let logs = sessions(); var reads = 0
        var pending: CheckedContinuation<WorkoutHistoryPage, Never>?
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { _, _, _ in
            reads += 1
            if reads == 1 { return await withCheckedContinuation { pending = $0 } }
            return WorkoutHistoryPage(logs: [logs[121]], nextCursor: nil, isFromCache: false)
        }
        let oldRequest = Task { await loader.load(force: false) }
        while pending == nil { await Task.yield() }
        await loader.load(force: true)
        pending?.resume(returning: try page(logs, from: 0))
        await oldRequest.value
        XCTAssertEqual(loader.logs.compactMap(\.id), ["session-121"])
        XCTAssertTrue(loader.hasCompleteCoverage); XCTAssertFalse(loader.isLoadingMore)
    }

    func testCancelledEarlierReadCanResumeWithoutDroppingLoadedHistory() async throws {
        let logs = sessions(); var cancelled = true
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { _, cursor, _ in
            if cursor != nil && cancelled { throw CancellationError() }
            let offset = cursor.map { Int($0.lastDocumentID.dropFirst("session-".count))! + 1 } ?? 0
            return try self.page(logs, from: offset)
        }
        await loader.load(force: false)
        XCTAssertEqual(loader.logs.count, 50); XCTAssertFalse(loader.hasCompleteCoverage)
        XCTAssertTrue(loader.canLoadEarlier); XCTAssertFalse(loader.isLoadingMore)
        XCTAssertTrue(loader.loadError?.contains("paused") == true)
        cancelled = false; await loader.loadRemaining()
        XCTAssertEqual(loader.logs.count, 122); XCTAssertTrue(loader.hasCompleteCoverage)
    }

    func testRepeatedCursorStopsAutomaticReadInsteadOfLoopingOrClaimingCompleteTotals() async throws {
        let logs = sessions(); var reads = 0
        let sameCursor = try cursor(logs, at: 49)
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { _, _, _ in
            reads += 1
            return WorkoutHistoryPage(logs: Array(logs.prefix(50)), nextCursor: sameCursor, isFromCache: false)
        }
        await loader.load(force: false)
        XCTAssertEqual(reads, 2); XCTAssertEqual(loader.logs.count, 50)
        XCTAssertFalse(loader.hasCompleteCoverage); XCTAssertNotNil(loader.loadError)
        XCTAssertFalse(loader.isLoadingMore)
    }

    func testNewOwnerEntryClearsPreviouslyLoadedOwnerEvenWithoutForceRefresh() async throws {
        let logs = sessions(); var owner = "owner"
        let loader = WorkoutHistoryLoader(currentUserID: { owner }) { uid, _, _ in
            WorkoutHistoryPage(logs: uid == "owner" ? [logs[0]] : [logs[121]], nextCursor: nil, isFromCache: false)
        }
        await loader.load(force: false); XCTAssertEqual(loader.logs.first?.id, "session-0")
        owner = "other"; await loader.load(force: false)
        XCTAssertEqual(loader.logs.compactMap(\.id), ["session-121"])
        XCTAssertTrue(loader.hasCompleteCoverage)
    }
    func testLaterPageOverlayPreservesNewerVersionOfPreviouslyLoadedSession() async throws {
        let logs = sessions()
        var updated = logs[0]; updated.completedExercises[0].sets[0].weight = 125
        let loader = WorkoutHistoryLoader(currentUserID: { "owner" }) { _, cursor, _ in
            let offset = cursor.map { Int($0.lastDocumentID.dropFirst("session-".count))! + 1 } ?? 0
            let page = try self.page(logs, from: offset)
            return WorkoutHistoryPage(logs: offset == 50 ? [updated] + page.logs : page.logs, nextCursor: page.nextCursor, isFromCache: page.isFromCache)
        }
        await loader.load(force: false)
        XCTAssertEqual(loader.logs.count, 122)
        XCTAssertEqual(loader.logs.first { $0.id == "session-0" }?.completedExercises.first?.sets.first?.weight, 125)
        XCTAssertTrue(loader.hasCompleteCoverage)
    }

    func testLegacyExerciseLoadsAllPagesAndKeepsConfirmedValuesOnCachedRefresh() async throws {
        let repository = MockWorkoutRepository()
        repository.mockFetchHistoryResult = sessions()
        var legacy = RoutineExercise(id: "legacy", name: "  bench   press ")
        legacy.movementIdentity = nil
        let model = ExerciseHistoryViewModel(exercise: legacy, automaticallyLoads: false, currentUserID: { "owner" }) {
            try await repository.fetchCompleteWorkoutHistory(userID: $0)
        }
        await model.load()
        XCTAssertEqual(model.history.count, 122)
        XCTAssertEqual(repository.historyPageRequests, 2)
        XCTAssertEqual(model.history.flatMap(\.sets).count, 1_740)
        XCTAssertNil(model.loadError)
        repository.historyPagesFromCache = true
        repository.mockFetchHistoryResult = []
        await model.load()
        XCTAssertEqual(model.history.count, 122, "An empty offline cache must not erase confirmed history")
        XCTAssertTrue(model.loadError?.contains("Complete history could not refresh") == true)
    }

    func testExerciseHistoryRejectsLatePreviousOwnerAndClearsOnSignOut() async {
        let logs = sessions(1); var owner: String? = "owner"
        let model = ExerciseHistoryViewModel(exercise: RoutineExercise(name: "Bench Press"), automaticallyLoads: false,
            currentUserID: { owner }) { _ in
                owner = "other"
                return logs
            }
        await model.load()
        XCTAssertTrue(model.history.isEmpty); XCTAssertFalse(model.isLoading)
        owner = nil
        await model.load()
        XCTAssertTrue(model.history.isEmpty); XCTAssertNil(model.loadError)
    }

}
