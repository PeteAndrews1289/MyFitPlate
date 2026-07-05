import XCTest
@testable import MyFitPlateCore

final class AYCEScoreboardTests: XCTestCase {

    private func finishedSession(buffetPrice: Double, rolls: Int, citySlug: String? = nil) -> AYCESession {
        let roll = AYCECatalog.item(id: "sushi_spicy_tuna_roll")!  // $8.50 national
        return AYCESession(
            cuisine: .sushi,
            buffetPrice: buffetPrice,
            entries: [AYCESessionEntry(item: roll, count: rolls)],
            citySlug: citySlug
        )
    }

    func testRecordSnapshotsSessionTotalsIncludingCity() {
        let nyc = finishedSession(buffetPrice: 30, rolls: 3, citySlug: "nyc")
        let record = AYCESessionRecord(session: nyc)

        XCTAssertEqual(record.menuValue, 8.50 * 1.30 * 3, accuracy: 0.001, "Snapshot keeps the city-adjusted value")
        XCTAssertEqual(record.cuisine, .sushi)
        XCTAssertTrue(record.beatSpot)
        XCTAssertFalse(record.beatKitchen, "Three rolls never out-eat a $30 ingredient budget")
    }

    func testAppendingIsNewestFirstCappedAndIgnoresEmptySessions() {
        var records: [AYCESessionRecord] = []
        for index in 0..<(AYCEScoreboard.maxRecords + 10) {
            let record = AYCESessionRecord(
                session: finishedSession(buffetPrice: 20, rolls: 1),
                endedAt: Date(timeIntervalSince1970: Double(index))
            )
            records = AYCEScoreboard.appending(record, to: records)
        }
        XCTAssertEqual(records.count, AYCEScoreboard.maxRecords)
        XCTAssertTrue(records[0].date > records[1].date, "Newest first")

        let empty = AYCESessionRecord(session: finishedSession(buffetPrice: 20, rolls: 0))
        XCTAssertEqual(AYCEScoreboard.appending(empty, to: records).count, AYCEScoreboard.maxRecords,
                       "A session with nothing eaten never makes the scoreboard")
    }

    func testSummaryCountsWinsLossesAndBeatenDollars() {
        let win = AYCESessionRecord(session: finishedSession(buffetPrice: 20, rolls: 3))      // $25.50 vs $20 → +5.50
        let bigWin = AYCESessionRecord(session: finishedSession(buffetPrice: 20, rolls: 5))   // $42.50 vs $20 → +22.50
        let loss = AYCESessionRecord(session: finishedSession(buffetPrice: 50, rolls: 1))

        let summary = AYCEScoreboard.summary(of: [win, bigWin, loss])
        XCTAssertEqual(summary.sessions, 3)
        XCTAssertEqual(summary.wins, 2)
        XCTAssertEqual(summary.losses, 1)
        XCTAssertEqual(summary.totalBeatenBy, 5.50 + 22.50, accuracy: 0.001)
    }

    func testRecordLineTiers() {
        XCTAssertNil(AYCEScoreboard.recordLine(summary: AYCEScoreboard.summary(of: [])), "No history, no brag")

        let win = AYCESessionRecord(session: finishedSession(buffetPrice: 20, rolls: 3))
        let loss = AYCESessionRecord(session: finishedSession(buffetPrice: 50, rolls: 1))
        let line = AYCEScoreboard.recordLine(summary: AYCEScoreboard.summary(of: [win, loss]))

        XCTAssertEqual(line, "1 win · 1 loss · $5.50 beaten out of the spots")
        XCTAssertFalse(line?.contains("!") ?? true, "System copy never uses exclamation marks")

        // A kitchen defeat earns its clause: 12 rolls at $20 crosses even the ingredient budget.
        let kitchenWin = AYCESessionRecord(session: finishedSession(buffetPrice: 20, rolls: 12))
        let kitchenLine = AYCEScoreboard.recordLine(summary: AYCEScoreboard.summary(of: [kitchenWin]))
        XCTAssertTrue(kitchenLine?.hasSuffix("1 kitchen defeated") == true)
    }
}
