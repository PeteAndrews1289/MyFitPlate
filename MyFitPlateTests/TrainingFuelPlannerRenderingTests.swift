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
            onMarkComplete: {},
            onSkip: {},
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

    func testAwaitingOutcomeRendersCompletionAndSkipActions() throws {
        let now = date(hour: 19)
        let start = date(hour: 18)
        let candidate = TrainingFuelSessionAdapter.manualCandidate(kind: .strength)
        let draft = TrainingFuelPlanDraft(
            candidate: candidate,
            scheduledAt: start,
            durationMinutes: 60,
            intensity: .hard,
            strengthFocus: .lowerBody
        )
        let plannerPlan = TrainingFuelPlannerPlan(
            status: .ready,
            normalizedDurationMinutes: 60,
            normalizedIntensity: .hard,
            minutesUntilSession: 240,
            remainingCalories: 1_200,
            remainingProteinGrams: 100,
            remainingCarbGrams: 160,
            allocations: [
                TrainingFuelAllocation(
                    phase: .beforeTraining,
                    timing: .overTwoHours,
                    proteinGrams: 10,
                    carbGrams: 30
                ),
                TrainingFuelAllocation(
                    phase: .afterTraining,
                    timing: .afterSession,
                    proteinGrams: 25,
                    carbGrams: 35
                )
            ],
            notes: []
        )
        let goals = TodayFuelPlanGoals(calories: 2_300, protein: 175, carbs: 270, fats: 75)
        let savedPlan = TrainingFuelConfirmedPlan(
            draft: draft,
            plannerPlan: plannerPlan,
            goals: goals,
            today: nil,
            confirmedAt: date(hour: 14)
        )
        let progress = TrainingFuelPlanProgressRules.makeProgress(
            plan: savedPlan,
            today: nil,
            goals: goals,
            now: now
        )
        XCTAssertEqual(progress.status, .awaitingOutcome)

        let sheet = TrainingFuelPlannerSheet(
            candidates: [candidate],
            savedPlan: savedPlan,
            savedProgress: progress,
            today: nil,
            goals: goals,
            now: now,
            onConfirm: { _, _ in },
            onUseTarget: { _, _, _, _ in },
            onUseSavedTarget: { _, _ in },
            onMarkComplete: {},
            onSkip: {},
            onRemove: {}
        )

        try render(
            AnyView(sheet.environment(\.sizeCategory, .large)),
            frame: CGRect(x: 0, y: 0, width: 430, height: 932),
            attachmentName: "Training fuel planner - awaiting outcome"
        )
    }

    func testLivingDayPersistedInsertionRendersAtStandardAndAccessibilitySizes() throws {
        let now = Date()
        let food = FoodItem(
            id: "transition-food",
            name: "Greek yogurt and berries",
            calories: 280,
            protein: 26,
            carbs: 32,
            fats: 6,
            timestamp: now.addingTimeInterval(-60)
        )
        let meal = Meal(name: "Afternoon Snack", foodItems: [food])
        let log = DailyLog(date: now, meals: [meal])
        let snapshot = LivingDaySnapshotBuilder.make(
            date: now,
            now: now,
            dailyLog: log,
            goals: TodayFuelPlanGoals(calories: 2_200, protein: 165, carbs: 240, fats: 70)
        )
        let transition = LivingDayTransition.foodLogged(food, meal: meal, createdAt: now)
        let view = LivingDayHomeExperience(
            snapshot: snapshot,
            transition: transition,
            onEventSelected: { _ in },
            onActionSelected: { _ in }
        )

        try render(
            AnyView(
                VStack(spacing: 0) {
                    view.environment(\.sizeCategory, .large)
                    Spacer(minLength: 0)
                }
            ),
            frame: CGRect(x: 0, y: 0, width: 430, height: 780),
            attachmentName: "Living Day persisted insertion - standard"
        )
        try render(
            AnyView(
                VStack(spacing: 0) {
                    view.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                    Spacer(minLength: 0)
                }
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 780),
            attachmentName: "Living Day persisted insertion - accessibility"
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
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
