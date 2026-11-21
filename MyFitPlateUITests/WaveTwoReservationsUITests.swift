import XCTest

final class WaveTwoReservationsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testPlannedReservationsStaySeparateFromPhysicalStockAndOwnCookingAllocation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", "meal-plan",
            "-ui-testing-wave2-inventory", "-ui-testing-stock-reservations", "-ui-testing-reset-editor-drafts"]
        app.launch()
        let workspace = app.segmentedControls["planner_workspace"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 12)); workspace.buttons["Cook"].tap()
        let reservations = app.buttons["inventory_planned_reservations"]
        let tools = app.buttons["Cooking tools and settings"]
        reveal(tools, app: app); tools.tap()
        reveal(reservations, app: app); reservations.tap()
        XCTAssertTrue(any(app, "inventory_reservations_screen").waitForExistence(timeout: 10))
        let row = any(app, "inventory_reservation_lot_00000000-0000-0000-0000-000000000201")
        reveal(row, app: app)
        let text = row.label.replacingOccurrences(of: ",", with: "")
        XCTAssertTrue(text.contains("Physical 1000 g"), text)
        XCTAssertTrue(text.contains("Planned 1000 g"), text)
        XCTAssertTrue(text.contains("Unallocated physical 0 g"), text)
        let future = any(app, "inventory_reservation_requirement_batch-reservation-later-batch")
        reveal(future, app: app); future.tap()
        let shortage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Missing 200 g'")).firstMatch
        reveal(shortage, app: app); XCTAssertTrue(shortage.exists)
        capture(app, "Reservations - physical amounts, cross-week allocation and shortage")
        app.navigationBars["Planned reservations"].buttons["Done"].tap()
        let cook = app.buttons["inventory_record_cooked_wave2-cooking-batch"]
        reveal(cook, app: app); cook.tap()
        let openedCookingReview = any(app, "inventory_cook_form").waitForExistence(timeout: 10)
        if !openedCookingReview { diagnostics(app, "Reservations - cooking review did not open") }
        XCTAssertTrue(openedCookingReview, app.debugDescription)
        let own = any(app, "inventory_cook_reservation_00000000-0000-0000-0000-000000000201")
        reveal(own, app: app)
        XCTAssertTrue(own.label.contains("this batch 400 g"), own.label)
        XCTAssertTrue(own.label.contains("other plans 600 g"), own.label)
        let reallocation = app.switches["I reviewed using stock planned for other meals"]
        reveal(reallocation, app: app)
        XCTAssertEqual(nativeSwitch(reallocation).value as? String, "0", "Using other meals' reservations must require explicit acknowledgement")
        capture(app, "Reservations - own batch counted once in cooking review")
        let picker = app.buttons["inventory_cook_lot_0"]
        reveal(picker, app: app); picker.tap()
        let lot = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'dry rice'")).firstMatch
        XCTAssertTrue(lot.waitForExistence(timeout: 5)); lot.tap()
        let review = app.buttons["inventory_cook_review"]
        reveal(review, app: app); review.tap()
        XCTAssertTrue(any(app, "inventory_review_list").waitForExistence(timeout: 10), app.debugDescription)
        let deduction = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '→ 600 g'")).firstMatch
        reveal(deduction, app: app); XCTAssertTrue(deduction.exists, "Own 400 g reservation must not be deducted twice")
        capture(app, "Reservations - reviewed physical deduction uses own allocation once")
        let discard = app.buttons["Discard this review"]
        reveal(discard, app: app); discard.tap()
        XCTAssertTrue(cook.waitForExistence(timeout: 10), "Discarding an unsubmitted review must not cook the batch")
    }
    @MainActor private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func nativeSwitch(_ element: XCUIElement) -> XCUIElement {
        element.descendants(matching: .switch).allElementsBoundByIndex.last ?? element
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for index in 0..<28 {
            let scroll = foregroundScroller(app)
            let pinned = ["inventory_cook_review", "meal_prep_start_timer"]
            if element.exists, pinned.contains(element.identifier), element.isHittable, app.frame.contains(element.frame) { return }
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)?.frame.maxY ?? app.frame.minY
            let top = max(scroll?.frame.minY ?? app.frame.minY, navigationBottom) + 4
            var bottom = min(scroll?.frame.maxY ?? app.frame.maxY, app.frame.maxY) - 4
            // ScrollView AX bounds include safe-area insets. Its vertical indicator
            // describes the actual scrollable viewport above the pinned cooking timer.
            let indicators = scroll?.descendants(matching: .other).matching(NSPredicate(format: "label BEGINSWITH 'Vertical scroll bar'"))
                .allElementsBoundByIndex.filter { $0.frame.height > 30 && $0.frame.width <= 35 && $0.frame.minY >= top - 5 } ?? []
            if let indicatorBottom = indicators.map(\.frame.maxY).min() { bottom = min(bottom, indicatorBottom - 3) }
            for id in ["inventory_review_footer", "inventory_cook_footer", "meal_prep_active_timer"] {
                let footer = any(app, id)
                if footer.exists, footer.isHittable, footer.frame.minY > top { bottom = min(bottom, footer.frame.minY - 4) }
            }
            if scroll?.identifier == "meal_prep_scroll" {
                let timer = app.buttons["meal_prep_start_timer"]
                if timer.exists, timer.isHittable { bottom = min(bottom, timer.frame.minY - 12) }
            }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 4) }
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            guard bottom - top > 45 else { break }
            let above = element.exists && element.frame.height > 0 ? element.frame.minY < top : index > 18
            let distance = min(CGFloat(130), (bottom - top) * 0.4)
            let middle = (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.75, dy: middle))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: above ? distance : -distance)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        diagnostics(app, "Reservations - target outside owned scroll viewport")
        let name = element.exists ? element.identifier : "unresolved reservation control"
        XCTFail("Could not reveal \(name). \(app.debugDescription)")
    }
    @MainActor private func foregroundScroller(_ app: XCUIApplication) -> XCUIElement? {
        for id in ["inventory_review_list", "inventory_cook_form", "inventory_reservations_screen", "meal_prep_scroll"] {
            let root = any(app, id)
            guard root.exists else { continue }
            if [.scrollView, .collectionView, .table].contains(root.elementType), root.isHittable { return root }
            let candidates = (root.collectionViews.allElementsBoundByIndex + root.scrollViews.allElementsBoundByIndex
                + root.tables.allElementsBoundByIndex).filter(\.isHittable)
            if let visible = candidates.last { return visible }
        }
        return app.collectionViews.allElementsBoundByIndex.last(where: \.isHittable)
            ?? app.scrollViews.allElementsBoundByIndex.last(where: \.isHittable)
    }
    @MainActor private func diagnostics(_ app: XCUIApplication, _ name: String) {
        capture(app, name)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + " - hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
