import MyFitPlateCore
import SwiftUI
import UIKit
import XCTest
@testable import MyFitPlate

@MainActor
final class TrainingFuelPlannerRenderingTests: XCTestCase {
    func testPlannerSheetRendersAtStandardAndAccessibilitySizes() throws {
        let now = date(hour: 10)
        let candidate = TrainingFuelSessionCandidate(
            id: "strength:test",
            source: .activeStrengthProgram,
            sourceID: "program",
            title: "Lower Power",
            detail: "Power Split - Week 2, Day 1",
            kind: .strength,
            scheduledDay: now,
            suggestedDurationMinutes: 65,
            suggestedIntensity: .hard,
            suggestedStrengthFocus: .lowerBody,
            assumptions: [.durationEstimated, .intensityEstimated, .focusEstimated, .sessionTimeRequired]
        )
        let candidates = [
            candidate,
            TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
            TrainingFuelSessionAdapter.runCandidate(from: RunWorkoutPlan.builtinTemplates(metric: false)[2]),
            TrainingFuelSessionAdapter.manualCandidate(kind: .run)
        ]
        let goals = TodayFuelPlanGoals(calories: 2_300, protein: 175, carbs: 270, fats: 75)
        let log = DailyLog(
            date: now,
            meals: [
                Meal(name: "Breakfast", foodItems: [
                    FoodItem(name: "Breakfast", calories: 520, protein: 30, carbs: 62, fats: 16)
                ])
            ]
        )

        let sheet = TrainingFuelPlannerSheet(
            candidates: candidates,
            savedPlan: nil,
            savedProgress: nil,
            today: log,
            goals: goals,
            now: now,
            onConfirm: { _, _ in },
            onUseTarget: { _, _, _, _ in },
            onUseSavedTarget: { _, _ in },
            onRemove: {}
        )

        try render(
            AnyView(sheet.environment(\.sizeCategory, .large)),
            frame: CGRect(x: 0, y: 0, width: 430, height: 932),
            attachmentName: "Training fuel planner - standard"
        )
        try render(
            AnyView(sheet.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 568),
            attachmentName: "Training fuel planner - accessibility"
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

    private func date(hour: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: Date()
        )!
    }
}
