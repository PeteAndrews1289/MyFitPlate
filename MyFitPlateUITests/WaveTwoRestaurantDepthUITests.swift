import XCTest

/// Synthetic-account journeys only; the runner selects an isolated QA simulator.
final class WaveTwoRestaurantDepthUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ screen: String, reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen]
        if reset { app.launchArguments += ["-ui-testing-reset-ayce", "-ui-testing-reset-editor-drafts"] }
        app.launch(); return app
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let buffet = app.otherElements["ayce_live_screen"].scrollViews.firstMatch
        let scroll = buffet.exists ? buffet : app.scrollViews.allElementsBoundByIndex
            .max { $0.frame.intersection(app.frame).height < $1.frame.intersection(app.frame).height } ?? app.scrollViews.firstMatch
        for _ in 0..<18 {
            let search = app.textFields["ayce_catalog_search"]
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.map { $0.frame.maxY }.max() ?? app.frame.minY + 80
            let top = max(scroll.frame.minY + 8, search.exists ? search.frame.maxY + 12 : navigationBottom + 8)
            let buffetFooter = app.buttons["ayce_end_button"]
            let chainFooter = app.buttons["chain_builder_review_meal"]
            let footerTop = buffetFooter.exists ? buffetFooter.frame.minY : chainFooter.exists ? chainFooter.frame.minY : app.frame.maxY - 70
            let bottom = min(scroll.frame.maxY - 8, footerTop - 12)
            guard bottom > top + 60 else { break }
            var offset: CGFloat = -100
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                if frame.minY < top { offset = top - frame.minY + 12 } else if frame.maxY > bottom { offset = bottom - frame.maxY - 12 }
            }
            // Short, bounded drags avoid repeatedly flinging a nearby row from
            // below the footer to behind the pinned search controls and back.
            let distance = (offset < 0 ? -1.0 : 1.0) * min(max(abs(offset), 40), 140)
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: min(scroll.frame.maxX - 12, app.frame.width * 0.9), dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        record(app, "Unrevealed restaurant control - \(element.identifier)")
        XCTFail("Could not reveal \(element.identifier). \(app.debugDescription)")
    }
    @MainActor private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testUnknownPriceStartsNutritionMealAndStableRoundSurvivesRelaunch() {
        var app = launch("ayce-start")
        XCTAssertTrue(app.buttons["ayce_start_button"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["ayce_start_button"].isEnabled, "Blank optional price must permit a nutrition meal")
        app.buttons["ayce_start_button"].tap()
        let search = app.textFields["ayce_catalog_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10)); search.tap(); search.typeText("rainbow\n")
        let add = app.buttons["ayce_add_sushi_rainbow_roll"]
        reveal(add, app: app); XCTAssertTrue(add.exists); add.tap()
        app.buttons["Clear buffet search"].tap()
        let finish = app.buttons["ayce_finish_round"]; reveal(finish, app: app); finish.tap()
        let options = app.buttons["ayce_session_options"]; reveal(options, app: app); options.tap()
        let history = app.buttons["ayce_round_history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
        XCTAssertTrue(app.otherElements["ayce_round_history_screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 food ·'")).firstMatch.exists)
        record(app, "Buffet stable round before recovery")
        // The start-only screenshot fixture explicitly disables restoring a draft.
        // Recovery uses the same restored-session route as the existing buffet suite.
        app.terminate(); app = launch("ayce-resume", reset: false)
        XCTAssertTrue(app.textFields["ayce_catalog_search"].waitForExistence(timeout: 10))
        let recoveredOptions = app.buttons["ayce_session_options"]; reveal(recoveredOptions, app: app); recoveredOptions.tap()
        let recovered = app.buttons["ayce_round_history"]
        XCTAssertTrue(recovered.waitForExistence(timeout: 5)); recovered.tap()
        XCTAssertTrue(app.otherElements["ayce_round_history_screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 food ·'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Undo only this change"].firstMatch.exists)
        record(app, "Buffet stable rounds and durable changes after recovery")
    }
    @MainActor func testSavedChainTemplateKeepsComponentReviewAvailableAfterRelaunch() {
        var app = launch("builder")
        let save = app.buttons["chain_builder_save_order"]; reveal(save, app: app)
        XCTAssertTrue(save.waitForExistence(timeout: 8)); save.tap()
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved orders ('")).firstMatch
        reveal(saved, app: app); saved.tap()
        XCTAssertTrue(app.navigationBars["Saved orders"].waitForExistence(timeout: 8))
        record(app, "Saved restaurant template retains frozen components")
        app.terminate(); app = launch("builder", reset: false)
        let reopened = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved orders ('")).firstMatch
        reveal(reopened, app: app); XCTAssertTrue(reopened.label.contains("1")); reopened.tap()
        let template = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chipotle order'")).firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 8)); template.tap()
        XCTAssertTrue(app.navigationBars["Review saved order"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Use saved nutrition and portions"].exists)
        record(app, "Restaurant template reopen requires explicit source choice")
    }
}
