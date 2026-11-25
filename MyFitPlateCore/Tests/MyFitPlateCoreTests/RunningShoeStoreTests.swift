import XCTest
@testable import MyFitPlateCore

final class RunningShoeStoreTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!
    private var authService: MockAuthService!
    private var store: RunningShoeStore!

    override func setUp() {
        super.setUp()
        suiteName = "RunningShoeStoreTests_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        authService = MockAuthService()
        authService.currentUserID = "runner-a"
        store = RunningShoeStore(userDefaults: testDefaults, authService: authService)
        store.addShoe(RunningShoe(name: "Road Trainer", brand: "Example", isDefault: true))
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        store = nil
        authService = nil
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshAccountDoesNotInventOwnedGear() {
        authService.currentUserID = "new-account"
        XCTAssertTrue(store.shoes.isEmpty)
        XCTAssertNil(store.defaultShoe())
    }

    func testAddShoeWithDefaultOverride() {
        let newShoe = RunningShoe(name: "Speed shoe", brand: "Nike", isDefault: true)
        store.addShoe(newShoe)

        XCTAssertEqual(store.shoes.count, 2)
        XCTAssertEqual(store.defaultShoe()?.name, "Speed shoe")
        let firstShoe = store.shoes.first(where: { $0.name == "Road Trainer" })
        XCTAssertFalse(firstShoe?.isDefault ?? true)
    }

    func testRetireDefaultShoeLeavesFutureRecordingsUnassigned() {
        let shoe2 = RunningShoe(name: "Daily Trainer", brand: "Brooks", isDefault: false)
        store.addShoe(shoe2)

        guard let defaultShoe = store.defaultShoe() else {
            XCTFail("Missing default shoe")
            return
        }
        store.retireShoe(id: defaultShoe.id)

        XCTAssertTrue(store.shoe(for: defaultShoe.id)?.isRetired ?? false)
        XCTAssertFalse(store.shoe(for: defaultShoe.id)?.isDefault ?? true)
        XCTAssertNil(store.defaultShoe())
        XCTAssertFalse(store.shoe(for: shoe2.id)?.isDefault ?? true)
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

    func testHealthIdentityUsesOriginalRecordingShoeTagWithoutOverwritingNewerExplicitChoices() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let original = RunningShoe(id: "original-shoe", name: "Original", brand: "A")
        let replacement = RunningShoe(id: "replacement-shoe", name: "Replacement", brand: "B")
        store.addShoe(original)
        store.addShoe(replacement)
        store.tagRun(runID: "recording-original", withShoeID: original.id)
        let run = Run(id: "health-uuid", source: .recorded, startDate: date, endDate: date.addingTimeInterval(600),
                      distanceMeters: 2_000, movingSeconds: 600, recordingID: "recording-original")
        XCTAssertEqual(store.applyTags(to: [run]).first?.shoeID, original.id)
        var embeddedChoice = run
        embeddedChoice.shoeID = replacement.id
        XCTAssertEqual(store.applyTags(to: [embeddedChoice]).first?.shoeID, replacement.id,
                       "The original recording fallback must not override an existing explicit choice")
        store.tagRun(runID: run.id, withShoeID: replacement.id)
        XCTAssertEqual(store.applyTags(to: [run]).first?.shoeID, replacement.id,
                       "A tag chosen for the confirmed Health identity takes precedence")
        var unrelated = run.reidentified(as: "unrelated")
        unrelated.recordingID = nil
        XCTAssertNil(store.applyTags(to: [unrelated]).first?.shoeID)
    }

    func testOriginalRecordingTagFallbackRemainsAccountScopedAndDoesNotUseDefaultShoe() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        store.tagRun(runID: "recording-original", withShoeID: "account-a-shoe")
        let run = Run(id: "health-uuid", source: .recorded, startDate: date, endDate: date.addingTimeInterval(600),
                      distanceMeters: 2_000, movingSeconds: 600, recordingID: "recording-original")
        authService.currentUserID = "runner-b"
        XCTAssertNil(store.applyTags(to: [run]).first?.shoeID)
        store.tagRun(runID: "recording-original", withShoeID: "account-b-shoe")
        XCTAssertEqual(store.applyTags(to: [run]).first?.shoeID, "account-b-shoe")
        authService.currentUserID = "runner-a"
        XCTAssertEqual(store.applyTags(to: [run]).first?.shoeID, "account-a-shoe")
        authService.currentUserID = nil
        XCTAssertNil(store.applyTags(to: [run]).first?.shoeID)
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

    func testShoesAndRunTagsAreIsolatedBetweenAccounts() {
        let accountAShoe = RunningShoe(name: "Account A Racer", brand: "A")
        store.addShoe(accountAShoe)
        store.tagRun(runID: "same-run", withShoeID: accountAShoe.id)

        authService.currentUserID = "runner-b"
        XCTAssertTrue(store.shoes.isEmpty)
        XCTAssertNil(store.shoeID(forRunID: "same-run"))

        let accountBShoe = RunningShoe(name: "Account B Trail", brand: "B")
        store.addShoe(accountBShoe)
        store.tagRun(runID: "same-run", withShoeID: accountBShoe.id)

        authService.currentUserID = "runner-a"
        XCTAssertNotNil(store.shoe(for: accountAShoe.id))
        XCTAssertNil(store.shoe(for: accountBShoe.id))
        XCTAssertEqual(store.shoeID(forRunID: "same-run"), accountAShoe.id)

        authService.currentUserID = "runner-b"
        XCTAssertNotNil(store.shoe(for: accountBShoe.id))
        XCTAssertNil(store.shoe(for: accountAShoe.id))
        XCTAssertEqual(store.shoeID(forRunID: "same-run"), accountBShoe.id)
    }

    func testSignedOutStoreDoesNotExposeOrPersistShoeData() {
        let accountAShoe = RunningShoe(name: "Private shoe", brand: "A")
        store.addShoe(accountAShoe)

        authService.currentUserID = nil
        XCTAssertTrue(store.shoes.isEmpty)
        store.addShoe(RunningShoe(name: "Signed-out shoe", brand: "None"))
        store.tagRun(runID: "signed-out-run", withShoeID: accountAShoe.id)

        authService.currentUserID = "runner-a"
        XCTAssertNotNil(store.shoe(for: accountAShoe.id))
        XCTAssertNil(store.shoes.first(where: { $0.name == "Signed-out shoe" }))
        XCTAssertNil(store.shoeID(forRunID: "signed-out-run"))
    }
}

