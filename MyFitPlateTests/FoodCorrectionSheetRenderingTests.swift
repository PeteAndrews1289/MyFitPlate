import MyFitPlateCore
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

    func testTrustReceiptRendersCrossVerifiedEvidence() throws {
        var metadata = FoodSourceMetadata.database(
            .usda,
            sourceName: "USDA FoodData Central",
            sourceID: "usda_2346398"
        )
        metadata.crossVerifiedBy = ["Open Food Facts"]
        let item = FoodItem(
            id: "usda_2346398",
            name: "Plain Greek yogurt",
            calories: 120,
            protein: 20,
            carbs: 8,
            fats: 1,
            saturatedFat: 0.5,
            servingSize: "1 cup (227 g)",
            servingWeight: 227,
            sourceMetadata: metadata
        )
        let descriptor = FoodSourceClassifier.descriptor(
            for: "usda",
            foodID: item.id,
            metadata: metadata
        )
        let receipt = FoodTrustReceipt(
            descriptor: descriptor,
            evaluation: FoodTrustEvaluation.evaluate(
                item: item,
                descriptor: descriptor,
                metadata: metadata
            ),
            metadata: metadata,
            findings: FoodDataSanity.findings(for: item),
            isSavingCorrection: false,
            resolution: nil,
            onAction: nil
        )

        try renderReceipt(
            receipt.environment(\.sizeCategory, .large),
            frame: CGRect(x: 0, y: 0, width: 430, height: 760),
            attachmentName: "Trust Receipt - cross-verified"
        )
    }

    func testTrustReceiptRendersNutritionWarningAtAccessibilitySize() throws {
        let metadata = FoodSourceMetadata(
            sourceType: .custom,
            confidence: .userVerified,
            reviewStatus: .userConfirmed,
            sourceName: "My Foods",
            barcode: "0044000087579"
        )
        let item = FoodItem(
            id: "saved-cinnamon-cookie",
            name: "Cinnamon bun flavored",
            calories: 150,
            protein: 0,
            carbs: 21,
            fats: 7,
            saturatedFat: 10,
            fiber: 1,
            servingSize: "2 cookies (29 g)",
            servingWeight: 29,
            sourceMetadata: metadata
        )
        let descriptor = FoodSourceClassifier.descriptor(
            for: "custom_barcode",
            foodID: item.id,
            metadata: metadata
        )
        let receipt = FoodTrustReceipt(
            descriptor: descriptor,
            evaluation: FoodTrustEvaluation.evaluate(
                item: item,
                descriptor: descriptor,
                metadata: metadata
            ),
            metadata: metadata,
            findings: FoodDataSanity.findings(for: item),
            isSavingCorrection: false,
            resolution: nil,
            onAction: {}
        )

        try renderReceipt(
            receipt.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            frame: CGRect(x: 0, y: 0, width: 320, height: 1_200),
            attachmentName: "Trust Receipt - warning accessibility"
        )
    }

    func testTrustReceiptRendersPersistedCorrectionResolution() throws {
        let metadata = FoodSourceMetadata(
            sourceType: .custom,
            confidence: .userVerified,
            reviewStatus: .userEdited,
            sourceName: "My Foods",
            barcode: "0044000087579"
        )
        let item = FoodItem(
            id: "corrected-cinnamon-cookie",
            name: "Cinnamon bun flavored",
            calories: 150,
            protein: 2,
            carbs: 21,
            fats: 7,
            saturatedFat: 3,
            fiber: 1,
            servingSize: "2 cookies (29 g)",
            servingWeight: 29,
            sourceMetadata: metadata
        )
        let descriptor = FoodSourceClassifier.descriptor(
            for: "custom_barcode",
            foodID: item.id,
            metadata: metadata
        )
        let receipt = FoodTrustReceipt(
            descriptor: descriptor,
            evaluation: FoodTrustEvaluation.evaluate(
                item: item,
                descriptor: descriptor,
                metadata: metadata
            ),
            metadata: metadata,
            findings: FoodDataSanity.findings(for: item),
            isSavingCorrection: false,
            resolution: FoodTrustResolution(
                title: "Correction saved",
                detail: "Future scans will use this reviewed entry"
            ),
            onAction: nil
        )

        try renderReceipt(
            receipt.environment(\.sizeCategory, .large),
            frame: CGRect(x: 0, y: 0, width: 430, height: 820),
            attachmentName: "Trust Receipt - persisted correction"
        )
    }

    private func renderReceipt<Content: View>(
        _ receipt: Content,
        frame: CGRect,
        attachmentName: String
    ) throws {
        let rootView = VStack(spacing: 0) {
            receipt
                .padding(.horizontal, 20)
                .padding(.top, 24)
            Spacer(minLength: 0)
        }
        .frame(width: frame.width, height: frame.height, alignment: .top)
        .background(Color(uiColor: .systemBackground))

        let controller = UIHostingController(rootView: rootView)
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
}
