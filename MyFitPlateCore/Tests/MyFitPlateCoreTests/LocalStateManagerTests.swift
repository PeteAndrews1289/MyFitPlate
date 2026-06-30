import XCTest
@testable import MyFitPlateCore

@MainActor
final class LocalStateManagerTests: XCTestCase {
    private var originalPinnedNotes: Any?
    private var originalSpotlightIDs: [String]?

    override func setUp() {
        super.setUp()
        originalPinnedNotes = UserDefaults.standard.object(forKey: "pinnedExerciseNotes")
        originalSpotlightIDs = UserDefaults.standard.stringArray(forKey: "shownSpotlightIDs")
        UserDefaults.standard.removeObject(forKey: "pinnedExerciseNotes")
        UserDefaults.standard.removeObject(forKey: "shownSpotlightIDs")
        SharedDataManager.shared.clearWidgetData()
    }

    override func tearDown() {
        if let originalPinnedNotes {
            UserDefaults.standard.set(originalPinnedNotes, forKey: "pinnedExerciseNotes")
        } else {
            UserDefaults.standard.removeObject(forKey: "pinnedExerciseNotes")
        }

        if let originalSpotlightIDs {
            UserDefaults.standard.set(originalSpotlightIDs, forKey: "shownSpotlightIDs")
        } else {
            UserDefaults.standard.removeObject(forKey: "shownSpotlightIDs")
        }
        SharedDataManager.shared.clearWidgetData()
        super.tearDown()
    }

    func testPinnedNotesCanSetFetchOverwriteAndRemoveNotes() {
        let manager = PinnedNotesManager.shared

        XCTAssertNil(manager.getPinnedNote(for: "Squat"))
        XCTAssertFalse(manager.isNotePinned(for: "Squat"))

        manager.setPinnedNote(for: "Squat", note: "Brace hard")
        XCTAssertEqual(manager.getPinnedNote(for: "Squat"), "Brace hard")
        XCTAssertTrue(manager.isNotePinned(for: "Squat"))

        manager.setPinnedNote(for: "Squat", note: "Drive up")
        XCTAssertEqual(manager.getPinnedNote(for: "Squat"), "Drive up")

        manager.removePinnedNote(for: "Squat")
        XCTAssertNil(manager.getPinnedNote(for: "Squat"))
        XCTAssertFalse(manager.isNotePinned(for: "Squat"))
    }

    func testSpotlightManagerPersistsAndResetsShownIDs() {
        var manager = SpotlightManager()
        XCTAssertFalse(manager.isShown(id: "menuScanner"))

        manager.markAsShown(id: "menuScanner")
        manager.markAsShown(id: "pantryFeature")
        XCTAssertTrue(manager.isShown(id: "menuScanner"))
        XCTAssertTrue(manager.isShown(id: "pantryFeature"))

        manager = SpotlightManager()
        XCTAssertTrue(manager.isShown(id: "menuScanner"))
        XCTAssertTrue(manager.isShown(id: "pantryFeature"))

        manager.resetSpotlights()
        XCTAssertFalse(manager.isShown(id: "menuScanner"))
        XCTAssertTrue(UserDefaults.standard.stringArray(forKey: "shownSpotlightIDs")?.isEmpty ?? true)
    }

    func testSharedDataManagerSavesLoadsWaterAndClearsWidgetData() {
        let manager = SharedDataManager.shared
        let data = WidgetData(
            calories: 1_900,
            calorieGoal: 2_400,
            protein: 140,
            proteinGoal: 180,
            carbs: 210,
            carbsGoal: 260,
            fats: 60,
            fatGoal: 75,
            lastUpdated: Date(timeIntervalSince1970: 123),
            macroCalorieDelta: 12
        )

        XCTAssertTrue(manager.saveData(data))
        let loaded = manager.loadData()
        XCTAssertEqual(loaded?.calories, 1_900)
        XCTAssertEqual(loaded?.proteinGoal, 180)
        XCTAssertEqual(loaded?.macroCalorieDelta, 12)

        manager.logPendingWater(ounces: 8)
        manager.logPendingWater(ounces: 4)
        XCTAssertEqual(manager.getAndClearPendingWater(), 12, accuracy: 0.001)
        XCTAssertEqual(manager.getAndClearPendingWater(), 0, accuracy: 0.001)

        manager.clearWidgetData()
        XCTAssertNil(manager.loadData())
    }

    func testWidgetPreviewDataIsReasonableForWidgets() {
        let preview = WidgetData.previewData

        XCTAssertGreaterThan(preview.calorieGoal, preview.calories)
        XCTAssertGreaterThan(preview.proteinGoal, 0)
        XCTAssertNil(preview.macroCalorieDelta)
        XCTAssertNotNil(preview.lastUpdated)
    }
}
