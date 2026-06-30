import XCTest
import SwiftUI
@testable import MyFitPlateCore

@MainActor
final class DesignSystemTests: XCTestCase {
    
    func testAppFontModifier() {
        let modifier = AppFont(size: 16, weight: .regular)
        let view = EmptyView().modifier(modifier)
        XCTAssertNotNil(view)
        
        let extensionView = EmptyView().appFont(size: 16)
        XCTAssertNotNil(extensionView)
    }
    
    func testPrimaryButtonStyle() {
        let view = Button("Test") { }.buttonStyle(PrimaryButtonStyle())
        XCTAssertNotNil(view)
    }
    
    func testSecondaryButtonStyle() {
        let view = Button("Test") { }.buttonStyle(SecondaryButtonStyle())
        XCTAssertNotNil(view)
    }
    
    func testAnimatedCardButtonStyle() {
        let view = Button("Test") { }.buttonStyle(AnimatedCardButtonStyle())
        XCTAssertNotNil(view)
    }
    
    func testAppTextFieldStyle() {
        let view = TextField("Test", text: .constant("")).textFieldStyle(AppTextFieldStyle())
        XCTAssertNotNil(view)
    }
    
    func testGlassCardModifier() {
        let modifier = GlassCardModifier()
        let view = EmptyView().modifier(modifier)
        XCTAssertNotNil(view)
        
        let extView = EmptyView().glassCard()
        XCTAssertNotNil(extView)
    }
    
    func testGuidanceEmptyState() {
        let view = GuidanceEmptyState(icon: "star", title: "Test", message: "Test message")
        XCTAssertNotNil(view.body)
    }
    
    func testSkeletonBlocks() {
        let modifier = SkeletonModifier()
        let view = EmptyView().modifier(modifier)
        XCTAssertNotNil(view)
        
        let shimmer = ShimmerEffect()
        let shimmerView = EmptyView().modifier(shimmer)
        XCTAssertNotNil(shimmerView)
        
        let block = SkeletonBlock(width: 100, height: 50, cornerRadius: 10)
        XCTAssertNotNil(block.body)
    }
}
