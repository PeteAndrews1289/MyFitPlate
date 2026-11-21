import XCTest

/// Synthetic simulator journeys only. Reset flags clear the screenshot account's
/// draft, never an owner account. Native repository tests establish server durability;
/// the screenshot mock reseeds its program library on each process launch.
final class WaveTwoTrainingClosureUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testReviewedPHULSkipCanCancelThenUndoWithoutCreatingAWorkout() {
        let app = launch("program-detail", flags: ["-ui-testing-wave2-phul"])
        assertPosition(39, app: app)
        XCTAssertTrue(app.staticTexts["Includes 3 explicitly skipped sessions"].exists)

        openSkipReview(app)
        let review = any(app, "workout_skip_review")
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let affected = review.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Session 40:", "will skip")).firstMatch
        XCTAssertTrue(affected.exists, "The consequence review identifies the exact next PHUL slot before changing progress")
        app.buttons["Keep current plan"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        assertPosition(39, app: app)
        XCTAssertFalse(app.buttons["program_undo_skip"].exists)

        openSkipReview(app)
        let confirm = app.buttons["workout_skip_confirm"]
        open(confirm, app: app)
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        assertPosition(40, app: app)
        XCTAssertTrue(app.staticTexts["Includes 4 explicitly skipped sessions"].exists)
        let undo = app.buttons["program_undo_skip"]
        open(undo, app: app)
        assertPosition(39, app: app)
        XCTAssertTrue(undo.waitForNonExistence(timeout: 5), "The one accepted skip is consumed by Undo, not applied twice")
        XCTAssertTrue(app.staticTexts["Includes 3 explicitly skipped sessions"].exists)
        record(app, "PHUL - reviewed skip undone with original progress and skips")

        app.terminate()
        _ = launch("program-detail", flags: ["-ui-testing-wave2-phul"], resets: false, app: app)
        assertPosition(39, app: app)
        XCTAssertFalse(app.buttons["program_undo_skip"].exists)
        XCTAssertFalse(app.buttons["workout_resume"].exists, "Browsing and skipping do not create a workout draft")
        record(app, "PHUL - clean restored baseline after skip and Undo")
    }

