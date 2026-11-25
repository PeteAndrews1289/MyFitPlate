import XCTest
@testable import MyFitPlateCore

@MainActor
final class FoodPreferencesIntegrityTests: XCTestCase {
    private var auth: MockAuthService!
    private var repository: MockSettingsRepository!
    private var previousAuth: AuthServiceProtocol?
    private var previousRepository: SettingsRepositoryProtocol?
    private var owner = ""

    override func setUp() {
        super.setUp()
        previousAuth = DIContainer.shared.authService
        previousRepository = DIContainer.shared.settingsRepository
        owner = "food-preferences-\(UUID().uuidString)"
        auth = MockAuthService(); auth.currentUserID = owner
        repository = MockSettingsRepository()
        DIContainer.shared.authService = auth
        DIContainer.shared.settingsRepository = repository
    }

    override func tearDown() {
        if let key = AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner) { UserDefaults.standard.removeObject(forKey: key) }
        DIContainer.shared.authService = previousAuth
        DIContainer.shared.settingsRepository = previousRepository
        super.tearDown()
    }

    private func model() -> GoalSettings {
        let result = GoalSettings(isEditingPreview: true)
        result.activateAccount(owner)
        result.calorieGoalMethod = .custom
        result.calories = 2_137; result.protein = 143; result.carbs = 271; result.fats = 67
        result.waterGoal = 93
        result.weightHistory = [("existing-weight", Date(timeIntervalSince1970: 1_700_000_000), 170)]
        result.suggestionProteins = ["Tempeh", "Fish"]
        return result
    }

    func testLegacyOriginRemainsUnknownUntilExplicitReviewedSaveAndConcurrentOriginChangesConflict() async throws {
        let live = model(), baseline = live.makeFoodPreferencesDraft()
        XCTAssertNil(baseline.selectionOrigin)
        var reviewed = baseline; reviewed.selectionOrigin = "reviewed"
        try await live.saveFoodPreferencesDraft(reviewed, revision: .init(userID: owner, baseline: baseline))
        XCTAssertEqual(live.foodPreferenceOrigin, "reviewed")
        XCTAssertEqual(reviewed.profilePatch(updatedAt: Date())["goals.foodPreferenceOrigin"] as? String, "reviewed")
        XCTAssertFalse(baseline.matchesPersistedPreferences(["goals": ["foodPreferenceOrigin": "reviewed"]]))
        XCTAssertTrue(baseline.matchesPersistedPreferences(["goals": [:]]))
        XCTAssertFalse(reviewed.matchesPersistedPreferences(["goals": ["foodPreferenceOrigin": 42]]))
    }

    func testDiscardingDraftAndUnchangedSaveAreInert() async throws {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        var discarded = baseline
        discarded.proteins = []; discarded.cuisines = ["Mexican"]
        XCTAssertNotEqual(discarded, live.makeFoodPreferencesDraft())
        try await live.saveFoodPreferencesDraft(baseline, revision: .init(userID: owner, baseline: baseline))
        XCTAssertEqual(live.makeFoodPreferencesDraft(), baseline)
        XCTAssertTrue(repository.foodPreferencesSaveUserIDs.isEmpty)
        XCTAssertNil(repository.savedUserGoals)
    }

    func testAcceptedSaveOnlyPatchesPreferencesAndPreservesEveryGoalAndHistory() async throws {
        let live = model()
        let goals = live.makeGoalEditorDraft()
        let baseline = live.makeFoodPreferencesDraft()
        var draft = baseline
        draft.carbs = []; draft.cuisines = ["Any"]
        try await live.saveFoodPreferencesDraft(draft, revision: .init(userID: owner, baseline: baseline))
        XCTAssertEqual(live.makeFoodPreferencesDraft(), draft)
        XCTAssertEqual(live.suggestionProteins, ["Tempeh", "Fish"], "Saved choices outside the menu remain intact")
        XCTAssertEqual(live.makeGoalEditorDraft(), goals)
        XCTAssertEqual(live.protein, 143); XCTAssertEqual(live.carbs, 271); XCTAssertEqual(live.fats, 67)
        XCTAssertEqual(live.waterGoal, 93); XCTAssertEqual(live.weightHistory.map(\.id), ["existing-weight"])
        let patch = try XCTUnwrap(repository.savedUserGoals)
        XCTAssertEqual(Set(patch.keys), ["goals.suggestionProteins", "goals.suggestionCarbs", "goals.suggestionVeggies", "goals.suggestionCuisines", "goals.mealConstraintProfile", "goals.foodPreferenceOrigin", "goals.updatedAt"])
        XCTAssertEqual(patch["goals.suggestionCarbs"] as? [String], [])
        XCTAssertTrue(patch["goals.foodPreferenceOrigin"] is NSNull, "A programmatic edit does not claim the legacy preferences were explicitly reviewed")
        XCTAssertNil(patch["calories"]); XCTAssertNil(patch["goals.calories"])
    }

    func testHardConstraintsSaveWithPreferencesWithoutChangingTargetsAndRejectRemoteConflict() async throws {
        let live = model()
        let originalGoals = live.makeGoalEditorDraft()
        let baseline = live.makeFoodPreferencesDraft()
        var requested = baseline
        requested.mealConstraintProfile = MealConstraintProfile(revisionID: "requested", diet: .vegetarian, hardExclusions: ["peanut"])
        try await live.saveFoodPreferencesDraft(requested, revision: .init(userID: owner, baseline: baseline))
        XCTAssertEqual(live.mealConstraintProfile, requested.mealConstraintProfile)
        XCTAssertEqual(live.makeGoalEditorDraft(), originalGoals)
        let acceptedFields = try XCTUnwrap(repository.savedUserGoals?["goals.mealConstraintProfile"] as? [String: Any])
        XCTAssertEqual(try MealConstraintProfile.decodeField(acceptedFields), requested.mealConstraintProfile)
        let remote = MealConstraintProfile(revisionID: "remote", diet: .vegan, hardExclusions: ["sesame"])
        var remoteFields: [String: Any] = requested.fields
        remoteFields["mealConstraintProfile"] = remote.fields
        repository.mockFetchUserGoalsResult = ["goals": remoteFields]
        var stale = requested; stale.carbs = ["Rice"]
        do {
            try await live.saveFoodPreferencesDraft(stale, revision: .init(userID: owner, baseline: requested))
            XCTFail("The current hard profile must participate in the same compare-and-set")
        } catch FoodPreferencesError.changed { }
        XCTAssertEqual(live.mealConstraintProfile, remote)
        XCTAssertEqual(live.makeGoalEditorDraft(), originalGoals)
        XCTAssertEqual(stale.mealConstraintProfile, requested.mealConstraintProfile)
    }

    func testUnknownConstraintVersionCannotBeOverwrittenByAnOlderPreferencesEditor() async throws {
        let live = model()
        live.mealConstraintProfile = MealConstraintProfile(schemaVersion: 99, revisionID: "future", hardExclusions: ["peanut"])
        let baseline = live.makeFoodPreferencesDraft()
        var proposed = baseline
        proposed.mealConstraintProfile = MealConstraintProfile(revisionID: "older", hardExclusions: [])
        do {
            try await live.saveFoodPreferencesDraft(proposed, revision: .init(userID: owner, baseline: baseline))
            XCTFail("A compatible editor is required before replacing a newer schema")
        } catch { }
        XCTAssertEqual(live.mealConstraintProfile?.schemaVersion, 99)
        XCTAssertTrue(repository.foodPreferencesSaveUserIDs.isEmpty)
    }

    func testFailedSaveLeavesDraftLiveModelAndCacheThenSameDraftRetries() async throws {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        let revision = FoodPreferencesRevision(userID: owner, baseline: baseline)
        var draft = baseline; draft.cuisines = ["Mediterranean"]
        repository.saveUserGoalsError = URLError(.notConnectedToInternet)
        do { try await live.saveFoodPreferencesDraft(draft, revision: revision); XCTFail("Expected offline failure") } catch {}
        XCTAssertEqual(draft.cuisines, ["Mediterranean"])
        XCTAssertEqual(live.makeFoodPreferencesDraft(), baseline)
        XCTAssertNil(repository.savedUserGoals)
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner))
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        repository.saveUserGoalsError = nil
        try await live.saveFoodPreferencesDraft(draft, revision: revision)
        XCTAssertEqual(live.makeFoodPreferencesDraft(), draft)
    }

    func testLocalAndRemotePreferenceConflictsFailWithoutOverwriting() async {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        let revision = FoodPreferencesRevision(userID: owner, baseline: baseline)
        var draft = baseline; draft.proteins = ["Tofu"]
        live.suggestionCuisines = ["Mexican"]
        do { try await live.saveFoodPreferencesDraft(draft, revision: revision); XCTFail("Expected local conflict") } catch {}
        XCTAssertTrue(repository.foodPreferencesSaveUserIDs.isEmpty)
        live.suggestionCuisines = baseline.cuisines
        repository.mockFetchUserGoalsResult = ["goals": ["suggestionProteins": ["Eggs"]]]
        do { try await live.saveFoodPreferencesDraft(draft, revision: revision); XCTFail("Expected remote conflict") } catch {}
        var refreshed = baseline; refreshed.proteins = ["Eggs"]
        XCTAssertEqual(live.makeFoodPreferencesDraft(), refreshed, "Reopening can use the current remote preferences")
        XCTAssertEqual(draft.proteins, ["Tofu"], "Conflict recovery cannot replace the open editor's local draft")
        XCTAssertNil(repository.savedUserGoals)
    }

    func testAccountHandoffBeforeAndDuringSaveCannotPublishIntoNewAccount() async {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        let revision = FoodPreferencesRevision(userID: owner, baseline: baseline)
        var draft = baseline; draft.proteins = ["Tofu"]
        auth.currentUserID = "other"
        do { try await live.saveFoodPreferencesDraft(draft, revision: revision); XCTFail("Expected account rejection") } catch {}
        XCTAssertTrue(repository.foodPreferencesSaveUserIDs.isEmpty)
        auth.currentUserID = owner
        repository.beforeNextGoalEditorCommit = { [auth] in auth?.currentUserID = "other"; live.activateAccount("other") }
        do { try await live.saveFoodPreferencesDraft(draft, revision: revision); XCTFail("Expected account handoff rejection") } catch {}
        XCTAssertEqual(live.makeFoodPreferencesDraft(), .defaults)
        XCTAssertNil(repository.savedUserGoals)
    }

    func testAnyAndStarterDefaultsAreDifferentAndMalformedPresentArraysFailClosed() throws {
        let defaults = FoodPreferencesDraft.defaults
        var any = defaults; any.proteins = []; any.carbs = []; any.vegetables = []; any.cuisines = ["Any"]
        XCTAssertNotEqual(defaults, any)
        XCTAssertEqual(try any.validated(), any)
        XCTAssertTrue(defaults.matchesPersistedPreferences(["goals": ["calories": 2_000]]))
        XCTAssertTrue(defaults.matchesPersistedPreferences([:]))
        XCTAssertFalse(defaults.matchesPersistedPreferences(["goals": ["suggestionProteins": "Fish"]]))
        for malformed: Any in ["not a map", NSNull(), ["not", "a", "map"]] {
            XCTAssertFalse(defaults.matchesPersistedPreferences(["goals": malformed]))
        }
        var invalid = defaults; invalid.proteins = [" "]
        XCTAssertThrowsError(try invalid.validated())
    }

    func testRemoteConflictRefreshesOnlyPreferencesAndReopeningCanSaveWithoutRelaunch() async throws {
        let live = model()
        let goals = live.makeGoalEditorDraft()
        let baseline = live.makeFoodPreferencesDraft()
        let oldRevision = FoodPreferencesRevision(userID: owner, baseline: baseline)
        var localDraft = baseline; localDraft.proteins = ["Tofu"]
        let remote = FoodPreferencesDraft(proteins: ["Eggs", "Lentils"], carbs: ["Quinoa"], vegetables: [], cuisines: ["Italian"])
        var remoteGoals: [String: Any] = remote.fields
        remoteGoals["calories"] = 9_999; remoteGoals["protein"] = 1; remoteGoals["waterGoal"] = 512
        repository.mockFetchUserGoalsResult = ["goals": remoteGoals, "age": 99, "weight": 999]
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner))
        UserDefaults.standard.set(["cacheMarker": "keep", "goals": ["calories": 1_875, "cachedGoalMarker": "keep"]], forKey: key)
        do {
            try await live.saveFoodPreferencesDraft(localDraft, revision: oldRevision)
            XCTFail("The old editor must still report a conflict")
        } catch FoodPreferencesError.changed { } catch { XCTFail("Unexpected conflict recovery error: \(error)") }
        XCTAssertEqual(localDraft.proteins, ["Tofu"])
        XCTAssertEqual(oldRevision.baseline, baseline)
        XCTAssertEqual(live.makeFoodPreferencesDraft(), remote)
        XCTAssertEqual(live.makeGoalEditorDraft(), goals)
        XCTAssertEqual(live.protein, 143); XCTAssertEqual(live.carbs, 271); XCTAssertEqual(live.fats, 67)
        XCTAssertEqual(live.waterGoal, 93); XCTAssertEqual(live.weightHistory.map(\.id), ["existing-weight"])
        XCTAssertNil(repository.savedUserGoals, "Refreshing a conflict never autosaves the rejected proposal")
        let cached = try XCTUnwrap(UserDefaults.standard.dictionary(forKey: key))
        let cachedGoals = try XCTUnwrap(cached["goals"] as? [String: Any])
        XCTAssertEqual(cached["cacheMarker"] as? String, "keep")
        XCTAssertEqual(cachedGoals["calories"] as? Int, 1_875)
        XCTAssertEqual(cachedGoals["cachedGoalMarker"] as? String, "keep")
        XCTAssertEqual(cachedGoals["suggestionProteins"] as? [String], remote.proteins)
        XCTAssertEqual(cachedGoals["suggestionVeggies"] as? [String], [])
        XCTAssertNil(cachedGoals["updatedAt"])
        let reopenedBaseline = live.makeFoodPreferencesDraft()
        var reopened = reopenedBaseline; reopened.cuisines = ["Mexican"]
        try await live.saveFoodPreferencesDraft(reopened, revision: .init(userID: owner, baseline: reopenedBaseline))
        XCTAssertEqual(live.makeFoodPreferencesDraft(), reopened)
        XCTAssertEqual(live.makeGoalEditorDraft(), goals)
    }

    func testAccountSwitchDuringConflictRefreshCannotPublishOrCacheOldAccountPreferences() async throws {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        var draft = baseline; draft.cuisines = ["Mexican"]
        let remote: [String: Any] = ["goals": ["suggestionProteins": ["Eggs"]]]
        repository.mockFetchUserGoalsResult = remote
        repository.shouldDeferFetchUserGoals = true
        let saving = Task { try await live.saveFoodPreferencesDraft(draft, revision: .init(userID: owner, baseline: baseline)) }
        for _ in 0..<300 { if repository.fetchUserGoalsCallbacks[owner] != nil { break }; await Task.yield() }
        let callback = try XCTUnwrap(repository.fetchUserGoalsCallbacks[owner])
        auth.currentUserID = "other-account"; live.activateAccount("other-account")
        let newAccountGoals = live.makeGoalEditorDraft()
        callback(remote)
        do { try await saving.value; XCTFail("The old refresh must reject the account switch") } catch FoodPreferencesError.accountChanged { }
        XCTAssertEqual(live.makeFoodPreferencesDraft(), .defaults)
        XCTAssertEqual(live.makeGoalEditorDraft(), newAccountGoals)
        XCTAssertNil(repository.savedUserGoals)
        let oldKey = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner))
        XCTAssertNil(UserDefaults.standard.object(forKey: oldKey))
    }

    func testMalformedRemoteGoalsAndPreferenceArraysNeverReplaceLiveValuesOrCache() async throws {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        var draft = baseline; draft.proteins = ["Tofu"]
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "cached_user_goals", userID: owner))
        let cached: [String: Any] = ["cacheMarker": "unchanged"]
        UserDefaults.standard.set(cached, forKey: key)
        let malformed: [Any] = [NSNull(), "not a map", ["array"], ["suggestionProteins": "not an array"], ["suggestionProteins": [String(repeating: "x", count: 121)]]]
        for goals in malformed {
            repository.mockFetchUserGoalsResult = ["goals": goals]
            do {
                try await live.saveFoodPreferencesDraft(draft, revision: .init(userID: owner, baseline: baseline))
                XCTFail("Malformed server preferences must fail closed")
            } catch FoodPreferencesError.unavailable { } catch { XCTFail("Unexpected malformed refresh error: \(error)") }
            XCTAssertEqual(live.makeFoodPreferencesDraft(), baseline)
            XCTAssertEqual(UserDefaults.standard.dictionary(forKey: key) as NSDictionary?, cached as NSDictionary)
            XCTAssertNil(repository.savedUserGoals)
        }
    }

    func testReconstructedNSErrorConflictRefreshesCurrentPreferencesAndKeepsTheOpenDraft() async throws {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        let goals = live.makeGoalEditorDraft()
        var draft = baseline; draft.proteins = ["Tofu"]
        let originalError = FoodPreferencesError.changed as NSError
        repository.mockFetchUserGoalsResult = ["goals": baseline.fields]
        repository.saveUserGoalsError = NSError(domain: originalError.domain, code: originalError.code,
            userInfo: [NSLocalizedDescriptionKey: "Transaction conflict"])
        repository.shouldDeferFetchUserGoals = true
        let pending = Task { try await live.saveFoodPreferencesDraft(draft, revision: .init(userID: owner, baseline: baseline)) }
        for _ in 0..<300 { if repository.fetchUserGoalsCallbacks[owner] != nil { break }; await Task.yield() }
        let callback = try XCTUnwrap(repository.fetchUserGoalsCallbacks[owner], "A reconstructed conflict must request current preferences")
        var remote = baseline; remote.proteins = ["Eggs"]; remote.cuisines = ["Italian"]
        callback(["goals": remote.fields])
        do { try await pending.value; XCTFail("The original editor must still report conflict") } catch FoodPreferencesError.changed { }
        XCTAssertEqual(live.makeFoodPreferencesDraft(), remote)
        XCTAssertEqual(live.makeGoalEditorDraft(), goals)
        XCTAssertEqual(draft.proteins, ["Tofu"])
        XCTAssertNil(repository.savedUserGoals)
    }

    func testOtherNSErrorDomainsOrCodesNeverTriggerConflictRefresh() async throws {
        let live = model()
        let baseline = live.makeFoodPreferencesDraft()
        var draft = baseline; draft.proteins = ["Tofu"]
        let conflict = FoodPreferencesError.changed as NSError
        repository.mockFetchUserGoalsResult = ["goals": baseline.fields]
        for failure in [NSError(domain: conflict.domain, code: conflict.code + 100), NSError(domain: "UnrelatedTransaction", code: conflict.code)] {
            repository.saveUserGoalsError = failure
            do {
                try await live.saveFoodPreferencesDraft(draft, revision: .init(userID: owner, baseline: baseline))
                XCTFail("Expected the original save failure")
            } catch {
                XCTAssertEqual((error as NSError).domain, failure.domain)
                XCTAssertEqual((error as NSError).code, failure.code)
            }
            XCTAssertTrue(repository.fetchedUserGoalIDs.isEmpty)
            XCTAssertEqual(live.makeFoodPreferencesDraft(), baseline)
            XCTAssertNil(repository.savedUserGoals)
        }
    }
}
