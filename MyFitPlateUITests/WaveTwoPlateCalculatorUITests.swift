import XCTest

final class WaveTwoPlateCalculatorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLargestTextCalculatorKeepsHeaderCompactAndTargetEditable() {
        let app = XCUIApplication()
        launch(app, resets: true, largestText: true)
        let content = app.scrollViews["plate_calculator_content"]
        XCTAssertTrue(content.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThan(content.frame.minY, app.frame.height * 0.3, app.debugDescription)
        XCTAssertGreaterThan(content.frame.height, app.frame.height * 0.55, app.debugDescription)
        let input = app.textFields["plate_calculator_input"]
        replace(input, with: "185", app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(Double(input.value as? String ?? ""), 185)
        XCTAssertTrue(input.isHittable, app.debugDescription)
        record(app, "Plate calculator - compact header and editable target at largest text")
    }

    @MainActor
    func testSavedKilogramBarUsesActualInventoryAndRestoresWithoutReinterpretingPounds() {
        let app = XCUIApplication()
        launch(app, resets: true)
        XCTAssertEqual(Double(app.textFields["plate_calculator_input"].value as? String ?? ""), 225)
        open(app.buttons["plate_calculator_choose_gym"], app: app)
        open(app.buttons["Choose or create a gym"], app: app)
        open(app.buttons["gym_profile_add"], app: app)
        replace(app.textFields["gym_profile_name"], with: "Metric plate gym", app: app)
        open(app.buttons["gym_profile_add_implement"], app: app)
        open(app.buttons["equipment_preset_barbell"], app: app)
        replace(app.textFields["equipment_name"], with: "20 kg training bar", app: app)
        let units = app.segmentedControls["equipment_units"]
        open(units.buttons["kg"], app: app)
        replace(app.textFields["equipment_bar_weight"], with: "20", app: app)
        replace(app.textFields["equipment_plates"], with: "20 10 5 2.5", app: app)
        open(app.buttons["equipment_save"], app: app)
        XCTAssertTrue(app.buttons["equipment_save"].waitForNonExistence(timeout: 5))
        open(app.buttons["gym_profile_save"], app: app)
        XCTAssertTrue(app.buttons["gym_profile_save"].waitForNonExistence(timeout: 5))
        open(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gym_profile_use_")).firstMatch, app: app)
        open(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gym_implement_choose_")).firstMatch, app: app)
        let selected = any(app, "plate_calculator_equipment")
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue(selected.label.contains("Metric plate gym"))
        replace(app.textFields["plate_calculator_input"], with: "72", app: app)
        let summary = any(app, "plate_calculator_summary")
        reveal(summary, app: app)
        XCTAssertTrue(summary.label.contains("72 kg"))
        XCTAssertTrue(summary.label.contains("70 kg"))
        XCTAssertTrue(summary.label.contains("2 kg under"))
        XCTAssertFalse(summary.label.contains("Exact"))
        let bar = any(app, "plate_calculator_bar")
        reveal(bar, app: app); XCTAssertTrue(bar.label.contains("20 kg"))
        let display = app.segmentedControls["plate_calculator_units"]
        open(display.buttons["lb"], app: app)
        open(display.buttons["kg"], app: app)
        XCTAssertEqual(Double(app.textFields["plate_calculator_input"].value as? String ?? "") ?? 0, 72, accuracy: 0.000001)
        replace(app.textFields["plate_calculator_input"], with: "70", app: app)
        reveal(summary, app: app); XCTAssertTrue(summary.label.contains("Exact"))
        record(app, "Plate calculator - real 20 kg bar and attainable inventory")
        app.terminate()
        launch(app, resets: false)
        reveal(selected, app: app)
        XCTAssertTrue(selected.label.contains("Metric plate gym"))
        let restoredInput = app.textFields["plate_calculator_input"]
        XCTAssertEqual(Double(restoredInput.value as? String ?? "") ?? 0, 102.058, accuracy: 0.001,
            "The legacy 225 lb launch target must retain its physical weight when the saved kg profile restores")
        open(app.buttons["plate_calculator_standard"], app: app)
        open(display.buttons["lb"], app: app)
        XCTAssertEqual(Double(restoredInput.value as? String ?? ""), 225)
        reveal(summary, app: app); XCTAssertTrue(summary.label.contains("Exact"))
        record(app, "Plate calculator - explicit standard preset and canonical pound target")
    }

    @MainActor private func launch(_ app: XCUIApplication, resets: Bool, largestText: Bool = false) {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "plate-calculator"]
        if resets { app.launchArguments += ["-ui-testing-reset-editor-drafts"] }
        if !resets || largestText {
            app.launchArguments += ["-screenshot-dark-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let root = any(app, "plate_calculator_screen")
        if !root.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists {
            app.terminate(); app.launch()
        }
        XCTAssertTrue(root.waitForExistence(timeout: 10))
    }

    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
    @MainActor private func open(_ target: XCUIElement, app: XCUIApplication) {
        reveal(target, app: app); target.tap()
    }
    @MainActor private func replace(_ field: XCUIElement, with text: String, app: XCUIApplication) {
        reveal(field, app: app)
        field.replaceContents(with: text, in: app)
        for id in ["plate_calculator_keyboard_done", "gym_profile_keyboard_done", "equipment_finish_edit", "equipment_keyboard_done"] {
            let done = app.buttons[id]
            if done.exists && done.isHittable { done.tap(); break }
        }
    }
    @MainActor private func reveal(_ target: XCUIElement, app: XCUIApplication) {
        for attempt in 0..<30 {
            let ids = ["strength_equipment_form", "gym_profile_editor", "gym_profile_library", "plate_calculator_content"]
            let named = ids.lazy.compactMap { id -> XCUIElement? in
                for type in [XCUIElement.ElementType.collectionView, .table, .scrollView] {
                    let surface = app.descendants(matching: type)[id].firstMatch
                    if surface.exists && surface.isHittable { return surface }
                }
                return nil
            }.first
            let surface = named ?? app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
                ?? app.tables.allElementsBoundByIndex.last(where: \.isHittable)
                ?? app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
            let top = max(surface?.frame.minY ?? 100, app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)?.frame.maxY ?? 100) + 4
            var bottom = min(surface?.frame.maxY ?? app.frame.maxY - 40, app.frame.maxY - 40) - 4
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 4) }
            let fixed = ["equipment_save", "gym_profile_save"].map { app.buttons[$0] }.filter { $0.exists && $0.isHittable }
            if target.exists, target.isHittable, app.frame.contains(target.frame), fixed.contains(where: { $0.identifier == target.identifier }) { return }
            if let pinned = fixed.map(\.frame.minY).filter({ $0 > top }).min() { bottom = min(bottom, pinned - 4) }
            if target.exists, target.isHittable, target.frame.minY >= top, target.frame.maxY <= bottom { return }
            guard bottom - top > 50 else { break }
            let down = target.exists && target.frame.height > 0 ? target.frame.minY < top : attempt > 20
            let middle = (top + bottom) / 2
            let end = min(bottom - 5, max(top + 5, middle + (down ? 1 : -1) * min(170, (bottom - top) * 0.4)))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: middle)).press(forDuration: 0.03,
                thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)))
        }
        XCTAssertTrue(target.exists && target.isHittable, "Could not reach \(target.identifier)\n\(app.debugDescription)")
    }
    @MainActor private func record(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name
        screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
