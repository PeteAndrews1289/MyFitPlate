import XCTest

extension XCUIElement {
    /// Replaces the whole field using its Clear control or the iPhone editing menu.
    @MainActor
    func replaceContents(with text: String, in app: XCUIApplication, using clearButton: XCUIElement? = nil,
                         file: StaticString = #filePath, line: UInt = #line) {
        if let clearButton {
            clearButton.tap()
            guard clearButton.wait(for: \.isEnabled, toEqual: false, timeout: 5) else {
                XCTFail("The input should be cleared before entering its replacement.", file: file, line: line)
                return
            }
        } else {
            tap()
            if let current = value as? String, !current.isEmpty {
                press(forDuration: 1)
                let selectAll = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label IN %@", ["Select All", "Select all"])).firstMatch
                if selectAll.waitForExistence(timeout: 2) {
                    selectAll.tap()
                } else {
                    tap(withNumberOfTaps: 3, numberOfTouches: 1)
                }
            }
        }
        typeText(text)
        assertTextValue(text, within: app, file: file, line: line)
    }

    @MainActor
    func assertTextValue(_ expected: String, within screen: XCUIElement,
                         file: StaticString = #filePath, line: UInt = #line) {
        let updated = screen.textFields.matching(NSPredicate(format: "identifier == %@ AND value == %@", identifier, expected)).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 8),
                      "Expected \(identifier) to show \(expected). Current value is \(value as? String ?? "empty").",
                      file: file, line: line)
    }
}
