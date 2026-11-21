import XCTest
@testable import MyFitPlateCore

@MainActor
final class GoalEditorIntegrityTests: XCTestCase {
    private var auth: MockAuthService!
    private var repo: MockSettingsRepository!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepo: SettingsRepositoryProtocol?
    private var owner = ""

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService; previousRepo = DIContainer.shared.settingsRepository
        owner = "goal-editor-\(UUID().uuidString)"
        auth = MockAuthService(); auth.currentUserID = owner; repo = MockSettingsRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.settingsRepository = repo
    }

    override func tearDown() {
        if let key = AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner) { UserDefaults.standard.removeObject(forKey: key) }
        DIContainer.shared.authService = previousAuth; DIContainer.shared.settingsRepository = previousRepo
        super.tearDown()
    }

    private func model(_ method: CalorieGoalMethod = .custom) -> GoalSettings {
        let value = GoalSettings(isEditingPreview: true)
        value.activateAccount(owner)
        value.calorieGoalMethod = method; value.calories = 2_100; value.waterGoal = 93
        value.weightHistory = [("history", Date(timeIntervalSince1970: 1_700_000_000), 170)]
        value.suggestionCuisines = ["Italian"]
        return value
    }

    func testEditingAndDiscardingIndependentPreviewDoesNotChangeLiveGoalsOrWrite() {
        let live = model(.dynamicTDEE)
        let before = live.makeGoalEditorDraft()
        let preview = GoalSettings(isEditingPreview: true)
        preview.applyGoalEditorPreview(before)
        preview.age = 41; preview.goal = "Lose"; preview.proteinPercentage = 65
        preview.calorieGoalMethod = .custom; preview.calories = 1_800
        XCTAssertEqual(live.makeGoalEditorDraft(), before)
        XCTAssertNil(repo.savedUserGoals)
        XCTAssertTrue(repo.goalEditorSaveUserIDs.isEmpty)
    }

    func testEditingNormalizationMapsOnlyKnownLegacyGoalLabelsAndPreservesEveryOtherField() {
        let aliases = [("Lose Weight", "Lose"), ("Gain Weight", "Gain"), ("Maintain Weight", "Maintain")]
        for (legacy, canonical) in aliases {
            var original = model(.dynamicTDEE).makeGoalEditorDraft()
            original.goal = legacy
            var expected = original
            expected.goal = canonical
            XCTAssertEqual(original.normalizedForEditing(), expected)
            XCTAssertEqual(original.goal, legacy, "Normalizing a value copy cannot mutate its baseline")
        }
        for goal in ["Lose", "Maintain", "Gain", "lose weight", "Lose Weight ", "Unknown"] {
            var original = model().makeGoalEditorDraft()
            original.goal = goal
            XCTAssertEqual(original.normalizedForEditing(), original)
        }
    }

    func testLegacyGoalPreviewDiscardAndRejectedSaveRemainInertUntilExplicitAcceptedSave() async throws {
        let cacheKey = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner))
        for method in [CalorieGoalMethod.custom, .dynamicTDEE] {
            for (legacy, canonical) in [("Lose Weight", "Lose"), ("Gain Weight", "Gain"), ("Maintain Weight", "Maintain")] {
                let live = model(method)
                live.goal = legacy
                let baseline = live.makeGoalEditorDraft()
                let cachedBefore = UserDefaults.standard.dictionary(forKey: cacheKey) as NSDictionary?
                let previousWrites = repo.goalEditorSaveUserIDs.count
                repo.savedUserGoals = nil
                repo.mockFetchUserGoalsResult = baseline.payload(updatedAt: Date())
                let proposal = baseline.normalizedForEditing()
                do {
                    let preview = GoalSettings(isEditingPreview: true)
                    preview.applyGoalEditorPreview(proposal)
                    XCTAssertEqual(preview.makeGoalEditorDraft(), proposal)
                    XCTAssertEqual(preview.goal, canonical)
                    XCTAssertEqual(preview.calorieGoalMethod, method)
                }
                XCTAssertEqual(live.makeGoalEditorDraft(), baseline, "Opening and discarding only changes the isolated preview")
                XCTAssertEqual(repo.goalEditorSaveUserIDs.count, previousWrites)
                XCTAssertEqual(UserDefaults.standard.dictionary(forKey: cacheKey) as NSDictionary?, cachedBefore)

                repo.saveUserGoalsError = URLError(.notConnectedToInternet)
                do {
                    try await live.saveGoalEditorDraft(proposal, baseline: baseline, userID: owner)
                    XCTFail("Expected rejected save")
                } catch {}
                XCTAssertEqual(live.makeGoalEditorDraft(), baseline)
                XCTAssertNil(repo.savedUserGoals)
                XCTAssertEqual(UserDefaults.standard.dictionary(forKey: cacheKey) as NSDictionary?, cachedBefore)

                repo.saveUserGoalsError = nil
                try await live.saveGoalEditorDraft(proposal, baseline: baseline, userID: owner)
                XCTAssertEqual(live.goal, canonical)
                XCTAssertEqual(live.calorieGoalMethod, method)
                if method == .custom { XCTAssertEqual(live.calories, baseline.calories) }
                XCTAssertEqual(repo.savedUserGoals?["goal"] as? String, canonical)
                XCTAssertEqual(repo.savedUserGoals?["calorieGoalMethod"] as? String, method.rawValue)
                XCTAssertEqual(live.waterGoal, 93)
                XCTAssertEqual(live.suggestionCuisines, ["Italian"])
                XCTAssertEqual(live.weightHistory.map(\.id), ["history"])
            }
        }
    }

    func testUnknownGoalStaysInvalidWithoutWritingOrChangingLiveSettings() async {
        let live = model()
        live.goal = "Unexpected goal"
        let baseline = live.makeGoalEditorDraft()
        let proposal = baseline.normalizedForEditing()
        XCTAssertEqual(proposal, baseline)
        do {
            try await live.saveGoalEditorDraft(proposal, baseline: baseline, userID: owner)
            XCTFail("Unknown labels must fail closed")
        } catch {}
        XCTAssertTrue(repo.goalEditorSaveUserIDs.isEmpty)
        XCTAssertEqual(live.makeGoalEditorDraft(), baseline)
    }

    func testFailureKeepsCurrentAndCacheUnchangedThenSameProposalRetries() async throws {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        var proposal = baseline; proposal.calories = 1_850; proposal.targetWeight = 140
        repo.saveUserGoalsError = URLError(.notConnectedToInternet)
        do { try await live.saveGoalEditorDraft(proposal, baseline: baseline, userID: owner); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(live.makeGoalEditorDraft(), baseline)
        XCTAssertNil(repo.savedUserGoals)
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner))
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        repo.saveUserGoalsError = nil
        try await live.saveGoalEditorDraft(proposal, baseline: baseline, userID: owner)
        XCTAssertEqual(live.calories, 1_850)
        XCTAssertEqual(live.targetWeight, 140)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: key))
        XCTAssertEqual(live.waterGoal, 93)
        XCTAssertEqual(live.suggestionCuisines, ["Italian"])
        XCTAssertEqual(live.weightHistory.map(\.id), ["history"])
        let payload = try XCTUnwrap(repo.savedUserGoals?["goals"] as? [String: Any])
        XCTAssertNil(payload["waterGoal"])
        XCTAssertNil(payload["suggestionCuisines"])
    }

    func testUnrelatedInputChangesPreserveEveryExplicitMethod() async throws {
        for method in CalorieGoalMethod.allCases {
            let live = model(method)
            let baseline = live.makeGoalEditorDraft()
            var draft = baseline; draft.age += 1; draft.goal = "Lose"
            try await live.saveGoalEditorDraft(draft, baseline: baseline, userID: owner)
            XCTAssertEqual(live.calorieGoalMethod, method)
            XCTAssertEqual(repo.savedUserGoals?["calorieGoalMethod"] as? String, method.rawValue)
        }
    }

    func testManualValueNearFormulaRemainsManualAndMinimumIsResolvedBeforeSave() async throws {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        var draft = baseline
        draft.calories = live.formulaMaintenanceCalories
        try await live.saveGoalEditorDraft(draft, baseline: baseline, userID: owner)
        XCTAssertEqual(live.calorieGoalMethod, .custom)
        let next = live.makeGoalEditorDraft()
        draft = next; draft.calories = 100
        XCTAssertEqual(try draft.resolved(adaptiveTDEE: nil, manualCaloriesBurned: 0).calories, 1_500)
        try await live.saveGoalEditorDraft(draft, baseline: next, userID: owner)
        XCTAssertEqual(live.calories, 1_500)
    }

    func testInvalidAndNonFiniteInputsNeverWriteOrNormalizeLivePercentages() async {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        var invalid = [GoalEditorDraft]()
        var draft = baseline; draft.calories = .infinity; invalid.append(draft)
        draft = baseline; draft.weight = .nan; invalid.append(draft)
        draft = baseline; draft.targetWeight = -1; invalid.append(draft)
        draft = baseline; draft.proteinPercentage = 55; invalid.append(draft)
        for value in invalid {
            do { try await live.saveGoalEditorDraft(value, baseline: baseline, userID: owner); XCTFail("Expected invalid draft") } catch {}
        }
        XCTAssertTrue(repo.goalEditorSaveUserIDs.isEmpty)
        XCTAssertEqual(live.makeGoalEditorDraft(), baseline)
    }

    func testLocalOrRemoteConflictingInputsRejectWithoutOverwriting() async {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        live.age += 1
        do { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner); XCTFail("Expected local conflict") } catch {}
        XCTAssertTrue(repo.goalEditorSaveUserIDs.isEmpty)
        live.age = baseline.age
        var remote = baseline.payload(updatedAt: Date()); remote["age"] = baseline.age + 2
        repo.mockFetchUserGoalsResult = remote
        do { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner); XCTFail("Expected remote conflict") } catch {}
        XCTAssertNil(repo.savedUserGoals)
    }

    func testAccountChangeBeforeSaveOrDuringAwaitNeverPublishesToNewAccount() async {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        auth.currentUserID = "other"
        do { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner); XCTFail("Expected account rejection") } catch {}
        XCTAssertTrue(repo.goalEditorSaveUserIDs.isEmpty)
        auth.currentUserID = owner
        repo.goalEditorSaveDelayNanoseconds = 40_000_000
        let pending = Task { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner) }
        await waitForSave()
        auth.currentUserID = "other"; live.activateAccount("other")
        do { try await pending.value; XCTFail("Expected stale completion rejection") } catch {}
        XCTAssertNil(live.calories)
        XCTAssertNil(repo.savedUserGoals)
    }

    func testAcceptedWriteAfterAccountSwitchHasNoNewAccountPublication() async {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        repo.onSave = { [self] in auth.currentUserID = "other"; live.activateAccount("other") }
        do { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner); XCTFail("Expected account handoff rejection") } catch {}
        XCTAssertEqual(repo.goalEditorSaveUserIDs, [owner])
        XCTAssertNotNil(repo.savedUserGoals, "The original account write was accepted before the account changed")
        XCTAssertNil(live.calories)
    }

    func testRapidSecondSaveIsRejectedWhileFirstProposalIsPending() async throws {
        let live = model()
        let baseline = live.makeGoalEditorDraft()
        repo.goalEditorSaveDelayNanoseconds = 40_000_000
        let pending = Task { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner) }
        await waitForSave()
        do { try await live.saveGoalEditorDraft(baseline, baseline: baseline, userID: owner); XCTFail("Expected duplicate guard") } catch {}
        try await pending.value
        XCTAssertEqual(repo.goalEditorSaveUserIDs, [owner])
    }

    func testPersistedComparisonAllowsLegacyOmissionsAndDerivedTargetRefreshButRejectsChangedMethod() {
        let baseline = model(.dynamicTDEE).makeGoalEditorDraft()
        XCTAssertTrue(baseline.matchesPersistedInputs([:]))
        var data = baseline.payload(updatedAt: Date()); data["calories"] = 3_000
        XCTAssertTrue(baseline.matchesPersistedInputs(data))
        data["calorieGoalMethod"] = CalorieGoalMethod.custom.rawValue
        XCTAssertFalse(baseline.matchesPersistedInputs(data))
    }

    func testWaterGoalFailureRetainsCurrentTargetMethodAndHistoryUntilAcceptedRetry() async throws {
        let live = model(.custom)
        let before = live.makeGoalEditorDraft()
        repo.saveUserGoalsError = URLError(.notConnectedToInternet)
        do { try await live.saveWaterGoal(100, baseline: 93, userID: owner); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(live.waterGoal, 93)
        XCTAssertEqual(live.makeGoalEditorDraft(), before)
        repo.saveUserGoalsError = nil
        try await live.saveWaterGoal(100, baseline: 93, userID: owner)
        XCTAssertEqual(live.waterGoal, 100)
        XCTAssertEqual(live.makeGoalEditorDraft(), before)
        XCTAssertEqual(live.weightHistory.map(\.id), ["history"])
        XCTAssertEqual(repo.savedUserGoals?.keys.sorted(), ["goals"])
        XCTAssertEqual((repo.savedUserGoals?["goals"] as? [String: Double])?["waterGoal"], 100)
    }

    func testAcceptedWaterTargetSurvivesRoutineCalorieRecalculation() async throws {
        let live = GoalSettings()
        live.activateAccount(owner)
        await withCheckedContinuation { continuation in live.recalculateAllGoals { continuation.resume() } }
        try await live.saveWaterGoal(93, baseline: live.waterGoal, userID: owner)
        live.weight += 2
        await withCheckedContinuation { continuation in live.recalculateAllGoals { continuation.resume() } }
        XCTAssertEqual(live.waterGoal, 93, "A routine calorie or body-measurement refresh cannot replace an accepted water target")
        var oldHistory = HydrationPreferences()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try oldHistory.acceptTarget(80, at: yesterday)
        live.hydrationPreferences = oldHistory
        XCTAssertEqual(live.hydrationTarget(for: Date()), 93, "A failed local history write cannot conceal the confirmed account target")
        XCTAssertEqual(live.hydrationTarget(for: yesterday), 80)
        try oldHistory.acceptTarget(nil)
        live.hydrationPreferences = oldHistory
        XCTAssertNil(live.hydrationTarget(for: Date()), "Tracking-only is an explicit independent preference")
        auth.currentUserID = "another-goal-owner"; live.activateAccount("another-goal-owner")
        await withCheckedContinuation { continuation in live.recalculateAllGoals { continuation.resume() } }
        XCTAssertEqual(live.waterGoal, GoalSettingsRules.calculateMicronutrientGoals(age: live.age, gender: live.gender).water)
    }

    func testWaterGoalRejectsInvalidAndConflictingBaselineWithoutPublishing() async {
        let live = model()
        for value in [Double.nan, .infinity, 0, 513] {
            do { try await live.saveWaterGoal(value, baseline: 93, userID: owner); XCTFail("Expected invalid target") } catch {}
        }
        do { try await live.saveWaterGoal(100, baseline: 64, userID: owner); XCTFail("Expected local conflict") } catch {}
        XCTAssertTrue(repo.waterGoalSaveUserIDs.isEmpty)
        repo.mockFetchUserGoalsResult = ["goals": ["waterGoal": 120]]
        do { try await live.saveWaterGoal(100, baseline: 93, userID: owner); XCTFail("Expected remote conflict") } catch {}
        XCTAssertEqual(live.waterGoal, 93)
        XCTAssertNil(repo.savedUserGoals)
    }

    func testWaterGoalAccountChangeAndDuplicateSaveCannotPublishOrWriteAnotherAccount() async {
        let live = model()
        repo.goalEditorSaveDelayNanoseconds = 40_000_000
        let pending = Task { try await live.saveWaterGoal(100, baseline: 93, userID: owner) }
        for _ in 0..<100 where repo.waterGoalSaveUserIDs.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(repo.waterGoalSaveUserIDs, [owner])
        do { try await live.saveWaterGoal(120, baseline: 93, userID: owner); XCTFail("Expected duplicate rejection") } catch {}
        auth.currentUserID = "other"; live.activateAccount("other")
        do { try await pending.value; XCTFail("Expected account rejection") } catch {}
        XCTAssertEqual(live.waterGoal, 64)
        XCTAssertNil(repo.savedUserGoals)
    }

    func testHeightOnlyCheckedChangeRetainsExactMetricValueAndManualTarget() async throws {
        let live = model(.custom)
        let before = live.makeGoalEditorDraft()
        var proposal = before
        proposal.height = 181.3
        try await live.saveGoalEditorDraft(proposal, baseline: before, userID: owner)
        XCTAssertEqual(live.height, 181.3)
        XCTAssertEqual(live.calorieGoalMethod, .custom)
        XCTAssertEqual(live.calories, before.calories)
        XCTAssertEqual(live.waterGoal, 93)
    }

    private func waitForSave() async {
        for _ in 0..<100 where repo.goalEditorSaveUserIDs.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(repo.goalEditorSaveUserIDs.isEmpty)
    }
}
