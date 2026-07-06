import XCTest
@testable import MyFitPlateCore

final class RunningShoeStoreTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var store: RunningShoeStore!

    override func setUp() {
        super.setUp()
        suiteName = "RunningShoeStoreTests_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        store = RunningShoeStore(userDefaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        store = nil
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultSeeding() {
        XCTAssertEqual(store.shoes.count, 1)
        XCTAssertEqual(store.shoes.first?.name, "Road Trainer")
        XCTAssertTrue(store.shoes.first?.isDefault ?? false)
    }

    func testAddShoeWithDefaultOverride() {
        let newShoe = RunningShoe(name: "Speed shoe", brand: "Nike", isDefault: true)
        store.addShoe(newShoe)

        XCTAssertEqual(store.shoes.count, 2)
        XCTAssertEqual(store.defaultShoe()?.name, "Speed shoe")
        let firstShoe = store.shoes.first(where: { $0.name == "Road Trainer" })
        XCTAssertFalse(firstShoe?.isDefault ?? true)
    }

    func testRetireDefaultShoePromotesNext() {
        let shoe2 = RunningShoe(name: "Daily Trainer", brand: "Brooks", isDefault: false)
        store.addShoe(shoe2)

        guard let defaultShoe = store.defaultShoe() else {
            XCTFail("Missing default shoe")
            return
        }
        store.retireShoe(id: defaultShoe.id)

        XCTAssertTrue(store.shoe(for: defaultShoe.id)?.isRetired ?? false)
        XCTAssertFalse(store.shoe(for: defaultShoe.id)?.isDefault ?? true)
        XCTAssertEqual(store.defaultShoe()?.name, "Daily Trainer")
        XCTAssertTrue(store.defaultShoe()?.isDefault ?? false)
    }

    func testMileageCalculationAndWearPercentage() {
        guard let defaultShoe = store.defaultShoe() else {
            XCTFail("Missing default shoe")
            return
        }

        let run1 = Run(source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 10000, movingSeconds: 3000, shoeID: defaultShoe.id)
        let run2 = Run(source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 5000, movingSeconds: 1500, shoeID: defaultShoe.id)
        let otherRun = Run(source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 20000, movingSeconds: 6000, shoeID: "other-id")

        let totalMeters = store.totalMeters(for: defaultShoe.id, across: [run1, run2, otherRun])
        XCTAssertEqual(totalMeters, 15000)

        // Default maxMeters is ~563270.4 meters (350 miles)
        let wear = store.wearPercentage(for: defaultShoe.id, across: [run1, run2, otherRun])
        XCTAssertEqual(wear, 15000 / defaultShoe.maxMeters, accuracy: 0.0001)
        XCTAssertFalse(store.isWornOut(shoeID: defaultShoe.id, across: [run1, run2, otherRun]))
    }

    func testWornOutShoeDetection() {
        let shoe = RunningShoe(name: "Old shoe", brand: "Asics", initialMeters: 500000, maxMeters: 500000)
        store.addShoe(shoe)

        XCTAssertTrue(store.isWornOut(shoeID: shoe.id, across: []))
    }

    func testShoeTaggingAndApplyTags() {
        guard let defaultShoe = store.defaultShoe() else {
            XCTFail("Missing default shoe")
            return
        }
        let shoe2 = RunningShoe(name: "Trail Shoe", brand: "Hoka", isDefault: false)
        store.addShoe(shoe2)

        let untaggedRun = Run(id: "run-1", source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 5000, movingSeconds: 1500)
        let customRun = Run(id: "run-2", source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 10000, movingSeconds: 3000)

        store.tagRun(runID: "run-2", withShoeID: shoe2.id)
        XCTAssertEqual(store.shoeID(forRunID: "run-2"), shoe2.id)

        let applied = store.applyTags(to: [untaggedRun, customRun])
        XCTAssertEqual(applied.count, 2)
        XCTAssertNil(applied[0].shoeID, "Untagged history stays untagged — the default shoe is not retroactive")
        XCTAssertEqual(applied[1].shoeID, shoe2.id)
        XCTAssertFalse(defaultShoe.isRetired)
    }

    func testSwitchingDefaultShoeNeverRewritesHistoryMileage() {
        guard let originalDefault = store.defaultShoe() else {
            XCTFail("Missing default shoe")
            return
        }
        let newShoe = RunningShoe(name: "Fresh Foam", brand: "NB")
        store.addShoe(newShoe)

        // One explicitly tagged run, one untagged historical import.
        store.tagRun(runID: "tagged", withShoeID: originalDefault.id)
        let tagged = Run(id: "tagged", source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 8000, movingSeconds: 2400)
        let historical = Run(id: "old", source: .imported(appName: "Garmin Connect"), startDate: Date(), endDate: Date(), distanceMeters: 50_000, movingSeconds: 15_000)

        let beforeSwitch = store.totalMeters(for: newShoe.id, across: store.applyTags(to: [tagged, historical]))
        store.setDefaultShoe(id: newShoe.id)
        let afterSwitch = store.totalMeters(for: newShoe.id, across: store.applyTags(to: [tagged, historical]))

        XCTAssertEqual(beforeSwitch, afterSwitch, accuracy: 0.001,
                       "Changing the default must not move 50 km of history onto the new shoe")
        XCTAssertEqual(afterSwitch, newShoe.initialMeters, accuracy: 0.001)

        let originalMeters = store.totalMeters(for: originalDefault.id, across: store.applyTags(to: [tagged, historical]))
        XCTAssertEqual(originalMeters, originalDefault.initialMeters + 8000, accuracy: 0.001, "Explicit tags stay put")
    }

    func testShoePerformanceAnalytics() {
        let fastShoe = RunningShoe(name: "Vaporfly", brand: "Nike")
        let slowShoe = RunningShoe(name: "Pegasus", brand: "Nike")
        store.addShoe(fastShoe)
        store.addShoe(slowShoe)

        let run1 = Run(id: "r1", source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 5000, movingSeconds: 1000, shoeID: fastShoe.id) // 200 s/km
        let run2 = Run(id: "r2", source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 10000, movingSeconds: 3000, shoeID: slowShoe.id) // 300 s/km

        let fastPace = store.averagePaceSecondsPerKm(for: fastShoe.id, across: [run1, run2])
        let slowPace = store.averagePaceSecondsPerKm(for: slowShoe.id, across: [run1, run2])

        XCTAssertEqual(fastPace ?? 0, 200, accuracy: 0.1)
        XCTAssertEqual(slowPace ?? 0, 300, accuracy: 0.1)
        XCTAssertEqual(store.runCount(for: fastShoe.id, across: [run1, run2]), 1)
        XCTAssertEqual(store.longestRunDistance(for: slowShoe.id, across: [run1, run2]), 10000)
        XCTAssertEqual(store.fastestShoeID(across: [run1, run2]), fastShoe.id)
    }
}
