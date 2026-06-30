import XCTest
import SwiftUI
@testable import MyFitPlateCore

@MainActor
final class ToastManagerTests: XCTestCase {
    
    func testToastDataInit() {
        let data = ToastData(message: "Hello")
        XCTAssertEqual(data.message, "Hello")
    }
    
    func testToastManager() {
        let manager = ToastManager()
        XCTAssertNil(manager.toast)
        
        manager.showToast(message: "Test")
        XCTAssertEqual(manager.toast?.message, "Test")
    }
    
    func testToastViewBody() {
        let view = ToastView(message: "Test")
        XCTAssertNotNil(view.body)
    }
    
    func testToastModifierBody() {
        let manager = ToastManager()
        manager.showToast(message: "Shown Toast")
        var modifier = ToastModifier()
        modifier.manager = manager
        let view = EmptyView().modifier(modifier)
        XCTAssertNotNil(view)
        
        let extView = EmptyView().withGlobalToast()
        XCTAssertNotNil(extView)
    }
}
