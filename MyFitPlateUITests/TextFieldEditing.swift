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
        XCTAssertEqual(value as? String, text, "The input field should show the entire replacement.", file: file, line: line)
    }
}
