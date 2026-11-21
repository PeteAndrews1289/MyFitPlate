import XCTest
@testable import MyFitPlateCore

@MainActor
final class AppToolCatalogTests: XCTestCase {
    func testEveryDeliveredToolHasUniqueIdentityAndUsableTypedDestination() {
        let tools = AppToolCatalog.tools
        XCTAssertEqual(Set(tools.map(\.id)).count, tools.count)
        XCTAssertEqual(Set(tools.map(\.route)).count, tools.count)
        XCTAssertFalse(tools.contains { [.community, .unavailable].contains($0.route) })
        XCTAssertTrue(tools.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.systemImage.isEmpty })
        XCTAssertEqual(AppToolCategory.allCases.flatMap(AppToolCatalog.tools(in:)), tools)
        for tool in tools {
            let coordinator = AppCoordinator()
            coordinator.navigate(to: tool.route)
            XCTAssertEqual(coordinator.takePendingRequest()?.route, tool.route)
            XCTAssertNil(coordinator.pendingRoute)
        }
    }

    func testCatalogLinksAndLegacyAliasesQueueExactDestinations() throws {
        let pairs: [(String, Route)] = [("tools", .tools), ("food-preferences", .foodPreferences), ("recipes", .recipes),
            ("pantry", .pantry), ("groceries", .grocery), ("sushi", .buffet), ("kbbq", .buffet),
            ("plate-math", .plateCalculator), ("rescue-my-week", .weekRescue), ("what-works-for-me", .mealExperiments),
            ("meal-plan", .nutrition), ("train", .workouts), ("trust-score", .trust), ("recovery-fuel", .trainingFuel)]
        let coordinator = AppCoordinator()
        for (alias, route) in pairs {
            XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://\(alias)"))), route)
            XCTAssertEqual(coordinator.takePendingRequest()?.route, route)
        }
    }

    func testRecipeObjectRequiresOwningAccountAndExistingObject() throws {
        let coordinator = AppCoordinator()
        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://recipes/saved-recipe?user=owner")))
        let request = try XCTUnwrap(coordinator.takePendingRequest())
        XCTAssertEqual(request.objectID, "saved-recipe")
        XCTAssertEqual(request.resolvedRoute(currentUserID: "owner", availableRecipeIDs: ["saved-recipe"]), .recipes)
        XCTAssertEqual(request.resolvedRoute(currentUserID: "other", availableRecipeIDs: ["saved-recipe"]), .unavailable)
        XCTAssertEqual(request.resolvedRoute(currentUserID: "owner", availableRecipeIDs: []), .unavailable)
        XCTAssertEqual(request.resolvedRoute(currentUserID: nil, availableRecipeIDs: ["saved-recipe"]), .unavailable)
    }

    func testCivilDayLinksAreValidatedAndUnknownObjectsOrCommandsNeverBecomeActions() throws {
        let coordinator = AppCoordinator()
        coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://diary?day=2026-10-28&owner=owner")))
        let day = try XCTUnwrap(coordinator.takePendingRequest())
        XCTAssertEqual(day.route, .home); XCTAssertEqual(day.dayKey, "2026-10-28")
        XCTAssertEqual(day.resolvedRoute(currentUserID: "other"), .unavailable)
        let context = try XCTUnwrap(day.diaryDayContext(for: "owner", timeZone: XCTUnwrap(TimeZone(identifier: "America/New_York"))))
        XCTAssertEqual(DiaryDayContext.dayKey(for: context.originalDate, timeZone: context.timeZone), "2026-10-28")
        XCTAssertNil(day.diaryDayContext(for: "other"))
        for invalid in ["home?day=2026-02-30", "home?day=2026-1-2", "home?day=2026-10-28&day=2026-10-29",
                        "recipes/one/two", "recipes/one?id=two", "recipes/one%2Ftwo", "recipes?owner=",
                        "runs/unknown", "food-search?action=log", "week-rescue?save=true", "community"] {
            XCTAssertEqual(coordinator.handle(url: try XCTUnwrap(URL(string: "myfitplate://\(invalid)"))), .unavailable, invalid)
            XCTAssertEqual(coordinator.takePendingRequest()?.route, .unavailable)
        }
    }

    func testQueuedRequestIsStableUntilTakenAndNewRequestReplacesItWithoutExecuting() throws {
        let coordinator = AppCoordinator()
        coordinator.navigate(to: .foodPreferences)
        let first = try XCTUnwrap(coordinator.pendingRequest)
        XCTAssertEqual(coordinator.pendingRequest, first)
        coordinator.navigate(to: .recipes)
        XCTAssertNotEqual(coordinator.pendingRequest?.id, first.id)
        XCTAssertEqual(coordinator.currentRoute, .recipes)
        XCTAssertEqual(coordinator.takePendingRequest()?.route, .recipes)
        XCTAssertNil(coordinator.pendingRequest)
    }
}
