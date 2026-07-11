import XCTest
@testable import MyFitPlateCore

final class MyFitPlateLinksTests: XCTestCase {
    func testAppStoreURLTargetsPublishedApp() {
        XCTAssertEqual(MyFitPlateLinks.appStoreURL.scheme, "https")
        XCTAssertEqual(MyFitPlateLinks.appStoreURL.host, "apps.apple.com")
        XCTAssertTrue(MyFitPlateLinks.appStoreURL.path.contains("id6740922831"))
    }

    func testShareMessageIncludesLeadAndStoreLink() {
        let message = MyFitPlateLinks.shareMessage("A useful result")

        XCTAssertTrue(message.hasPrefix("A useful result"))
        XCTAssertTrue(message.contains(MyFitPlateLinks.appStoreURLString))
    }
}
