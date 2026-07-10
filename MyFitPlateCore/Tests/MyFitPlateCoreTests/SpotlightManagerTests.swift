import XCTest
@testable import MyFitPlateCore

@MainActor
final class SpotlightManagerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SpotlightManagerTests_\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName = suiteName {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        testDefaults = nil
        super.tearDown()
    }

    func testInitialStateIsEmpty() {
        let manager = SpotlightManager(defaults: testDefaults)
        XCTAssertTrue(manager.shownSpotlightIDs.isEmpty)
        XCTAssertEqual(manager.replayToken, 0)
        XCTAssertFalse(manager.isShown(id: "home_macro_card"))
    }

    func testMarkAsShownPersistsAcrossInstances() {
        let manager1 = SpotlightManager(defaults: testDefaults)
        manager1.markAsShown(id: "home_macro_card")
        XCTAssertTrue(manager1.isShown(id: "home_macro_card"))

        let manager2 = SpotlightManager(defaults: testDefaults)
        XCTAssertTrue(manager2.isShown(id: "home_macro_card"))
    }

    func testResetSpotlightsClearsMemoryAndPersistence() {
        let manager = SpotlightManager(defaults: testDefaults)
        manager.markAsShown(id: "maia_quick_actions")
        manager.markAsShown(id: "maia_ask_bar")
        XCTAssertEqual(manager.shownSpotlightIDs.count, 2)

        manager.resetSpotlights()
        XCTAssertTrue(manager.shownSpotlightIDs.isEmpty)
        XCTAssertFalse(manager.isShown(id: "maia_quick_actions"))

        let reloaded = SpotlightManager(defaults: testDefaults)
        XCTAssertTrue(reloaded.shownSpotlightIDs.isEmpty)
    }

    func testRequestReplayIncrementsTokenAndResetsSpotlights() {
        let manager = SpotlightManager(defaults: testDefaults)
        manager.markAsShown(id: "train_hub")
        XCTAssertEqual(manager.replayToken, 0)

        manager.requestReplay()
        XCTAssertEqual(manager.replayToken, 1)
        XCTAssertTrue(manager.shownSpotlightIDs.isEmpty)
        XCTAssertFalse(manager.isShown(id: "train_hub"))
    }
}
