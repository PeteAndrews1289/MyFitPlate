import XCTest
@testable import MyFitPlateCore

final class WaveTwoPlatformTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private func date(_ day: Int) -> Date { calendar.date(from: .init(year: 2026, month: 11, day: day))! }
    private func log(_ day: Int, status: NutritionDayStatus? = nil, entry: Bool = true) -> DailyLog {
        let food = FoodItem(id: "food", name: "Secret food", calories: 10, protein: 1, carbs: 1, fats: 0)
        return DailyLog(date: date(day), meals: entry ? [Meal(name: "Dinner", foodItems: [food])] : [], nutritionDayStatus: status)
    }
    private func snapshot() -> LivingDaySnapshot {
        .init(date: date(2), generatedAt: date(2), pathWindow: .init(start: date(2), end: date(3)),
              budget: .init(calories: .init(kind: .calories, consumed: 987, planned: 200, target: 2000),
                            protein: .init(kind: .protein, consumed: nil, planned: 0, target: 150),
                            carbs: .init(kind: .carbs, consumed: 0, planned: nil, target: 200),
                            fats: .init(kind: .fats, consumed: 4, planned: 3, target: 60)),
              events: (0..<7).map { index in .init(id: "private-account-id-\(index)", kind: .meal, state: .completed, title: "Secret event title", detail: "Secret coordinates", startDate: date(2).addingTimeInterval(Double(index) * 3600), timing: .approximate, evidence: .review, destination: .none) },
              trainingWindow: nil, nextAction: .init(kind: .proteinCatchUp, title: "Secret action", detail: "Secret health data", deepLink: "myfitplate://private"), freshness: .current(updatedAt: date(2)), currentTime: date(2))
    }
    func testPublicShareDefaultsExcludeSensitiveFieldsAndBoundPath() {
        let result = LivingDayPrivateShare(snapshot: snapshot(), options: .init(), foodNames: ["Secret food"], weightPounds: 155, dayStatus: .partial, calendar: calendar)
        XCTAssertTrue(result.text.contains("2026-11-02")); XCTAssertTrue(result.text.contains("Partly logged"))
        XCTAssertTrue(result.text.contains("5 of 7")); XCTAssertTrue(result.text.contains("Approx."))
        for value in ["Secret", "987", "155", "myfitplate://", "private-account", "protein gap"] { XCTAssertFalse(result.text.contains(value)) }
        XCTAssertEqual(result.lines.filter { $0.title == "Meal" }.count, 5)
    }
    func testShareAllPrivacyCombinationsOnlyExposeChosenFields() {
        for mask in 0..<64 {
            var options = LivingDayPrivateShare.Options()
            options.budget = mask & 1 != 0; options.path = mask & 2 != 0; options.foodNames = mask & 4 != 0
            options.weight = mask & 8 != 0; options.trust = mask & 16 != 0; options.action = mask & 32 != 0
            let result = LivingDayPrivateShare(snapshot: snapshot(), options: options, foodNames: ["Secret food"], weightPounds: 155, calendar: calendar)
            XCTAssertEqual(result.text.contains("987"), options.budget)
            XCTAssertEqual(result.text.contains("Secret food"), options.foodNames)
            XCTAssertEqual(result.text.contains("155.0 lb"), options.weight)
            XCTAssertEqual(result.text.contains("Data review:"), options.trust)
            XCTAssertEqual(result.text.contains("Next step:"), options.action)
            XCTAssertEqual(result.text.contains("Path scope:"), options.path)
            XCTAssertFalse(result.text.contains("coordinates")); XCTAssertFalse(result.text.contains("private-account"))
            XCTAssertEqual(result.text.split(separator: "\n").count, result.lines.count + 1)
        }
    }
    func testShareUnknownIsNotZeroAndCaptionIsBounded() {
        var options = LivingDayPrivateShare.Options(preset: .privateCheckIn); options.weight = true
        let result = LivingDayPrivateShare(snapshot: snapshot(), options: options, weightPounds: nil, metric: true, caption: String(repeating: "a", count: 300), calendar: calendar)
        XCTAssertEqual(result.caption.count, 180)
        XCTAssertTrue(result.text.contains("Eaten unknown; planned 0 g"))
        XCTAssertTrue(result.text.contains("Eaten 0 g; planned unknown"))
        XCTAssertTrue(result.text.contains("No captured measurement"))
        XCTAssertTrue(result.text.contains("Open / not reviewed"))
    }
    func testReviewedHabitUsesCanonicalReviewAndDeduplicatesImports() {
        var preferences = LoggingHabitPreferences(); preferences.reviewed = true; preferences.rule = .reviewedComplete
        let logs = [log(1, status: .complete), log(1, status: .complete), log(2, status: .partial), log(3, status: .complete)]
        let result = LoggingHabitRules.make(logs: logs, preferences: preferences, today: date(4), from: date(1), calendar: calendar)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.days.map(\.state), [.complete, .partial, .complete, .open])
        preferences.rule = .anyEntry
        XCTAssertEqual(LoggingHabitRules.make(logs: logs, preferences: preferences, today: date(4), from: date(1), calendar: calendar).count, 3)
    }
    func testHabitGracePauseAndFutureEvidence() {
        var preferences = LoggingHabitPreferences()
        let logs = [log(1), log(2), log(5)]
        let result = LoggingHabitRules.make(logs: logs, preferences: preferences, today: date(4), from: date(1), calendar: calendar)
        XCTAssertEqual(result.count, 2); XCTAssertEqual(result.days.last?.state, .open)
        XCTAssertEqual(result.days.dropLast().last?.state, .grace)
        preferences.paused = true
        let paused = LoggingHabitRules.make(logs: logs, preferences: preferences, today: date(4), from: date(1), calendar: calendar)
        XCTAssertEqual(paused.count, 0); XCTAssertFalse(paused.days.contains { $0.state == .grace })
        XCTAssertEqual(LoggingHabitRules.make(logs: logs, preferences: .init(), today: date(5), from: date(1), calendar: calendar).count, 1)
    }
    func testHabitPreferencesRejectStaleWriterAndKeepAccountsSeparate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LoggingHabitStore(store: EditorDraftStore(directory: directory))
        let initial = try store.load(userID: "a"); var hidden = initial; hidden.hidden = true
        try store.save(hidden, expected: initial, userID: "a")
        var paused = initial; paused.paused = true
        XCTAssertThrowsError(try store.save(paused, expected: initial, userID: "a"))
        XCTAssertEqual(try store.load(userID: "a"), hidden)
        XCTAssertEqual(try store.load(userID: "b"), initial)
    }
}
