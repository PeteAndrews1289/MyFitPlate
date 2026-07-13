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

    func testVisualSystemTokensRemainFiniteAndOrdered() {
        XCTAssertEqual(AppTextRole.allCases.count, 8)
        XCTAssertGreaterThan(AppTextRole.display.pointSize, AppTextRole.screenTitle.pointSize)
        XCTAssertGreaterThan(AppTextRole.screenTitle.pointSize, AppTextRole.sectionTitle.pointSize)
        XCTAssertGreaterThan(AppSpacing.section, AppSpacing.group)
        XCTAssertGreaterThan(AppRadius.hero, AppRadius.surface)
        XCTAssertGreaterThan(AppRadius.surface, AppRadius.control)
    }

    func testVisualSystemComponentsCanBeConstructed() {
        let text = Text("Test").appTextRole(.body)
        let surface = EmptyView().appSurface(.quiet)
        let primary = Button("Continue") {}.buttonStyle(AppActionButtonStyle(.primary))
        let secondary = Button("Later") {}.buttonStyle(AppActionButtonStyle(.secondary))
        let icon = Button {} label: { Image(systemName: "xmark") }
            .buttonStyle(AppIconButtonStyle())
        let header = AppScreenHeader(title: "Living Day", subtitle: "Current")
        let section = AppSectionHeader(title: "Your day")
        let row = AppListRow(icon: "magnifyingglass", title: "Search food", subtitle: "Find from the food database")
        let sheet = AppSheetScaffold(title: "Quick Log", dismiss: {}) { EmptyView() }

        XCTAssertNotNil(text)
        XCTAssertNotNil(surface)
        XCTAssertNotNil(primary)
        XCTAssertNotNil(secondary)
        XCTAssertNotNil(icon)
        XCTAssertNotNil(header.body)
        XCTAssertNotNil(section.body)
        XCTAssertNotNil(row.body)
        XCTAssertNotNil(sheet.body)
    }
}
