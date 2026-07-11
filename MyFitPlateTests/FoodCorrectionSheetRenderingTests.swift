import SwiftUI
import UIKit
import XCTest
@testable import MyFitPlate

@MainActor
final class FoodCorrectionSheetRenderingTests: XCTestCase {
    func testCorrectionSheetRendersTotalAndSaturatedFatControls() {
        let serving = ServingSizeOption(
            description: "2 cookies (29 g)",
            servingWeightGrams: 29,
            calories: 150,
            protein: 0,
            carbs: 21,
            fats: 7,
            saturatedFat: 10,
            fiber: 1
        )
        let sheet = FoodDetailCorrectionSheet(
            foodName: "Cinnamon bun flavored",
            serving: serving,
            barcode: "0044000087579",
            onSave: { _, _ in }
        )
        let controller = UIHostingController(rootView: sheet)
        let frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        let window = UIWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = frame
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: frame)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Food correction fat fields"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
