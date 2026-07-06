import XCTest
@testable import MyFitPlateCore

final class RunStatsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_750_100_000)

    private func run(_ id: String, meters: Double, seconds: Double, daysAgo: Int = 0) -> Run {
        let start = base.addingTimeInterval(Double(-daysAgo) * 86_400)
        return Run(
            id: id,
            source: .imported(appName: "Garmin Connect"),
            startDate: start,
            endDate: start.addingTimeInterval(seconds),
            distanceMeters: meters,
            movingSeconds: seconds
        )
    }

    // MARK: Personal records

    func testRecordsPickLongestAndBestScaledTimes() {
        let records = RunStats.personalRecords(from: [
            run("easy5k", meters: 5000, seconds: 1600),      // 5K in 26:40
            run("fast6k", meters: 6000, seconds: 1740),      // scaled 5K = 1450 (24:10) — best 5K
            run("long12k", meters: 12_000, seconds: 4200)    // longest; scaled 10K = 3500 — best 10K
        ])

        XCTAssertEqual(records.longestRun?.id, "long12k")
        XCTAssertEqual(records.best5KRunID, "fast6k")
        XCTAssertEqual(records.best5KSeconds ?? 0, 1450, accuracy: 0.5)
        XCTAssertEqual(records.best10KRunID, "long12k")
        XCTAssertEqual(records.best10KSeconds ?? 0, 3500, accuracy: 0.5)
    }

    func testShortRunsNeverClaimDistanceRecords() {
        let records = RunStats.personalRecords(from: [
            run("sprint", meters: 3000, seconds: 700)
        ])
        XCTAssertEqual(records.longestRun?.id, "sprint")
        XCTAssertNil(records.best5KSeconds, "A 3K can't hold a 5K record")
        XCTAssertNil(records.best10KSeconds)
    }

    func testEmptyHistoryHasNoRecords() {
        let records = RunStats.personalRecords(from: [])
        XCTAssertNil(records.longestRun)
        XCTAssertNil(records.best5KSeconds)
    }

    func testSetsRecordDetectsNewBestsAndRejectsOrdinaryRuns() {
        let history = [
            run("old5k", meters: 5000, seconds: 1600, daysAgo: 10),
            run("old8k", meters: 8000, seconds: 2700, daysAgo: 5)
        ]

        let newLongest = run("new9k", meters: 9000, seconds: 3200)
        XCTAssertTrue(RunStats.setsRecord(newLongest, against: history + [newLongest]))

        let newFast5K = run("tempo", meters: 5000, seconds: 1400)
        XCTAssertTrue(RunStats.setsRecord(newFast5K, against: history + [newFast5K]))

        let ordinary = run("jog", meters: 4000, seconds: 1500)
        XCTAssertFalse(RunStats.setsRecord(ordinary, against: history + [ordinary]),
                       "A mid-pack run must not trigger the celebration")
    }

    // MARK: Ghost Pace

    func testGhostPaceDetectsLoopPRAndCalculatesDifferentials() {
        let history = [
            run("loop1", meters: 5000, seconds: 1500, daysAgo: 10), // 300 sec/km
            run("loop2", meters: 5100, seconds: 1581, daysAgo: 5),  // 310 sec/km
            run("other10k", meters: 10000, seconds: 3200, daysAgo: 2) // not similar distance
        ]

        let newPR = run("loop3", meters: 5050, seconds: 1464.5) // 290 sec/km (faster than 300)
        let comp = RunStats.ghostPaceComparison(for: newPR, against: history + [newPR])

        XCTAssertNotNil(comp)
        XCTAssertTrue(comp?.isPR == true)
        XCTAssertEqual(comp?.matchingRunsCount, 2)
        XCTAssertEqual(comp?.prPaceSecondsPerKm ?? 0, 300, accuracy: 0.1)
        XCTAssertEqual(comp?.averagePaceSecondsPerKm ?? 0, 305, accuracy: 0.1)
        XCTAssertEqual(comp?.paceDifferenceVsAverage ?? 0, -15, accuracy: 0.1) // 15 sec/km faster than avg
        XCTAssertEqual(comp?.paceDifferenceVsPR ?? 0, -10, accuracy: 0.1) // 10 sec/km faster than PR
    }

    func testGhostPaceWhenNotAPROnSimilarLoop() {
        let history = [
            run("loop1", meters: 5000, seconds: 1400, daysAgo: 10), // 280 sec/km
            run("loop2", meters: 5000, seconds: 1600, daysAgo: 5)   // 320 sec/km
        ]

        let slower = run("loop3", meters: 5000, seconds: 1500) // 300 sec/km (avg is 300)
        let comp = RunStats.ghostPaceComparison(for: slower, against: history + [slower])

        XCTAssertNotNil(comp)
        XCTAssertFalse(comp?.isPR == true)
        XCTAssertEqual(comp?.matchingRunsCount, 2)
        XCTAssertEqual(comp?.prPaceSecondsPerKm ?? 0, 280, accuracy: 0.1)
        XCTAssertEqual(comp?.averagePaceSecondsPerKm ?? 0, 300, accuracy: 0.1)
        XCTAssertEqual(comp?.paceDifferenceVsAverage ?? 0, 0, accuracy: 0.1)
    }

    // MARK: Weekly mileage

    func testWeeklyMileageZeroFillsQuietWeeksOldestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2

        // base falls on a Monday; with Monday-start weeks, daysAgo 7 (prev Monday) and
        // daysAgo 6 (prev Tuesday) are both squarely in "last week".
        let thisWeekRun = run("a", meters: 5000, seconds: 1500)
        let lastWeekRun1 = run("b", meters: 8000, seconds: 2400, daysAgo: 7)
        let lastWeekRun2 = run("c", meters: 4000, seconds: 1300, daysAgo: 6)

        let weeks = RunStats.weeklyMileage(
            runs: [thisWeekRun, lastWeekRun1, lastWeekRun2],
            weeks: 4,
            endingAt: base,
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(weeks[0].weekStart < weeks[3].weekStart, "Oldest first")
        XCTAssertEqual(weeks[0].meters, 0, "Quiet weeks are zero, not missing")
        XCTAssertEqual(weeks[1].meters, 0)
        XCTAssertEqual(weeks[2].meters, 12_000, accuracy: 0.01)
        XCTAssertEqual(weeks[2].runCount, 2)
        XCTAssertEqual(weeks[3].meters, 5000, accuracy: 0.01)
        XCTAssertEqual(weeks[3].runCount, 1)
    }

    func testWeeklyMileageHandlesDegenerateInputs() {
        XCTAssertTrue(RunStats.weeklyMileage(runs: [], weeks: 0).isEmpty)
        let empty = RunStats.weeklyMileage(runs: [], weeks: 3)
        XCTAssertEqual(empty.count, 3)
        XCTAssertTrue(empty.allSatisfy { $0.meters == 0 })
    }

    // MARK: Negative Split & Fastest Split

    func testNegativeSplitDetection() {
        let positiveSplits = [
            RunSplit(index: 1, distanceMeters: 1000, seconds: 240), // 4:00/km
            RunSplit(index: 2, distanceMeters: 1000, seconds: 260)  // 4:20/km (slower second half)
        ]
        XCTAssertFalse(RunStats.isNegativeSplit(splits: positiveSplits))

        let negativeSplits = [
            RunSplit(index: 1, distanceMeters: 1000, seconds: 300), // 5:00/km
            RunSplit(index: 2, distanceMeters: 1000, seconds: 280)  // 4:40/km (faster second half)
        ]
        XCTAssertTrue(RunStats.isNegativeSplit(splits: negativeSplits))
        XCTAssertEqual(RunStats.negativeSplitDeltaSecondsPerKm(splits: negativeSplits) ?? 0, 20.0, accuracy: 0.1)
    }

    func testFastestSplit() {
        let splits = [
            RunSplit(index: 1, distanceMeters: 1000, seconds: 300),
            RunSplit(index: 2, distanceMeters: 1000, seconds: 270), // Fastest valid
            RunSplit(index: 3, distanceMeters: 150, seconds: 30)    // Tiny tail (<200m), should be ignored
        ]
        let best = RunStats.fastestSplit(splits: splits)
        XCTAssertEqual(best?.index, 2)
    }
}

final class RouteSimplifyTests: XCTestCase {

    private func trace(_ count: Int) -> [RunLocationFix] {
        (0..<count).map {
            RunLocationFix(latitude: 40 + Double($0) * 0.0001, longitude: -74,
                           horizontalAccuracy: 5,
                           timestamp: Date(timeIntervalSince1970: Double($0)))
        }
    }

    func testShortTracesPassThroughUntouched() {
        let short = trace(150)
        XCTAssertEqual(RouteSimplify.decimate(short, maxPoints: 200), short)
    }

    func testLongTracesThinToTheCapWithEndpointsIntact() {
        let long = trace(3600)
        let thinned = RouteSimplify.decimate(long, maxPoints: 200)
        XCTAssertEqual(thinned.count, 200)
        XCTAssertEqual(thinned.first, long.first, "Start point must survive")
        XCTAssertEqual(thinned.last, long.last, "End point must survive")
        let latitudes = thinned.map(\.latitude)
        XCTAssertEqual(latitudes, latitudes.sorted(), "Order is preserved")
    }

    func testDegenerateCapReturnsInput() {
        let input = trace(10)
        XCTAssertEqual(RouteSimplify.decimate(input, maxPoints: 1), input)
    }
}
