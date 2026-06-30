import XCTest
@testable import MyFitPlateCore

@MainActor
final class JournalEntryStoreTests: XCTestCase {
    private var service: DailyLogService!
    private var mockRepo: MockNutritionRepository!
    private var store: JournalEntryStore!

    override func setUp() {
        super.setUp()
        mockRepo = MockNutritionRepository()
        DIContainer.shared.nutritionRepository = mockRepo
        DIContainer.shared.authService = MockAuthService()
        service = DailyLogService()
        store = JournalEntryStore(dailyLogService: service)
    }

    override func tearDown() {
        store = nil
        service = nil
        mockRepo = nil
        super.tearDown()
    }

    private func fixedDay(_ dayOffset: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_725_235_200)
        return Calendar.current.startOfDay(for: base.addingTimeInterval(Double(dayOffset) * 86_400))
    }

    private func entry(id: String, text: String = "Felt strong", category: String = "training") -> JournalEntry {
        JournalEntry(id: id, date: fixedDay(), text: text, category: category)
    }

    func testAddJournalEntryAppendsToCurrentViewedLogAndSaves() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        service.publishCurrentDailyLog(DailyLog(id: "log-1", date: viewedDate, meals: [], journalEntries: nil))

        await store.addJournalEntry(for: "user-1", entry: entry(id: "entry-1"))

        let savedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(savedLog.id, "log-1")
        XCTAssertEqual(savedLog.journalEntries?.map(\.id), ["entry-1"])
        XCTAssertEqual(service.currentDailyLog?.journalEntries?.map(\.id), ["entry-1"])
        XCTAssertEqual(mockRepo.savedDailyLogUserIDs, ["user-1"])
    }

    func testAddJournalEntryCreatesAndPublishesLogWhenNoCurrentLogExists() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate

        await store.addJournalEntry(for: "user-1", entry: entry(id: "entry-1", category: "recovery"))

        let savedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(savedLog.id, service.dateFormatter.string(from: viewedDate))
        XCTAssertEqual(savedLog.date, viewedDate)
        XCTAssertEqual(savedLog.journalEntries?.map(\.category), ["recovery"])
        XCTAssertEqual(service.currentDailyLog?.id, savedLog.id)
    }

    func testAddJournalEntryIgnoresStaleCurrentLogAndSavesViewedDate() async throws {
        let viewedDate = fixedDay()
        let staleDate = fixedDay(-1)
        service.activelyViewedDate = viewedDate
        service.publishCurrentDailyLog(
            DailyLog(id: "stale-log", date: staleDate, meals: [], journalEntries: [entry(id: "old-entry")])
        )

        await store.addJournalEntry(for: "user-1", entry: entry(id: "new-entry"))

        let savedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(savedLog.id, service.dateFormatter.string(from: viewedDate))
        XCTAssertEqual(savedLog.date, viewedDate)
        XCTAssertEqual(savedLog.journalEntries?.map(\.id), ["new-entry"])
        XCTAssertEqual(service.currentDailyLog?.date, viewedDate)
    }

    func testAddJournalEntryPublishesLocalStateEvenWhenSaveFails() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        mockRepo.saveDailyLogError = URLError(.notConnectedToInternet)

        await store.addJournalEntry(for: "user-1", entry: entry(id: "entry-1"))

        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertEqual(service.currentDailyLog?.journalEntries?.map(\.id), ["entry-1"])
    }

    func testDeleteJournalEntryRemovesMatchingEntryAndSaves() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        let first = entry(id: "entry-1")
        let second = entry(id: "entry-2", text: "Tired", category: "recovery")
        service.publishCurrentDailyLog(
            DailyLog(id: "log-1", date: viewedDate, meals: [], journalEntries: [first, second])
        )

        store.deleteJournalEntry(for: "user-1", entry: first)

        try await Task.sleep(nanoseconds: 50_000_000)

        let savedLog = try XCTUnwrap(mockRepo.lastUpdatedLog)
        XCTAssertEqual(savedLog.journalEntries?.map(\.id), ["entry-2"])
        XCTAssertEqual(service.currentDailyLog?.journalEntries?.map(\.id), ["entry-2"])
    }

    func testDeleteJournalEntrySkipsSaveWhenEntryIsMissing() async throws {
        let viewedDate = fixedDay()
        service.activelyViewedDate = viewedDate
        service.publishCurrentDailyLog(
            DailyLog(id: "log-1", date: viewedDate, meals: [], journalEntries: [entry(id: "entry-1")])
        )

        store.deleteJournalEntry(for: "user-1", entry: entry(id: "missing"))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertEqual(service.currentDailyLog?.journalEntries?.map(\.id), ["entry-1"])
    }

    func testDeleteJournalEntrySkipsSaveWhenCurrentLogIsForAnotherDay() async throws {
        let viewedDate = fixedDay()
        let staleDate = fixedDay(-1)
        let existing = entry(id: "entry-1")
        service.activelyViewedDate = viewedDate
        service.publishCurrentDailyLog(
            DailyLog(id: "stale-log", date: staleDate, meals: [], journalEntries: [existing])
        )

        store.deleteJournalEntry(for: "user-1", entry: existing)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(mockRepo.lastUpdatedLog)
        XCTAssertEqual(service.currentDailyLog?.journalEntries?.map(\.id), ["entry-1"])
    }
}
