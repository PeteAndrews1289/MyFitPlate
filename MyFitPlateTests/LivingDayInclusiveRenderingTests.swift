import MyFitPlateCore
import SwiftUI
import UIKit
import XCTest
@testable import MyFitPlate

@MainActor
final class LivingDayInclusiveRenderingTests: XCTestCase {
    func testLivingDayQualityMatrixRendersWithoutBlankOrClippedSurfaces() throws {
        try renderLivingDay(
            snapshot: makeSnapshot(.ordinary),
            density: .compact,
            sizeCategory: .large,
            frame: CGRect(x: 0, y: 0, width: 430, height: 932),
            attachmentName: "Living Day matrix - ordinary"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.empty),
            density: .compact,
            sizeCategory: .large,
            frame: CGRect(x: 0, y: 0, width: 320, height: 568),
            attachmentName: "Living Day matrix - empty compact"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.training),
            density: .detailed,
            sizeCategory: .large,
            colorScheme: .dark,
            frame: CGRect(x: 0, y: 0, width: 430, height: 1_100),
            attachmentName: "Living Day matrix - training dark"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.recovery),
            density: .detailed,
            sizeCategory: .large,
            frame: CGRect(x: 0, y: 0, width: 430, height: 1_000),
            attachmentName: "Living Day matrix - recovery"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.overTarget),
            density: .compact,
            sizeCategory: .large,
            contrast: .high,
            frame: CGRect(x: 0, y: 0, width: 320, height: 760),
            attachmentName: "Living Day matrix - over target contrast"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.lowTrust),
            density: .detailed,
            sizeCategory: .large,
            frame: CGRect(x: 0, y: 0, width: 430, height: 1_000),
            attachmentName: "Living Day matrix - low Trust"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.offline),
            density: .compact,
            sizeCategory: .large,
            frame: CGRect(x: 0, y: 0, width: 320, height: 760),
            attachmentName: "Living Day matrix - offline stale"
        )
        try renderLivingDay(
            snapshot: makeSnapshot(.ordinary),
            density: .detailed,
            sizeCategory: .accessibilityExtraExtraExtraLarge,
            frame: CGRect(x: 0, y: 0, width: 320, height: 1_700),
            attachmentName: "Living Day matrix - accessibility detailed"
        )
    }

    func testLivingDayShareCardsRenderStandardAndExplicitSelections() throws {
        let snapshot = makeSnapshot(.lowTrust)
        let allSections = LivingDayShareBuilder.make(
            from: snapshot,
            selection: [.budget, .path, .trust, .action]
        )
        let pathAndAction = LivingDayShareBuilder.make(
            from: snapshot,
            selection: [.path, .action]
        )

        try render(
            AnyView(LivingDayShareCard(snapshot: allSections)),
            frame: CGRect(x: 0, y: 0, width: 360, height: 500),
            attachmentName: "Living Day share - all selected"
        )
        try render(
            AnyView(LivingDayShareCard(snapshot: pathAndAction)),
            frame: CGRect(x: 0, y: 0, width: 360, height: 500),
            attachmentName: "Living Day share - path and action"
        )
    }

    func testFixedSharePreviewFitsCompactSheetWidth() throws {
        let snapshot = LivingDayShareBuilder.make(
            from: makeSnapshot(.ordinary),
            selection: [.budget, .path, .action]
        )
        let content = VStack {
            FixedShareCardPreview {
                LivingDayShareCard(snapshot: snapshot)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 320, height: 450, alignment: .top)
        .background(Color(UIColor.systemBackground))

        try render(
            AnyView(content),
            frame: CGRect(x: 0, y: 0, width: 320, height: 450),
            attachmentName: "Living Day share preview - compact sheet"
        )
    }

    private func renderLivingDay(
        snapshot: LivingDaySnapshot,
        density: LivingDayPathDensity,
        sizeCategory: ContentSizeCategory,
        colorScheme: ColorScheme = .light,
        contrast: UIAccessibilityContrast = .normal,
        frame: CGRect,
        attachmentName: String
    ) throws {
        let content = ScrollView(.vertical, showsIndicators: true) {
            LivingDayHomeExperience(
                snapshot: snapshot,
                transition: nil,
                hydration: LivingDayHydrationState(consumed: 72, target: 96),
                density: density,
                onEventSelected: { _ in },
                onActionSelected: { _ in }
            )
            .padding(18)
        }
        .background(Color(UIColor.systemBackground))
        .environment(\.sizeCategory, sizeCategory)
        .environment(\.colorScheme, colorScheme)

        try render(
            AnyView(content),
            frame: frame,
            attachmentName: attachmentName,
            traits: UITraitCollection(accessibilityContrast: contrast)
        )
    }

    private func render(
        _ view: AnyView,
        frame: CGRect,
        attachmentName: String,
        traits: UITraitCollection? = nil
    ) throws {
        let controller = UIHostingController(rootView: view)
        let container = UIViewController()
        let window = UIWindow(frame: frame)
        container.addChild(controller)
        container.view.addSubview(controller.view)
        controller.didMove(toParent: container)
        if let traits {
            controller.traitOverrides.accessibilityContrast = traits.accessibilityContrast
        }
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.frame = frame
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
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

    private enum Fixture {
        case ordinary
        case empty
        case training
        case recovery
        case overTarget
        case lowTrust
        case offline
    }

    private func makeSnapshot(_ fixture: Fixture) -> LivingDaySnapshot {
        let events: [LivingDaySnapshot.Event]
        let budget: LivingDaySnapshot.Budget
        let trainingWindow: LivingDaySnapshot.TrainingWindow?
        let action: DailyNextAction
        let freshness: LivingDaySnapshot.Freshness

        switch fixture {
        case .ordinary:
            events = ordinaryEvents
            budget = makeBudget(consumed: (1_090, 82, 118, 35), planned: (640, 46, 58, 24))
            trainingWindow = nil
            action = makeAction(.proteinCatchUp, title: "Close your protein gap", detail: "37 g protein left today")
            freshness = .current(updatedAt: date(hour: 14, minute: 28))
        case .empty:
            events = []
            budget = makeBudget(consumed: (0, 0, 0, 0), planned: (0, 0, 0, 0))
            trainingWindow = nil
            action = makeAction(.proteinCatchUp, title: "Build your first meal", detail: "Start with a meal you know")
            freshness = .current(updatedAt: date(hour: 8))
        case .training:
            events = ordinaryEvents + [
                event(
                    id: "strength",
                    kind: .strength,
                    state: .planned,
                    title: "Lower body",
                    detail: "60 min, hard session",
                    hour: 17,
                    minute: 30,
                    evidence: .notApplicable,
                    destination: .trainingFuel
                )
            ]
            budget = makeBudget(consumed: (1_090, 82, 118, 35), planned: (0, 0, 0, 0))
            trainingWindow = .init(
                planID: "fixture-plan",
                title: "Lower body",
                sessionStart: date(hour: 17, minute: 30),
                sessionEnd: date(hour: 18, minute: 30),
                windowStart: date(hour: 16),
                windowEnd: date(hour: 20, minute: 30),
                status: .upcoming
            )
            action = DailyNextAction(
                kind: .preWorkoutFuel,
                title: "Fuel before training",
                detail: "22 g protein + 42 g carbs",
                deepLink: "myfitplate://training-fuel",
                proteinGrams: 22,
                carbGrams: 42
            )
            freshness = .current(updatedAt: date(hour: 14, minute: 28))
        case .recovery:
            events = ordinaryEvents + [
                event(
                    id: "run",
                    kind: .run,
                    state: .completed,
                    title: "Tempo run",
                    detail: "5.2 mi, 47 min",
                    hour: 17,
                    evidence: .notApplicable,
                    destination: .runs
                ),
                event(
                    id: "recovery",
                    kind: .recovery,
                    state: .active,
                    title: "Recovery window",
                    detail: "Open for 38 more minutes",
                    hour: 18,
                    evidence: .notApplicable,
                    destination: .trainingFuel
                )
            ]
            budget = makeBudget(consumed: (1_350, 96, 152, 42), planned: (0, 0, 0, 0))
            trainingWindow = .init(
                planID: "fixture-recovery",
                title: "Tempo run",
                sessionStart: date(hour: 17),
                sessionEnd: date(hour: 17, minute: 47),
                windowStart: date(hour: 15, minute: 30),
                windowEnd: date(hour: 19, minute: 30),
                status: .recovery
            )
            action = DailyNextAction(
                kind: .recoveryMeal,
                title: "Log recovery fuel",
                detail: "28 g protein + 48 g carbs",
                deepLink: "myfitplate://training-fuel",
                proteinGrams: 28,
                carbGrams: 48
            )
            freshness = .current(updatedAt: date(hour: 18, minute: 6))
        case .overTarget:
            events = ordinaryEvents
            budget = makeBudget(consumed: (2_370, 182, 276, 84), planned: (0, 0, 0, 0))
            trainingWindow = nil
            action = makeAction(.steadyDay, title: "Stay steady today", detail: "Keep logging as you go")
            freshness = .current(updatedAt: date(hour: 20, minute: 12))
        case .lowTrust:
            events = [
                event(
                    id: "review-meal",
                    kind: .meal,
                    state: .completed,
                    title: "Lunch",
                    detail: "560 cal, nutrition needs review",
                    hour: 12,
                    minute: 20,
                    evidence: .correction,
                    destination: .diary(mealID: "review-meal")
                )
            ] + Array(ordinaryEvents.dropFirst())
            budget = makeBudget(consumed: (1_150, 75, 132, 43), planned: (0, 0, 0, 0))
            trainingWindow = nil
            action = makeAction(.trustReview, title: "Review food data", detail: "1 entry needs your review")
            freshness = .current(updatedAt: date(hour: 14, minute: 28))
        case .offline:
            events = ordinaryEvents
            budget = makeUnavailableBudget()
            trainingWindow = nil
            action = makeAction(.steadyDay, title: "Stay steady today", detail: "Some totals are temporarily unavailable")
            freshness = .stale(lastUpdated: date(hour: 9, minute: 15))
        }

        return LivingDaySnapshot(
            date: date(hour: 0),
            generatedAt: date(hour: 14, minute: 30),
            pathWindow: .init(start: date(hour: 6), end: date(hour: 22)),
            budget: budget,
            events: events,
            trainingWindow: trainingWindow,
            nextAction: action,
            freshness: freshness,
            currentTime: date(hour: 14, minute: 30)
        )
    }

    private var ordinaryEvents: [LivingDaySnapshot.Event] {
        [
            event(
                id: "breakfast",
                kind: .meal,
                state: .completed,
                title: "Breakfast",
                detail: "510 cal, cross-checked",
                hour: 8,
                evidence: .excellent,
                destination: .diary(mealID: "breakfast")
            ),
            event(
                id: "lunch",
                kind: .meal,
                state: .completed,
                title: "Lunch",
                detail: "580 cal, database supported",
                hour: 12,
                minute: 20,
                evidence: .supported,
                destination: .diary(mealID: "lunch")
            ),
            event(
                id: "dinner",
                kind: .plannedMeal,
                state: .planned,
                title: "Dinner",
                detail: "640 cal planned",
                hour: 19,
                timing: .approximate,
                evidence: .supported,
                destination: .mealPlan
            )
        ]
    }

    private func event(
        id: String,
        kind: LivingDaySnapshot.EventKind,
        state: LivingDaySnapshot.EventState,
        title: String,
        detail: String,
        hour: Int,
        minute: Int = 0,
        timing: LivingDaySnapshot.TimingConfidence = .exact,
        evidence: LivingDaySnapshot.Evidence,
        destination: LivingDaySnapshot.Destination
    ) -> LivingDaySnapshot.Event {
        LivingDaySnapshot.Event(
            id: id,
            kind: kind,
            state: state,
            title: title,
            detail: detail,
            startDate: date(hour: hour, minute: minute),
            timing: timing,
            evidence: evidence,
            destination: destination
        )
    }

    private func makeAction(
        _ kind: DailyNextAction.Kind,
        title: String,
        detail: String
    ) -> DailyNextAction {
        DailyNextAction(
            kind: kind,
            title: title,
            detail: detail,
            deepLink: "myfitplate://home"
        )
    }

    private func makeBudget(
        consumed: (Double, Double, Double, Double),
        planned: (Double, Double, Double, Double)
    ) -> LivingDaySnapshot.Budget {
        LivingDaySnapshot.Budget(
            calories: .init(kind: .calories, consumed: consumed.0, planned: planned.0, target: 2_200),
            protein: .init(kind: .protein, consumed: consumed.1, planned: planned.1, target: 165),
            carbs: .init(kind: .carbs, consumed: consumed.2, planned: planned.2, target: 245),
            fats: .init(kind: .fats, consumed: consumed.3, planned: planned.3, target: 70)
        )
    }

    private func makeUnavailableBudget() -> LivingDaySnapshot.Budget {
        LivingDaySnapshot.Budget(
            calories: .init(kind: .calories, consumed: nil, planned: nil, target: nil),
            protein: .init(kind: .protein, consumed: nil, planned: nil, target: nil),
            carbs: .init(kind: .carbs, consumed: nil, planned: nil, target: nil),
            fats: .init(kind: .fats, consumed: nil, planned: nil, target: nil)
        )
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: hour,
            minute: minute
        ))!
    }
}
