import MyFitPlateCore
import SwiftUI
import UIKit
import XCTest
@testable import MyFitPlate

@MainActor
final class MyFoodsLibraryRenderingTests: XCTestCase {
    func testLibraryRendersManagementAndAccessibilityStates() throws {
        let now = Date()
        let barcodeFood = food(
            id: "barcode-food",
            name: "Cinnamon bun flavored cookies",
            fats: 7,
            saturatedFat: 10,
            barcode: "0044000087579"
        )
        let oatmeal = food(id: "oatmeal", name: "Morning oatmeal")
        let duplicate = food(id: "oatmeal-copy", name: " morning   oatmeal ")
        let recipe = food(
            id: "recipe",
            name: "Turkey chili with black beans",
            sourceType: .recipe
        )
        var recentMetadata = oatmeal.sourceMetadata
        recentMetadata?.sourceID = oatmeal.id
        let recent = FoodItem(
            id: "recent-oatmeal",
            name: oatmeal.name,
            timestamp: now.addingTimeInterval(-3_600),
            sourceMetadata: recentMetadata
        )
        let foods = [barcodeFood, oatmeal, duplicate, recipe]

        try render(
            AnyView(
                MyFoodsLibraryView(
                    initialFoods: foods,
                    recentFoods: [recent],
                    loadsRemoteData: false
                )
                .environmentObject(DailyLogService())
                .environmentObject(BannerService())
                .environment(\.sizeCategory, .large)
            ),
            frame: CGRect(x: 0, y: 0, width: 430, height: 932),
            attachmentName: "My Foods Library - standard"
        )

        try render(
            AnyView(
                MyFoodsLibraryView(
                    initialFoods: foods,
                    recentFoods: [recent],
                    loadsRemoteData: false
                )
                .environmentObject(DailyLogService())
                .environmentObject(BannerService())
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 1_000),
            attachmentName: "My Foods Library - accessibility"
        )
    }

    private func render(
        _ view: AnyView,
        frame: CGRect,
        attachmentName: String
    ) throws {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: frame)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10_000)

        let attachment = XCTAttachment(image: image)
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    private func food(
        id: String,
        name: String,
        fats: Double = 4,
        saturatedFat: Double? = 1,
        barcode: String? = nil,
        sourceType: FoodSourceType = .custom
    ) -> FoodItem {
        FoodItem(
            id: id,
            name: name,
            calories: 180,
            protein: 20,
            carbs: 16,
            fats: fats,
            saturatedFat: saturatedFat,
            fiber: 3,
            servingSize: "1 serving (100 g)",
            servingWeight: 100,
            sourceMetadata: FoodSourceMetadata(
                sourceType: sourceType,
                confidence: .userVerified,
                reviewStatus: .userConfirmed,
                sourceName: "My Foods",
                sourceID: id,
                barcode: barcode,
                matchedFoodID: id
            )
        )
    }
}