extension RunningShoeStoreTests {
    func testCorruptExplicitTagDataIsKeptInsteadOfOverwritten() throws {
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "myfitplate.running_shoe_tags", userID: "runner-a"))
        let original = Data("unreadable original tags".utf8)
        testDefaults.set(original, forKey: key)
        store.tagRun(runID: "new-run", withShoeID: store.defaultShoe()?.id)
        XCTAssertEqual(testDefaults.data(forKey: key), original)
    }
    func testRetiredShoeIsNotAutomaticallyAssignedToFutureRecordings() throws {
        let shoe = try XCTUnwrap(store.defaultShoe())
        store.retireShoe(id: shoe.id)
        XCTAssertNil(store.defaultShoe())
        XCTAssertNotNil(store.shoe(for: shoe.id), "Historical explicit assignments retain their inventory reference")
    }
    func testExplicitNoneSurvivesEmbeddedTagAndHealthAliasReload() throws {
        let shoe = try XCTUnwrap(store.defaultShoe())
        let original = Run(id: "health-id", source: .recorded, startDate: Date(), endDate: Date(), distanceMeters: 5000,
                           movingSeconds: 1500, shoeID: shoe.id, recordingID: "recording-id")
        store.tagRun(original, withShoeID: nil)
        XCTAssertNil(store.explicitShoeID(for: original))
        let reloaded = RunningShoeStore(userDefaults: testDefaults, authService: authService)
        let alias = Run(id: "later-health-id", source: .recorded, startDate: original.startDate, endDate: original.endDate,
                        distanceMeters: original.distanceMeters, movingSeconds: original.movingSeconds,
                        shoeID: shoe.id, recordingID: "recording-id")
        XCTAssertNil(reloaded.explicitShoeID(for: alias))
        XCTAssertEqual(reloaded.totalMeters(for: shoe.id, across: [original, alias]), shoe.initialMeters)
        reloaded.tagRun(alias, withShoeID: shoe.id)
        XCTAssertEqual(reloaded.explicitShoeID(for: alias), shoe.id)
    }
    func testLifetimeMileageKeepsOldRunsAndDeduplicatesSameReceipt() throws {
        let shoe = try XCTUnwrap(store.defaultShoe())
        let start = Date().addingTimeInterval(-500 * 86400)
        let old = Run(id: "old", source: .recorded, startDate: start, endDate: start.addingTimeInterval(1800),
                      distanceMeters: 5000, movingSeconds: 1800, shoeID: shoe.id)
        XCTAssertEqual(store.totalMeters(for: shoe.id, across: [old, old]), shoe.initialMeters + 5000)
        var revised = old; revised.distanceMeters = 5500
        XCTAssertEqual(store.totalMeters(for: shoe.id, across: [revised]), shoe.initialMeters + 5500)
        store.tagRun(old, withShoeID: nil)
        XCTAssertEqual(store.totalMeters(for: shoe.id, across: [old]), shoe.initialMeters)
    }
    func testDefaultChangeNeverAssignsAnUnassignedOldRun() throws {
        let start = Date().addingTimeInterval(-200 * 86400)
        let old = Run(id: "unassigned", source: .imported(appName: "Apple Watch"), startDate: start, endDate: start.addingTimeInterval(1000), distanceMeters: 3000, movingSeconds: 1000)
        let shoe = RunningShoe(name: "New default", brand: "Example", isDefault: true)
        store.addShoe(shoe)
        XCTAssertNil(store.explicitShoeID(for: old))
        XCTAssertEqual(store.totalMeters(for: shoe.id, across: [old]), 0)
    }
}
