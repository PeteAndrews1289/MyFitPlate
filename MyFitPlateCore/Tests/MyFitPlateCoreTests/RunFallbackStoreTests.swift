import XCTest
@testable import MyFitPlateCore

final class RunFallbackStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: RunFallbackStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "RunFallbackStoreTests")
        defaults.removePersistentDomain(forName: "RunFallbackStoreTests")
        store = RunFallbackStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "RunFallbackStoreTests")
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testFallbackRunIsAccountScopedAndDropsRouteClaim() {
        let run = Run(
            source: .recorded,
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_800),
            distanceMeters: 5_000,
            movingSeconds: 1_800,
            hasRoute: true
        )

        XCTAssertTrue(store.save(run, for: "first-user"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "first-user").count, 1)
        XCTAssertFalse(store.runs(since: .distantPast, for: "first-user")[0].hasRoute)
        XCTAssertTrue(store.runs(since: .distantPast, for: "second-user").isEmpty)
    }

    func testFallbackSaveReplacesSameRunInsteadOfDuplicatingIt() {
        let run = Run(
            id: "run-1",
            source: .recorded,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1_800),
            distanceMeters: 5_000,
            movingSeconds: 1_800
        )

        XCTAssertTrue(store.save(run, for: "user"))
        XCTAssertTrue(store.save(run, for: "user"))
        XCTAssertEqual(store.runs(since: .distantPast, for: "user").count, 1)
    }
}