    @MainActor
    func testMeasuredHoldPausesRecoversAndCompletesOnceWithoutLoggingOtherSets() {
        let app = launch("workout-player", flags: ["-ui-testing-wave2-interval"])
        let strength = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "set_complete_")).firstMatch
        XCTAssertTrue(strength.waitForExistence(timeout: 10))
        let strengthID = strength.identifier
        XCTAssertEqual(strength.value as? String, "Not completed")
        open(app.buttons["Add Exercise"], app: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Plank")
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.exists, searchKey.isHittable { searchKey.tap() }
        let plank = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Plank")).firstMatch
        open(plank, app: app)
        XCTAssertTrue(search.waitForNonExistence(timeout: 5))

        let player = any(app, "workout_player")
        let addedMovement = player.staticTexts["Plank"].firstMatch
        reveal(addedMovement, app: app)
        XCTAssertTrue(addedMovement.exists, "The selected movement must be present in the active workout before testing its timer")
        let start = player.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "interval_start_")).firstMatch
        reveal(start, app: app)
        let setID = start.identifier.replacingOccurrences(of: "interval_start_", with: "")
        start.tap()
        let controls = any(app, "interval_controls_" + setID)
        let pause = app.buttons["interval_pause_" + setID]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(pause.frame.height, 44)
        let running = controls.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[1-9][0-9]* active seconds, running$")).firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 8), "The hold measures real elapsed work before completion")
        open(pause, app: app)
        let paused = controls.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "active seconds, paused")).firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 5))
        let elapsed = activeSeconds(paused)
        XCTAssertGreaterThan(elapsed, 0)
        record(app, "Mixed workout - measured hold paused before recovery")

        app.terminate()
        _ = launch("train", resets: false, app: app)
        open(app.buttons["workout_resume"], app: app)
        let resume = app.buttons["interval_start_" + setID]
        reveal(resume, app: app)
        XCTAssertEqual(resume.label, "Resume")
        XCTAssertTrue(paused.waitForExistence(timeout: 5))
        XCTAssertEqual(activeSeconds(paused), elapsed, "A paused hold does not accrue time during termination or relaunch")
        open(resume, app: app)
        let laterLabels = ((elapsed + 1)...(elapsed + 20)).map { "\($0) active seconds, running" }
        let advanced = controls.staticTexts.matching(NSPredicate(format: "label IN %@", laterLabels)).firstMatch
        XCTAssertTrue(advanced.waitForExistence(timeout: 8))
        open(app.buttons["interval_complete_" + setID], app: app)
        let completed = controls.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "active seconds, completed")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5), "A completed hold must be labeled completed, not paused")
        let measured = activeSeconds(completed)
        XCTAssertGreaterThan(measured, elapsed)
        let loggedSeconds = player.textFields["Duration in seconds, set 1"]
        XCTAssertTrue(loggedSeconds.exists)
        XCTAssertEqual(Int(loggedSeconds.value as? String ?? ""), measured, "The completed clock and saved duration must use the same rounding")
        XCTAssertFalse(app.buttons["interval_start_" + setID].exists)
        XCTAssertFalse(app.buttons["interval_complete_" + setID].exists, "An accepted timer cannot complete the same set again")
        record(app, "Mixed workout - recovered hold completed once")
        reveal(app.buttons[strengthID], app: app)
        XCTAssertEqual(app.buttons[strengthID].value as? String, "Not completed", "Completing the hold never logs an unrelated strength set")

        app.terminate()
        _ = launch("train", resets: false, app: app)
        open(app.buttons["workout_resume"], app: app)
        reveal(controls, app: app)
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertEqual(activeSeconds(completed), measured)
        XCTAssertEqual(Int(loggedSeconds.value as? String ?? ""), measured)
        XCTAssertFalse(app.buttons["interval_complete_" + setID].exists)
        record(app, "Mixed workout - completed hold remains exact after second recovery")
        reveal(app.buttons[strengthID], app: app)
        XCTAssertEqual(app.buttons[strengthID].value as? String, "Not completed")
    }

    @MainActor
    private func launch(_ screen: String, flags: [String] = [], resets: Bool = true,
                        app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-ui-testing", "-screenshot-mode", "-screenshot-screen", screen] + flags
            + (resets ? ["-ui-testing-reset-workout-draft", "-ui-testing-reset-equipment", "-ui-testing-reset-editor-drafts"] : [])
        app.launch()
        let root = screen == "train" ? app.buttons["workout_resume"]
            : any(app, screen == "program-detail" ? "program_detail" : "workout_player")
        if !root.waitForExistence(timeout: 10), app.buttons["welcome_get_started"].exists,
           app.buttons["welcome_sign_in"].exists { app.terminate(); app.launch() }
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func openSkipReview(_ app: XCUIApplication) {
        let detail = any(app, "program_detail")
        open(detail.buttons["workout_slot_options"], app: app)
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5)); skip.tap()
        XCTAssertTrue(app.buttons["workout_skip_confirm"].waitForExistence(timeout: 5))
    }
    @MainActor private func assertPosition(_ position: Int, app: XCUIApplication) {
        let progress = any(app, "program_progress_summary")
        reveal(progress, app: app)
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "\(position) of 48"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 10), .completed)
    }
    @MainActor private func activeSeconds(_ label: XCUIElement) -> Int {
        Int(label.label.split(separator: " ").first.map(String.init) ?? "") ?? -1
    }
    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
    @MainActor private func open(_ element: XCUIElement, app: XCUIApplication) {
        reveal(element, app: app); element.tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for step in 0..<20 {
            if element.exists, element.isHittable, app.frame.contains(element.frame) { return }
            let player = any(app, "workout_player")
            let detail = any(app, "program_detail")
            let picker = app.navigationBars["Add Exercise"]
            let root = picker.exists && picker.isHittable ? nil : player.exists ? player : detail.exists ? detail : nil
            let scroller = verticalSurface(root: root, app: app)
            let nav = app.navigationBars.allElementsBoundByIndex.last(where: \.isHittable)
            let top = max(scroller?.frame.minY ?? app.frame.minY + 90, nav?.frame.maxY ?? app.frame.minY + 90) + 4
            var bottom = min(scroller?.frame.maxY ?? app.frame.maxY - 80, app.frame.maxY - 80) - 4
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 5) }
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            guard bottom - top > 50 else { break }
            let targetFrame = element.exists ? element.frame : .zero
            let known = element.exists && targetFrame.height > 0
            let above = known ? targetFrame.minY < top : step > 15
            let needed = known ? (above ? top - targetFrame.minY : targetFrame.maxY - bottom) + 8 : 100
            let distance = min(CGFloat(140), max(CGFloat(40), needed))
            let middle = top + (bottom - top) * 0.5
            let end = min(bottom - 6, max(top + 6, middle + (above ? distance : -distance)))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: app.frame.midX, dy: middle))
                .press(forDuration: 0.03, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: end)))
        }
        let target = element.exists ? element.identifier : "unresolved target"
        if !element.exists || !element.isHittable { record(app, "Training UI - unreachable " + target) }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reach \(target)\n\(app.debugDescription)")
    }
    @MainActor private func verticalSurface(root: XCUIElement?, app: XCUIApplication) -> XCUIElement? {
        let scope: XCUIElement = root ?? app
        var candidates = scope.scrollViews.allElementsBoundByIndex
            + scope.collectionViews.allElementsBoundByIndex + scope.tables.allElementsBoundByIndex
        // Descendant queries omit the root, which is itself the vertical surface
        // on program detail and some SwiftUI accessibility configurations.
        if let root, [.scrollView, .collectionView, .table].contains(root.elementType) { candidates.append(root) }
        func visibleFrame(_ element: XCUIElement) -> CGRect { element.frame.intersection(app.frame) }
        return candidates.filter { element in
            guard element.exists, element.isHittable else { return false }
            let visible = visibleFrame(element)
            return !visible.isNull && !visible.isEmpty && visible.height >= 100 && visible.width >= app.frame.width * 0.6
        }.max { first, second in
            let firstFrame = visibleFrame(first), secondFrame = visibleFrame(second)
            if firstFrame.height != secondFrame.height { return firstFrame.height < secondFrame.height }
            return firstFrame.width * firstFrame.height < secondFrame.width * secondFrame.height
        }
    }
    @MainActor private func record(_ app: XCUIApplication, _ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
