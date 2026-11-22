import XCTest
@testable import MyFitPlateCore

@MainActor final class CookingSessionWorkspaceTests: XCTestCase {
    private let user = "w2-cooking-guidance-owner"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func activate() { let auth = MockAuthService(); auth.currentUserID = user; DIContainer.shared.authService = auth }
    private func session() -> MealCookingCheckpointSession {
        activate()
        return MealCookingCheckpointSession(userID: user, contextID: UUID().uuidString,
            store: EditorDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    private func requirements() -> [MealCookingRequirement] {
        [.init(id: "one", date: now, name: "Rice", ingredients: [.init(quantity: 100, unit: "g", name: "rice", originalString: "100 g rice")], instructions: "Wash rice\nCook rice\nCool rice"),
         .init(id: "two", date: now, name: "Sauce", ingredients: [.init(quantity: 1, unit: "item", name: "salt", originalString: "salt to taste")], instructions: "Mix sauce")]
    }
    func testStepTimeSuggestionsRequireOneExplicitSupportedDuration() {
        for (text, expected) in [("Bake at 400°F for 12 minutes.", 12...12), ("Simmer 10–15 min.", 10...15),
                                  ("Chill for 10 to 15 minutes.", 10...15), ("Cook 10 minutes to 15 minutes.", 10...15)] {
            XCTAssertEqual(MealPrepTimerRules.instructionMinutes(text), expected)
        }
        for text in ["Cook until golden", "Stir every 2 min", "Cook 4 minutes per side", "Rest 1.5 minutes",
                     "Heat 1 hour 30 minutes", "Cook 3 minutes, rest 2 minutes", "Boil 125 min",
                     "Grill 15–10 minutes", "Heat for 1/2 minute", "Stir for 3 minutes and 15 seconds"] {
            XCTAssertNil(MealPrepTimerRules.instructionMinutes(text), text)
        }
    }

    func testGuidedDependencyChecksAndUncheckingCascadesWithinRecipeOnly() {
        let session = session(), steps = CookingSessionRules.steps(requirements: requirements())
        XCTAssertFalse(session.toggleGuidedStep(1, steps: steps))
        XCTAssertTrue(session.toggleGuidedStep(0, steps: steps)); XCTAssertTrue(session.toggleGuidedStep(1, steps: steps))
        XCTAssertTrue(session.toggleGuidedStep(2, steps: steps)); XCTAssertTrue(session.toggleGuidedStep(3, steps: steps))
        XCTAssertTrue(session.toggleGuidedStep(0, steps: steps))
        XCTAssertEqual(session.checkpoint.completedStepIndexes, [3])
        XCTAssertEqual(steps[1].prerequisites, ["one-step-0"])
    }
    func testGuidedAdvanceRestoresCheckedStepAndNextUnfinishedSelectedStepTogether() {
        activate()
        let store = EditorDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let context = UUID().uuidString
        let steps = CookingSessionRules.steps(requirements: requirements())
        let first = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
        XCTAssertTrue(first.toggleGuidedStep(3, steps: steps, advanceWhenComplete: true))
        let session = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
        XCTAssertTrue(session.restored)
        XCTAssertEqual(session.checkpoint.completedStepIndexes, [3])
        XCTAssertEqual(session.checkpoint.currentStepID, steps[0].id)
        XCTAssertTrue(session.selectRequirements(["one"], available: ["one", "two"]))
        for index in 0...2 {
            XCTAssertTrue(session.toggleGuidedStep(index, steps: steps, advanceWhenComplete: true))
        }
        XCTAssertEqual(session.checkpoint.currentStepID, steps[2].id)
        XCTAssertTrue(session.toggleGuidedStep(1, steps: steps, advanceWhenComplete: true))
        XCTAssertEqual(session.checkpoint.currentStepID, steps[1].id)
        XCTAssertEqual(session.checkpoint.completedStepIndexes, [0, 3])
        XCTAssertTrue(session.toggleGuidedStep(3, steps: steps))
        XCTAssertTrue(session.toggleGuidedStep(1, steps: steps, advanceWhenComplete: true))
        XCTAssertTrue(session.toggleGuidedStep(2, steps: steps, advanceWhenComplete: true))
        XCTAssertEqual(session.checkpoint.currentStepID, steps[2].id)
    }

    func testPrepSelectionExportsOnlyChosenSourcesAndPreservesUnknownAmount() throws {
        let values = requirements()
        let text = CookingSessionRules.checklist(requirements: values, selected: ["two"])
        XCTAssertFalse(text.contains("Wash rice")); XCTAssertTrue(text.contains("amount unconfirmed"))
        let data = try CookingSessionRules.structuredChecklist(requirements: values, selected: ["two"])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        let items = try XCTUnwrap(rows[0]["ingredients"] as? [[String: Any]])
        XCTAssertNil(items[0]["amount"])
    }
    func testLinkedTimerAdjustmentPreservesExactDeadlineAndIndependentPausedState() throws {
        let session = session()
        XCTAssertTrue(session.addNamedTimer(name: "Rice", minutes: 10, stepID: "one-step-1", now: now))
        XCTAssertTrue(session.addNamedTimer(name: "Sauce", minutes: 5, now: now))
        let rice = try XCTUnwrap(session.checkpoint.additionalTimers?.first)
        XCTAssertTrue(session.adjustNamedTimer(id: rice.id, seconds: 60, now: now.addingTimeInterval(17)))
        XCTAssertEqual(session.checkpoint.additionalTimers?[0].deadline, now.addingTimeInterval(660))
        XCTAssertEqual(session.checkpoint.additionalTimers?[0].stepID, "one-step-1")
        XCTAssertTrue(session.changeNamedTimer(id: rice.id, now: now.addingTimeInterval(20)))
        XCTAssertEqual(session.checkpoint.additionalTimers?[0].pausedRemaining, 640)
        XCTAssertEqual(session.checkpoint.additionalTimers?[1].deadline, now.addingTimeInterval(300))
    }
    func testNotificationProjectionUsesStableIDsAndDropsPausedCancelledExpiredTimers() {
        let running = CookingTimerInspection(id: "one", contextID: "session", name: "Rice", deadline: now.addingTimeInterval(60), pausedRemaining: 0, finished: false)
        var paused = running; paused.id = "paused"; paused.deadline = nil; paused.pausedRemaining = 30
        var expired = running; expired.id = "expired"; expired.deadline = now.addingTimeInterval(-1)
        let requests = CookingNotificationRules.requests(userID: user, timers: [running, paused, expired], now: now)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests, CookingNotificationRules.requests(userID: user, timers: [running], now: now))
        XCTAssertNotEqual(requests[0].id, CookingNotificationRules.requests(userID: "another", timers: [running], now: now)[0].id)
        XCTAssertTrue(CookingNotificationRules.requests(userID: user, timers: [running], now: now.addingTimeInterval(61)).isEmpty)
    }
    func testDeliveredAlertResolvesOnlyItsAccountAndKeepsTheOriginalInstruction() throws {
        let cooking = session()
        let instruction = "Cover the rice and simmer for 12 minutes."
        XCTAssertTrue(cooking.addNamedTimer(name: "Rice", minutes: 12, stepID: "rice-step-1", instruction: instruction, now: now))
        XCTAssertTrue(cooking.addNamedTimer(name: "Rice", minutes: 3, stepID: "rice-step-2", instruction: "Rest for 3 minutes.", now: now))
        let timers = try CookingTimerRegistry.shared.checkedTimers(userID: user).filter { $0.contextID == cooking.contextID }
        let request = try XCTUnwrap(CookingNotificationRules.requests(userID: user, timers: timers, now: now).last)
        let coordinator = AppCoordinator()
        coordinator.navigate(to: .workouts)
        coordinator.handleCookingNotification(identifier: "meal-reminder")
        coordinator.handleCookingNotification(identifier: CookingNotificationRules.identifierPrefix + "invalid")
        XCTAssertEqual(coordinator.pendingRoute, .workouts)
        coordinator.handleCookingNotification(identifier: request.id)
        let link = try XCTUnwrap(coordinator.takePendingRequest())
        XCTAssertEqual(link.route, .cookingTimer)
        XCTAssertEqual(link.route.selectedTab, Route.nutrition.selectedTab)
        let target = try XCTUnwrap(link.objectID)
        let timer = try XCTUnwrap(CookingNotificationRules.timer(for: target, userID: user, in: timers))
        XCTAssertEqual(timer.stepID, "rice-step-1")
        XCTAssertEqual(timer.instruction, instruction)
        XCTAssertNil(CookingNotificationRules.timer(for: target, userID: "another-account", in: timers))
        XCTAssertNil(CookingNotificationRules.timer(for: target, userID: user, in: timers.filter { $0.id != timer.id }))
        XCTAssertNil(coordinator.takePendingRequest())
    }
    func testEarlierCookingTimersDecodeWithoutAnInstructionAndRetainTheirIdentity() throws {
        let cooking = session()
        XCTAssertTrue(cooking.addNamedTimer(name: "Rice", minutes: 5, stepID: "rice-step", now: now))
        let original = try XCTUnwrap(cooking.checkpoint.additionalTimers?.first)
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["instruction"])
        let restored = try JSONDecoder().decode(NamedCookingTimer.self, from: data)
        XCTAssertNil(restored.instruction)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.stepID, original.stepID)
        XCTAssertEqual(restored.deadline, original.deadline)
    }
    func testStaleCookingViewCannotOverwriteTimerChangedOutsideCook() throws {
        activate()
        let store = EditorDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = MealCookingCheckpointSession(userID: user, contextID: "same", store: store)
        XCTAssertTrue(first.startTimer(minutes: 10, now: now))
        let other = MealCookingCheckpointSession(userID: user, contextID: "same", store: store)
        XCTAssertTrue(other.pauseTimer(now: now.addingTimeInterval(10)))
        XCTAssertFalse(first.selectStep("one"))
        XCTAssertNil(first.checkpoint.timerEndDate)
        XCTAssertEqual(first.checkpoint.pausedTimerRemaining, 590)
        XCTAssertTrue(first.selectStep("one"))
    }
    func testPrimaryTimerAdjustmentDoesNotRoundSecondsAndReloadKeepsSelection() {
        let session = session()
        XCTAssertTrue(session.startTimer(minutes: 1, now: now))
        XCTAssertTrue(session.adjustTimer(seconds: 60, now: now.addingTimeInterval(17)))
        XCTAssertEqual(session.checkpoint.timerEndDate, now.addingTimeInterval(120))
        XCTAssertTrue(session.selectRequirements(["two"], available: ["one", "two"]))
        XCTAssertEqual(session.checkpoint.selectedRequirementIDs, ["two"])
        XCTAssertFalse(session.selectRequirements(["unseen"], available: ["one", "two"]))
    }
    func testCorruptRegistryIsPreservedAndIdenticalUpdatesDoNotRepublish() throws {
        activate()
        let suite = "cooking-index-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let registry = CookingTimerRegistry(defaults: defaults)
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cooking-timer-index", userID: user))
        let bytes = Data("unreadable index".utf8); defaults.set(bytes, forKey: key)
        var checkpoint = MealCookingCheckpoint(); checkpoint.timerEndDate = now.addingTimeInterval(100)
        registry.update(userID: user, contextID: "one", checkpoint: checkpoint)
        XCTAssertEqual(defaults.data(forKey: key), bytes); XCTAssertNotNil(registry.errorMessage)
        XCTAssertThrowsError(try registry.checkedTimers(userID: user))
        defaults.removeObject(forKey: key)
        registry.update(userID: user, contextID: "one", checkpoint: checkpoint)
        let revision = registry.revision
        registry.update(userID: user, contextID: "one", checkpoint: checkpoint)
        XCTAssertEqual(registry.revision, revision)
    }
    func testNotificationLimitDoesNotDiscardUnderlyingTimerIdentities() {
        let timers = (0..<60).map { index in CookingTimerInspection(id: "\(index)", contextID: "many", name: "Timer \(index)",
            deadline: now.addingTimeInterval(Double(index+1)), pausedRemaining: 0, finished: false) }
        let requests = CookingNotificationRules.requests(userID: user, timers: timers, now: now)
        XCTAssertEqual(requests.count, 48)
        XCTAssertEqual(Set(timers.map { CookingNotificationRules.identifier(userID: user, timer: $0) }).count, 60)
        XCTAssertEqual(requests.first?.deadline, now.addingTimeInterval(1))
    }

    private func repeatedMealDays() -> [MealPlanDay] {
        let start = Calendar.current.startOfDay(for: now)
        return (0..<2).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            return MealPlanDay(id: MealPlanEditingRules.dayID(date), date: date,
                meals: [.init(id: "rice-\(offset)", mealType: "Dinner", ingredients: ["100 g rice"],
                              instructions: "Wash rice\nCook rice")])
        }
    }

    func testIndependentIdenticalMealsKeepSelectionChecksAndExportOnTheirOwnDates() throws {
        activate()
        let days = repeatedMealDays(), prep = MealPrepService()
        let requirements = MealPlanCookingRules.requirements(from: days)
        prep.aggregate(days: days, selectedRequirementIDs: ["rice-1"])
        XCTAssertEqual(prep.structuredSteps.count, 4)
        XCTAssertEqual(prep.bulkIngredients.values.flatMap { $0 }.first?.quantity, 100)
        XCTAssertEqual(CookingSessionRules.selectedStepIndexes(steps: prep.structuredSteps, selected: ["rice-1"]), [2, 3])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let context = MealCookingCheckpointSession.contextID(days: days)
        let first = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
        XCTAssertTrue(first.reconcileStepLayout(steps: prep.structuredSteps,
            legacyStepIDs: CookingSessionRules.legacyStepIDs(requirements: requirements)))
        XCTAssertTrue(first.selectRequirements(["rice-1"], available: ["rice-0", "rice-1"]))
        XCTAssertTrue(first.toggleGuidedStep(2, steps: prep.structuredSteps))
        XCTAssertTrue(first.toggleGuidedStep(3, steps: prep.structuredSteps))
        XCTAssertEqual(first.checkpoint.completedStepIndexes, [2, 3])
        let completed = Set(first.checkpoint.completedStepIndexes.map { prep.structuredSteps[$0].id })
        let selectedExport = CookingSessionRules.checklist(requirements: requirements, selected: ["rice-1"], completed: completed)
        let otherExport = CookingSessionRules.checklist(requirements: requirements, selected: ["rice-0"], completed: completed)
        XCTAssertEqual(selectedExport.components(separatedBy: "☑").count - 1, 2)
        XCTAssertFalse(otherExport.contains("☑"))
        let restored = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
        XCTAssertEqual(restored.checkpoint.completedStepIndexes, [2, 3])
        XCTAssertEqual(restored.checkpoint.selectedRequirementIDs, ["rice-1"])
        XCTAssertEqual(restored.checkpoint.stepIDs, prep.structuredSteps.map(\.id))
    }

    func testLegacyChecksMoveByOriginalStepIdentityWithoutCompletingIdenticalMeals() throws {
        activate()
        var days = repeatedMealDays()
        days[1].meals.append(.init(id: "sauce", mealType: "Sauce", ingredients: ["10 g oil"], instructions: "Mix sauce"))
        let requirements = MealPlanCookingRules.requirements(from: days)
        let prep = MealPrepService(); prep.aggregate(days: days)
        let legacyIDs = CookingSessionRules.legacyStepIDs(requirements: requirements)
        XCTAssertEqual(legacyIDs, ["rice-0-step-0", "rice-0-step-1", "sauce-step-0"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory), context = MealCookingCheckpointSession.contextID(days: days)
        var original = MealCookingCheckpoint()
        original.completedStepIndexes = [0, 1, 2]; original.currentStepID = "sauce-step-0"
        original.selectedRequirementIDs = ["rice-1", "sauce"]
        original.timerEndDate = now.addingTimeInterval(300)
        original.additionalTimers = [.init(name: "Rice", minutes: 10, now: now)]
        try store.save(original, userID: user, scope: "meal-cooking-\(context)")
        let session = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
        XCTAssertTrue(session.reconcileStepLayout(steps: prep.structuredSteps, legacyStepIDs: legacyIDs))
        XCTAssertEqual(session.checkpoint.completedStepIndexes, [0, 1, 4])
        XCTAssertEqual(session.checkpoint.legacyCompletedStepIndexes, [0, 1, 2])
        XCTAssertEqual(session.checkpoint.currentStepID, original.currentStepID)
        XCTAssertEqual(session.checkpoint.selectedRequirementIDs, original.selectedRequirementIDs)
        XCTAssertEqual(session.checkpoint.timerEndDate, original.timerEndDate)
        XCTAssertEqual(session.checkpoint.additionalTimers?.first?.id, original.additionalTimers?.first?.id)
        let saved = try XCTUnwrap(store.load(MealCookingCheckpoint.self, userID: user, scope: "meal-cooking-\(context)"))
        XCTAssertTrue(session.reconcileStepLayout(steps: prep.structuredSteps, legacyStepIDs: legacyIDs))
        XCTAssertEqual(try store.load(MealCookingCheckpoint.self, userID: user, scope: "meal-cooking-\(context)")?.updatedAt, saved.updatedAt,
            "An unchanged step layout must not rewrite its checkpoint")
        let restored = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
        XCTAssertEqual(restored.checkpoint.completedStepIndexes, [0, 1, 4])
        XCTAssertEqual(restored.checkpoint.legacyCompletedStepIndexes, [0, 1, 2])
    }

    func testUnmatchedOrCorruptLegacyCheckpointsStayUnmodified() throws {
        activate()
        let steps = CookingSessionRules.steps(requirements: requirements())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        for (context, ids, indexes) in [("unmatched", nil as [String]?, Set([99])),
                                        ("corrupt", ["duplicate", "duplicate"], Set([0]))] {
            var original = MealCookingCheckpoint(); original.stepIDs = ids
            original.completedStepIndexes = indexes; original.timerEndDate = now.addingTimeInterval(300)
            try store.save(original, userID: user, scope: "meal-cooking-\(context)")
            let before = try XCTUnwrap(store.load(MealCookingCheckpoint.self, userID: user, scope: "meal-cooking-\(context)"))
            let session = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
            XCTAssertFalse(session.reconcileStepLayout(steps: steps, legacyStepIDs: steps.map(\.id)))
            XCTAssertNotNil(session.errorMessage)
            let after = try XCTUnwrap(store.load(MealCookingCheckpoint.self, userID: user, scope: "meal-cooking-\(context)"))
            XCTAssertEqual(try PlanFingerprint.make(before), try PlanFingerprint.make(after))
        }
    }

    func testInvalidExternalRefreshKeepsPublishedProgressAndOriginalBytes() throws {
        activate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 0..<5 {
            let folder = directory.appendingPathComponent("case-\(index)")
            let store = EditorDraftStore(directory: folder), context = "refresh-\(index)"
            let session = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
            XCTAssertTrue(session.startTimer(minutes: 5, now: now))
            let valid = try PlanFingerprint.make(session.checkpoint)
            var invalid = session.checkpoint
            switch index {
            case 0: invalid.completedStepIndexes = [-1]
            case 1: invalid.lastTimerMinutes = 0
            case 2:
                let timer = NamedCookingTimer(name: "Rice", minutes: 1, now: now)
                invalid.additionalTimers = [timer, timer]
            case 3: invalid.additionalTimers = [.init(name: "", minutes: 1, now: now)]
            default: invalid.additionalTimers = [.init(name: "  \n", minutes: 1, now: now)]
            }
            try store.save(invalid, userID: user, scope: "meal-cooking-\(context)")
            let files = try FileManager.default.subpathsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
            XCTAssertEqual(files.count, 1)
            let file = folder.appendingPathComponent(try XCTUnwrap(files.first))
            let originalBytes = try Data(contentsOf: file)
            session.refreshFromDisk()
            XCTAssertNotNil(session.errorMessage)
            XCTAssertEqual(try PlanFingerprint.make(session.checkpoint), valid, "Refresh must retain the last usable progress")
            XCTAssertFalse(session.pauseTimer(now: now.addingTimeInterval(30)))
            XCTAssertEqual(try Data(contentsOf: file), originalBytes, "A later control must not overwrite invalid external evidence")
            let restored = MealCookingCheckpointSession(userID: user, contextID: context, store: store)
            XCTAssertNotNil(restored.errorMessage, "Initialization and refresh must apply the same validation")
            XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        }
    }
}
