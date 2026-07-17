import XCTest
@testable import MyFitPlateCore

final class AppRuntimeTests: XCTestCase {
    func testUITestingRequiresExplicitDebugLaunchArgument() {
        XCTAssertFalse(AppRuntime.isUITesting(arguments: ["MyFitPlate"]))
        XCTAssertTrue(AppRuntime.isUITesting(arguments: ["MyFitPlate", "-ui-testing"]))
    }
}
