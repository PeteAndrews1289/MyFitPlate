import XCTest
@testable import MyFitPlateCore

@MainActor
final class CycleTrackingServiceTests: XCTestCase {
    private var originalCycleSettingsData: Data?
    private var originalLastPeriodStartDate: Date?

    override func setUpWithError() throws {
        originalCycleSettingsData = UserDefaults.standard.data(forKey: "cycleSettings")
        originalLastPeriodStartDate = UserDefaults.standard.object(forKey: "lastPeriodStartDate") as? Date
        UserDefaults.standard.removeObject(forKey: "cycleSettings")
        UserDefaults.standard.removeObject(forKey: "lastPeriodStartDate")
    }

    override func tearDownWithError() throws {
        if let originalCycleSettingsData {
            UserDefaults.standard.set(originalCycleSettingsData, forKey: "cycleSettings")
        } else {
            UserDefaults.standard.removeObject(forKey: "cycleSettings")
        }

        if let originalLastPeriodStartDate {
            UserDefaults.standard.set(originalLastPeriodStartDate, forKey: "lastPeriodStartDate")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastPeriodStartDate")
        }
    }

    func testInitializesWithoutCycleDayWhenNoPeriodStartExists() {
        let service = CycleTrackingService()

        XCTAssertNil(service.cycleDay)
    }

    func testLogPeriodStartCreatesMenstrualDayOne() {
        let service = CycleTrackingService()

        service.logPeriodStart()

        XCTAssertEqual(service.cycleDay?.cycleDayNumber, 1)
        XCTAssertEqual(service.cycleDay?.phase, .menstrual)
    }

    func testClearLastPeriodStartRemovesCycleDay() {
        let service = serviceWithLastPeriodStart(daysAgo: 3)
        XCTAssertNotNil(service.cycleDay)

        service.clearLastPeriodStart()

        XCTAssertNil(service.cycleDay)
    }

    func testDefaultPhaseBoundaries() {
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 0).cycleDay?.phase, .menstrual)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 5).cycleDay?.phase, .follicular)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 13).cycleDay?.phase, .ovulatory)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 17).cycleDay?.phase, .luteal)
    }

    func testCustomCycleSettingsAffectPhaseCalculation() throws {
        let customSettings = CycleSettings(typicalCycleLength: 32, typicalPeriodLength: 4)
        let data = try JSONEncoder().encode(customSettings)
        UserDefaults.standard.set(data, forKey: "cycleSettings")

        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 4).cycleDay?.phase, .follicular)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 15).cycleDay?.phase, .ovulatory)
        XCTAssertEqual(serviceWithLastPeriodStart(daysAgo: 19).cycleDay?.phase, .luteal)
    }

    func testCycleSettingsPersistWhenChanged() throws {
        let service = CycleTrackingService()

        service.cycleSettings = CycleSettings(typicalCycleLength: 31, typicalPeriodLength: 6)

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: "cycleSettings"))
        let decoded = try JSONDecoder().decode(CycleSettings.self, from: data)
        XCTAssertEqual(decoded.typicalCycleLength, 31)
        XCTAssertEqual(decoded.typicalPeriodLength, 6)
    }

    private func serviceWithLastPeriodStart(daysAgo: Int) -> CycleTrackingService {
        let startDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        UserDefaults.standard.set(Calendar.current.startOfDay(for: startDate), forKey: "lastPeriodStartDate")
        return CycleTrackingService()
    }
}
