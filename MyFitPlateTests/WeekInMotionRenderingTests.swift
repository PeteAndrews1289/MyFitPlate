import MyFitPlateCore
import SwiftUI
import UIKit
import XCTest
@testable import MyFitPlate

@MainActor
final class WeekInMotionRenderingTests: XCTestCase {
    func testWeekInMotionRendersStandardAndAccessibilitySequences() throws {
        let recap = makeRecap()

        try render(
            AnyView(
                ScrollView(.vertical, showsIndicators: true) {
                    WeekInMotionView(recap: recap)
                        .padding(18)
                }
                .background(Color(UIColor.systemBackground))
                .environment(\.sizeCategory, .large)
            ),
            frame: CGRect(x: 0, y: 0, width: 430, height: 1_100),
            attachmentName: "Week in Motion - standard"
        )

        try render(
            AnyView(
                ScrollView(.vertical, showsIndicators: true) {
                    WeekInMotionView(recap: recap)
                        .padding(18)
                }
                .background(Color(UIColor.systemBackground))
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 1_900),
            attachmentName: "Week in Motion - accessibility"
        )

        try render(
            AnyView(
                ScrollView(.vertical, showsIndicators: true) {
                    WeekInMotionView(recap: recap)
                        .padding(18)
                }
                .background(Color(UIColor.systemBackground))
                .preferredColorScheme(.dark)
                .environment(\.sizeCategory, .large)
            ),
            frame: CGRect(x: 0, y: 0, width: 430, height: 1_100),
            attachmentName: "Week in Motion - dark"
        )

        try render(
            AnyView(
                WeeklyRecapShareCard(
                    recap: recap,
                    weekRangeText: "Jul 6 - Jul 12",
                    useMetric: false
                )
            ),
            frame: CGRect(x: 0, y: 0, width: 360, height: 500),
            attachmentName: "Week in Motion - share all selected"
        )

        try render(
            AnyView(
                WeeklyRecapShareCard(
                    recap: recap,
                    weekRangeText: "Jul 6 - Jul 12",
                    useMetric: false,
                    selection: [.rhythm, .observation]
                )
            ),
            frame: CGRect(x: 0, y: 0, width: 360, height: 500),
            attachmentName: "Week in Motion - share selected sections"
        )
    }

    private func makeRecap() -> WeeklyRecap {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        func day(_ daysAgo: Int, hour: Int = 12) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)!
                .addingTimeInterval(Double(hour * 60 * 60))
        }

        func food(
            id: String,
            name: String,
            calories: Double,
            protein: Double,
            carbs: Double,
            timestamp: Date,
            metadata: FoodSourceMetadata? = .database(.usda, sourceName: "USDA", sourceID: nil)
        ) -> FoodItem {
            FoodItem(
                id: id,
                name: name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fats: 60,
                fiber: 24,
                servingSize: "1 day",
                timestamp: timestamp,
                sourceMetadata: metadata
            )
        }

        let runStart = day(3, hour: 7)
        let run = Run(
            id: "week-motion-run",
            source: .recorded,
            startDate: runStart,
            endDate: runStart.addingTimeInterval(48 * 60),
            distanceMeters: 10_000,
            movingSeconds: 48 * 60,
            activeCalories: 700
        )
        let recovery = food(
            id: "recovery",
            name: "Recovery meal",
            calories: 2_100,
            protein: 160,
            carbs: 260,
            timestamp: run.endDate.addingTimeInterval(15 * 60)
        )
        let needsReview = food(
            id: "review",
            name: "Estimated meal",
            calories: 2_050,
            protein: 155,
            carbs: 245,
            timestamp: day(1, hour: 13),
            metadata: .aiEstimate(.aiText, sourceName: "Maia estimate")
        )
        let logs = [
            DailyLog(date: day(5), meals: [Meal(name: "Meals", foodItems: [
                food(id: "day-one", name: "Meals", calories: 2_080, protein: 165, carbs: 230, timestamp: day(5))
            ])]),
            DailyLog(date: day(3), meals: [Meal(name: "Recovery", foodItems: [recovery])]),
            DailyLog(date: day(1), meals: [Meal(name: "Meals", foodItems: [needsReview])]),
            DailyLog(date: day(0), meals: [Meal(name: "Meals", foodItems: [
                food(id: "today", name: "Meals", calories: 2_100, protein: 170, carbs: 240, timestamp: day(0))
            ])])
        ]

        func strengthSession(
            daysAgo: Int,
            exercise: String,
            setCount: Int = 4
        ) -> WorkoutSessionLog {
            let routineExercise = RoutineExercise(name: exercise, type: .strength, sets: [])
            let sets = (0..<setCount).map { _ in
                CompletedSet(reps: 8, weight: 135, distance: 0, durationInSeconds: 0)
            }
            return WorkoutSessionLog(
                date: day(daysAgo, hour: 17),
                routineID: "week-motion-strength",
                completedExercises: [
                    CompletedExercise(
                        exerciseName: exercise,
                        exercise: routineExercise,
                        sets: sets
                    )
                ]
            )
        }

        return WeeklyRecapBuilder.build(
            weekEnding: now,
            calendar: calendar,
            dailyLogs: logs,
            sessionLogs: [
                strengthSession(daysAgo: 5, exercise: "Bench Press", setCount: 8),
                strengthSession(daysAgo: 1, exercise: "Squat")
            ],
            priorSessionLogs: [],
            weightHistory: [],
            runs: [run],
            calorieGoal: 2_100,
            proteinGoal: 160,
            bodyWeightLbs: 181
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
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 12_000)

        let attachment = XCTAttachment(image: image)
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
