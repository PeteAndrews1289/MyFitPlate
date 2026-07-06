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
        var shoe = RunningShoe(name: "Old shoe", brand: "Asics", initialMeters: 500000, maxMeters: 500000)
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
        XCTAssertEqual(applied[0].shoeID, defaultShoe.id)
        XCTAssertEqual(applied[1].shoeID, shoe2.id)
    }
}
