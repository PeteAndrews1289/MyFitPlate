import XCTest

extension XCUIElement {
    /// Selects the contents through the iPhone editing menu even when the simulator
    /// has no connected hardware keyboard to deliver Command-A.
    @MainActor
    func replaceContents(with text: String, in app: XCUIApplication,
                         file: StaticString = #filePath, line: UInt = #line) {
        tap()
        if let current = value as? String, !current.isEmpty, current != placeholderValue {
            press(forDuration: 1)
            let selectAll = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
            if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            } else {
                tap(withNumberOfTaps: 3, numberOfTouches: 1)
            }
        }
        typeText(text)
        assertTextValue(text, within: app, file: file, line: line)
    }

    @MainActor
    func assertTextValue(_ expected: String, within screen: XCUIElement,
                         file: StaticString = #filePath, line: UInt = #line) {
        let updated = screen.textFields.matching(NSPredicate(format: "identifier == %@ AND value == %@", identifier, expected)).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 8), "Expected \(identifier) to show \(expected).", file: file, line: line)
    }
}
