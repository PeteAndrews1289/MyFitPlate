import XCTest
import UserNotifications
@testable import MyFitPlateCore

final class ReminderPolicyTests: XCTestCase {
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "America/New_York")!; return value }
    private func date(_ day: Int = 4, hour: Int = 9, month: Int = 11) -> Date { calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))! }
    private func record(_ kinds: [ReminderKind]) -> ReminderAccountRecord {
        var value = ReminderAccountRecord(); for kind in kinds { value.preferences[kind].enabled = true }; return value
    }
    private func evidence() -> ReminderEvidence { .init(goals: .init(calories: 2_000, protein: 120, carbs: 200, fats: 65), waterGoal: 64) }

    func testDefaultsOffAndSevenDayCalendarAcrossDSTHasStableCivilDays() {
        XCTAssertTrue(ReminderPolicy.decisions(ownerID: "a", record: .init(), evidence: evidence(), now: date()).isEmpty)
        let now = date(7, hour: 6, month: 3)
        let values = ReminderPolicy.decisions(ownerID: "a", record: record([.weighIn]), evidence: evidence(), now: now, calendar: calendar)
        XCTAssertEqual(values.count, 7)
        XCTAssertEqual(Set(values.map { $0.candidate.target.dayKey }).count, 7)
        XCTAssertTrue(values.allSatisfy { calendar.component(.hour, from: $0.candidate.fireDate) == 7 })
        XCTAssertTrue(values.allSatisfy { $0.candidate.target.day()?.timeZoneIdentifier == "America/New_York" })
    }

    func testAccountIDsAndExactTargetsDoNotCrossAccounts() throws {
        let a = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: record([.dailyLog]), evidence: evidence(), now: date(), calendar: calendar).first)
        let b = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "b", record: record([.dailyLog]), evidence: evidence(), now: date(), calendar: calendar).first)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertFalse(a.candidate.target.isAvailable(ownerID: "b", now: date()))
        XCTAssertEqual(a.candidate.target.dayKey, "2026-11-04")
        XCTAssertFalse(a.candidate.target.isAvailable(ownerID: "a", now: date(5)))
    }

    func testPendingFoodAndWeightAndQueuedWaterSuppressWithoutFabricatingRecords() {
        var source = evidence()
        source.pendingFoodDayKeys = ["2026-11-04"]; source.pendingWeightDayKeys = ["2026-11-04"]
        source.logs["2026-11-04"] = DailyLog(id: "2026-11-04", date: date(), meals: [], waterTracker: .init(totalOunces: 64, date: date()))
        let values = ReminderPolicy.decisions(ownerID: "a", record: record([.dailyLog, .hydration, .weighIn]), evidence: source, now: date(hour: 6), calendar: calendar)
            .filter { $0.candidate.target.dayKey == "2026-11-04" }
        XCTAssertEqual(values.count, 6)
        XCTAssertTrue(values.allSatisfy { $0.state == .suppressed })
        XCTAssertTrue(values.contains { $0.reason.contains("submitted food") })
        XCTAssertEqual(source.logs["2026-11-04"]?.meals.count, 0)
    }

    func testCompleteDayRuleDoesNotTreatOneFoodAsWholeDayCompletion() {
        var source = evidence()
        source.logs["2026-11-04"] = DailyLog(id: "2026-11-04", date: date(), meals: [Meal(name: "Meal", foodItems: [FoodItem(name: "Food", calories: 400)])])
        var value = record([.dailyLog])
        XCTAssertEqual(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first?.state, .suppressed)
        value.preferences.diaryRule = .completeDay
        XCTAssertEqual(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first?.state, .ready)
        source.logs["2026-11-04"]?.nutritionDayStatus = .complete
        XCTAssertEqual(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first?.state, .suppressed)
    }

    func testUnavailableDiaryAndQuietHoursDoNotScheduleAssumedMissingActions() {
        var source = evidence(); source.unavailableDays = ["2026-11-04"]
        var value = record([.dailyLog]); value.preferences[.dailyLog].quietStart = 19 * 60
        let values = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar)
        XCTAssertTrue(values.allSatisfy { $0.state == .suppressed })
        XCTAssertTrue(values.allSatisfy { $0.reason.contains("quiet") })
        value.preferences[.dailyLog].quietStart = 22 * 60
        XCTAssertTrue(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first?.reason.contains("unavailable") == true)
    }

    func testBudgetUsesExistingDailyReservationsRatherThanEachRefresh() {
        var value = record([.hydration, .dailyLog, .weighIn]); value.preferences.maximumPerDay = 2
        let first = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(hour: 6), calendar: calendar)
        let today = first.filter { $0.candidate.target.dayKey == "2026-11-04" && $0.state == .ready }
        XCTAssertEqual(today.count, 2)
        value.reservations = today.map { .init(key: $0.candidate.budgetKey, dayKey: "2026-11-04", kind: $0.candidate.target.kind, reservedAt: date(hour: 6)) }
        let later = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(hour: 11), calendar: calendar)
        XCTAssertFalse(later.contains { $0.candidate.target.dayKey == "2026-11-04" && $0.candidate.target.kind == .hydration && $0.state == .ready })
    }

    func testHandledDayStaysHandledAndSnoozeSurvivesOriginalFireTime() throws {
        var value = record([.dailyLog])
        var item = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(), calendar: calendar).first)
        item.state = .handled; value.decisions[item.id] = item
        XCTAssertEqual(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(), calendar: calendar).first?.state, .handled)
        item.state = .scheduled; item.snoozeCount = 1; item.candidate.fireDate = date(hour: 21); item.candidate.budgetKey += ".snooze.1"
        value.decisions[item.id] = item
        let snoozed = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(hour: 20).addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(snoozed.first { $0.id == item.id }?.candidate.fireDate, date(hour: 21))
    }

    func testDisabledSnoozedReminderCannotBeRescheduled() throws {
        var value = record([.dailyLog])
        var item = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(), calendar: calendar).first)
        item.snoozeCount = 1; item.state = .scheduled; item.candidate.fireDate = date(hour: 21)
        value.decisions[item.id] = item; value.preferences[.dailyLog].enabled = false
        let values = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(hour: 20), calendar: calendar)
        XCTAssertEqual(values.first { $0.id == item.id }?.state, .suppressed)
    }

    func testPostFireScheduleChangeConsumesANewDailyReservation() throws {
        var value = record([.dailyLog]); value.preferences.maximumPerDay = 1
        let item = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(), calendar: calendar).first)
        value.decisions[item.id] = item
        value.reservations = [.init(key: item.candidate.budgetKey, dayKey: "2026-11-04", kind: .dailyLog, reservedAt: date())]
        value.preferences[.dailyLog].minutes = [21 * 60]
        let next = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: evidence(), now: date(hour: 20).addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(next.first { $0.id == item.id }?.state, .suppressed)
        XCTAssertTrue(next.first { $0.id == item.id }?.reason.contains("budget") == true)
    }

    func testMovedFuelPlanReplacesExactRevisionAndSkippedPlanStopsScheduling() throws {
        var source = evidence(); let value = record([.beforeTraining])
        var plan = fuelPlan(start: date(hour: 12)); source.fuelPlans = [plan]
        let first = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first)
        plan = fuelPlan(start: date(hour: 14)); plan.revisionID = "revision-two"; source.fuelPlans = [plan]
        let moved = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first)
        XCTAssertEqual(first.id, moved.id)
        XCTAssertNotEqual(first.candidate.fingerprint, moved.candidate.fingerprint)
        XCTAssertEqual(moved.candidate.target.planRevisionID, "revision-two")
        XCTAssertFalse(ReminderPolicy.actionIsCurrent(first.candidate, ownerID: "a", preferences: value.preferences, evidence: source, now: date(), calendar: calendar))
        plan.outcome = .init(status: .skipped, source: .programSkip, recordedAt: date()); source.fuelPlans = [plan]
        XCTAssertTrue(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).isEmpty)
    }

    func testFuelTapRechecksRemainingBudgetEvenWhenPlanRevisionDidNotChange() throws {
        var source = evidence(); source.fuelPlans = [fuelPlan(start: date(hour: 12))]
        let value = record([.beforeTraining])
        let item = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first)
        source.logs["2026-11-04"] = DailyLog(id: "2026-11-04", date: date(), meals: [Meal(name: "Meal", foodItems: [FoodItem(name: "Food", calories: 2_100, protein: 150, carbs: 250)])])
        XCTAssertFalse(ReminderPolicy.actionIsCurrent(item.candidate, ownerID: "a", preferences: value.preferences, evidence: source, now: date(hour: 11), calendar: calendar))
    }

    func testOvernightRecoveryTargetsActualRecoveryDayAndSuppressesSecondaryProtein() throws {
        let now = date(hour: 1).addingTimeInterval(60)
        var plan = fuelPlan(start: date(3, hour: 23))
        plan.outcome = .init(status: .completed, source: .manualConfirmation, recordedAt: date(hour: 1),
            actualEndAt: date(hour: 1), recoveryDiaryIsAuthoritative: true)
        var source = evidence(); source.fuelPlans = [plan]
        var value = record([.recovery, .eveningProtein]); value.preferences[.recovery].quietStart = 0; value.preferences[.recovery].quietEnd = 0
        let values = ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: now, calendar: calendar)
        let recovery = try XCTUnwrap(values.first { $0.candidate.target.kind == .recovery })
        XCTAssertEqual(recovery.candidate.target.dayKey, "2026-11-04")
        XCTAssertEqual(recovery.state, .ready)
        XCTAssertTrue(values.filter { $0.candidate.target.kind == .eveningProtein }.allSatisfy { $0.state == .suppressed })
    }

    private func fuelPlan(start: Date) -> TrainingFuelConfirmedPlan {
        let draft = TrainingFuelPlanDraft(id: "fixed-fuel-plan", candidate: TrainingFuelSessionAdapter.manualCandidate(kind: .strength),
            scheduledAt: start, durationMinutes: 60, intensity: .hard, strengthFocus: .lowerBody, preference: .init())
        let proposal = TrainingFuelPlannerPlan(status: .ready, normalizedDurationMinutes: 60, normalizedIntensity: .hard,
            minutesUntilSession: 180, remainingCalories: 1_200, remainingProteinGrams: 100, remainingCarbGrams: 160,
            allocations: [.init(phase: .beforeTraining, timing: .thirtyTo120Minutes, proteinGrams: 15, carbGrams: 35),
                .init(phase: .afterTraining, timing: .afterSession, proteinGrams: 25, carbGrams: 45)], notes: [])
        var plan = TrainingFuelConfirmedPlan(draft: draft, plannerPlan: proposal, goals: evidence().goals,
            today: DailyLog(date: start, meals: []), confirmedAt: date(3, hour: 8))
        plan.ownerID = "a"; plan.revisionID = "revision-one"
        return plan
    }

    func testActionRevalidatesCompletionAfterOriginalDeliveryTime() throws {
        let value = record([.dailyLog]); var source = evidence()
        let item = try XCTUnwrap(ReminderPolicy.decisions(ownerID: "a", record: value, evidence: source, now: date(), calendar: calendar).first)
        source.logs["2026-11-04"] = DailyLog(id: "2026-11-04", date: date(), meals: [Meal(name: "Meal", foodItems: [FoodItem(name: "Food", calories: 400)])])
        XCTAssertFalse(ReminderPolicy.actionIsCurrent(item.candidate, ownerID: "a", preferences: value.preferences, evidence: source, now: date(hour: 21), calendar: calendar))
    }
}

@MainActor final class AccountReminderCoordinatorTests: XCTestCase {
    func testLegacyPreferencesRequireExplicitReviewAndAccountSwitchCancelsAllOwnedRequests() throws {
        let fixture = Fixture(); fixture.defaults.set(true, forKey: "hydrationRemindersEnabled")
        let model = fixture.model(); model.activateAccount("one")
        XCTAssertFalse(model.preferences[.hydration].enabled)
        XCTAssertTrue(model.hasLegacyPreferences)
        var settings = try XCTUnwrap(model.legacyPreferences()); settings.legacyReviewCompleted = true
        XCTAssertTrue(model.savePreferences(settings))
        fixture.owner = "two"; model.activateAccount("two")
        XCTAssertFalse(model.preferences[.hydration].enabled)
        XCTAssertTrue(fixture.center.removed.contains("hydration_0"))
        XCTAssertTrue(fixture.center.removed.contains("weighInReminder"))
    }

    func testUnreadableLedgerCannotBeOverwrittenByFreshDefaults() throws {
        let fixture = Fixture()
        try fixture.store.save(.init(), ownerID: "one")
        let folder = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let original = Data("unreadable-existing-ledger".utf8)
        try original.write(to: file)
        let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true
        XCTAssertFalse(model.savePreferences(value))
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertNotNil(model.errorMessage)
    }

    func testWrongOwnerOrMismatchedIdentityLedgerIsNotProjectedOrOverwritten() throws {
        for wrongOwner in [true, false] {
            let fixture = Fixture()
            var value = ReminderAccountRecord(); value.preferences[.dailyLog].enabled = true
            let owner = wrongOwner ? "other-account" : "one"
            let decision = try XCTUnwrap(ReminderPolicy.decisions(ownerID: owner, record: value,
                evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar).first)
            value.decisions[wrongOwner ? decision.id : "mismatched-key"] = decision
            let drafts = EditorDraftStore(directory: fixture.directory)
            try drafts.save(value, userID: "one", scope: ReminderAccountStore.scope, now: fixture.now)
            XCTAssertThrowsError(try fixture.store.load(ownerID: "one"))
            let model = fixture.model(); model.activateAccount("one")
            XCTAssertTrue(model.decisions.isEmpty)
            XCTAssertNotNil(model.errorMessage)
            XCTAssertFalse(model.savePreferences(.init()))
            XCTAssertEqual(try drafts.load(ReminderAccountRecord.self, userID: "one", scope: ReminderAccountStore.scope)?.value, value)
        }
    }

    func testPermissionDenialPreservesPreferenceWithoutScheduling() async {
        let fixture = Fixture(); fixture.center.status = .denied
        let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true
        XCTAssertTrue(model.savePreferences(value))
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        XCTAssertTrue(model.preferences[.dailyLog].enabled)
        XCTAssertTrue(fixture.center.requests.isEmpty)
        XCTAssertTrue(model.decisions.contains { $0.reason.contains("iOS Settings") })
    }

    func testScheduleReceiptAndHandledPersistWithoutDuplicatingOrLogging() async throws {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true
        XCTAssertTrue(model.savePreferences(value))
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        XCTAssertEqual(fixture.center.requests.count, 7)
        let originalAdds = fixture.center.adds
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        XCTAssertEqual(fixture.center.adds, originalAdds)
        let decision = try XCTUnwrap(model.decisions.first { $0.candidate.target.dayKey == "2026-11-04" })
        let handled = await model.respond(identifier: decision.id, fingerprint: decision.candidate.fingerprint,
            action: AccountReminderCoordinator.handledAction, now: fixture.now)
        XCTAssertTrue(handled)
        XCTAssertEqual(try fixture.store.load(ownerID: "one").decisions[decision.id]?.state, .handled)
        XCTAssertNil(fixture.center.requests[decision.id])
        XCTAssertTrue(fixture.evidence.logs.isEmpty)
    }

    func testSnoozeNeverMovesAFutureReminderEarlierAndStaysInsideBudget() async throws {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true; _ = model.savePreferences(value)
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        let item = try XCTUnwrap(model.decisions.first { $0.candidate.target.dayKey == "2026-11-04" })
        let accepted = await model.respond(identifier: item.id, fingerprint: item.candidate.fingerprint,
            action: AccountReminderCoordinator.snoozeAction, now: fixture.now)
        XCTAssertTrue(accepted)
        XCTAssertEqual(model.decisions.first { $0.id == item.id }?.candidate.fireDate, item.candidate.fireDate.addingTimeInterval(20 * 60))
        XCTAssertEqual(try fixture.store.load(ownerID: "one").reservations.filter { $0.dayKey == "2026-11-04" }.count, 2)
    }

    func testAccountChangeDuringAuthorizationCannotScheduleOldRequests() async {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true; _ = model.savePreferences(value)
        fixture.center.delayStatus = true
        let task = Task { await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar) }
        for _ in 0..<100 where fixture.center.pendingStatus == nil { await Task.yield() }
        let oldStatus = fixture.center.pendingStatus
        fixture.center.delayStatus = false
        fixture.owner = "two"; model.activateAccount("two")
        oldStatus?(.authorized); fixture.center.pendingStatus = nil
        await task.value
        XCTAssertTrue(fixture.center.requests.isEmpty)
    }

    func testOnlyObservedNotificationCenterDeliveryIsLabeledDelivered() async throws {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true; _ = model.savePreferences(value)
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        let item = try XCTUnwrap(model.decisions.first { $0.candidate.target.dayKey == "2026-11-04" })
        XCTAssertEqual(item.state, .scheduled)
        XCTAssertTrue(item.reason.contains("not guaranteed"))
        fixture.center.requests[item.id] = nil
        fixture.center.delivered = [item.id]
        let later = item.candidate.fireDate.addingTimeInterval(60)
        await model.reconcile(evidence: fixture.evidence, now: later, calendar: fixture.calendar)
        XCTAssertEqual(model.decisions.first { $0.id == item.id }?.state, .observedDelivered)
        XCTAssertTrue(model.decisions.first { $0.id == item.id }?.reason.contains("does not mean it was read") == true)
        let added = fixture.center.adds
        await model.reconcile(evidence: fixture.evidence, now: later, calendar: fixture.calendar)
        XCTAssertEqual(fixture.center.adds, added)
        XCTAssertNil(fixture.center.requests[item.id])
    }

    func testOpeningTaskDoesNotRearmItAndUnknownActionDoesNotOpenAnything() async throws {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true; _ = model.savePreferences(value)
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        let item = try XCTUnwrap(model.decisions.first { $0.candidate.target.dayKey == "2026-11-04" })
        let invalid = await model.respond(identifier: item.id, fingerprint: item.candidate.fingerprint, action: "unexpected", now: fixture.now)
        XCTAssertFalse(invalid); XCTAssertNil(model.pendingTarget)
        let opened = await model.respond(identifier: item.id, fingerprint: item.candidate.fingerprint,
            action: UNNotificationDefaultActionIdentifier, now: fixture.now)
        XCTAssertTrue(opened); XCTAssertEqual(model.pendingTarget?.dayKey, "2026-11-04")
        let additions = fixture.center.adds
        await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar)
        XCTAssertEqual(fixture.center.adds, additions)
        XCTAssertEqual(model.decisions.first { $0.id == item.id }?.state, .opened)
        XCTAssertNil(fixture.center.requests[item.id])
    }

    func testHandledResponseCannotBeResurrectedByLateSchedulingCallback() async throws {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences; value[.dailyLog].enabled = true; _ = model.savePreferences(value)
        fixture.center.delayAdd = true
        let scheduling = Task { await model.reconcile(evidence: fixture.evidence, now: fixture.now, calendar: fixture.calendar) }
        for _ in 0..<100 where fixture.center.pendingAdd == nil { await Task.yield() }
        let pending = try XCTUnwrap(fixture.center.pendingAdd)
        let item = try XCTUnwrap(model.decisions.first { $0.id == pending.0.identifier })
        let handled = await model.respond(identifier: item.id, fingerprint: item.candidate.fingerprint,
            action: AccountReminderCoordinator.handledAction, now: fixture.now)
        XCTAssertTrue(handled)
        fixture.center.delayAdd = false
        fixture.center.requests[pending.0.identifier] = pending.0
        pending.1?(nil); fixture.center.pendingAdd = nil
        await scheduling.value
        for _ in 0..<100 where fixture.center.requests[item.id] != nil { await Task.yield() }
        XCTAssertNil(fixture.center.requests[item.id])
        XCTAssertEqual(try fixture.store.load(ownerID: "one").decisions[item.id]?.state, .handled)
        XCTAssertTrue(fixture.evidence.logs.isEmpty)
    }

    func testSnoozeRespectsQuietHoursAndTrackingOnlySuppressesWaterWithoutErasingPreference() async throws {
        let fixture = Fixture(); let model = fixture.model(); model.activateAccount("one")
        var value = model.preferences
        value[.dailyLog].enabled = true; value[.dailyLog].minutes = [21 * 60 + 50]
        value[.hydration].enabled = true
        _ = model.savePreferences(value)
        var evidence = fixture.evidence; evidence.waterGoal = 0
        await model.reconcile(evidence: evidence, now: fixture.now, calendar: fixture.calendar)
        XCTAssertTrue(model.preferences[.hydration].enabled)
        XCTAssertTrue(model.decisions.filter { $0.candidate.target.kind == .hydration }.allSatisfy { $0.state == .suppressed && $0.reason.contains("tracking-only") })
        let item = try XCTUnwrap(model.decisions.first { $0.candidate.target.kind == .dailyLog && $0.candidate.target.dayKey == "2026-11-04" })
        let snoozed = await model.respond(identifier: item.id, fingerprint: item.candidate.fingerprint,
            action: AccountReminderCoordinator.snoozeAction, now: fixture.now)
        XCTAssertFalse(snoozed)
        XCTAssertEqual(try fixture.store.load(ownerID: "one").decisions[item.id]?.candidate.fireDate, item.candidate.fireDate)
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let center = ReminderFakeCenter()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var owner = "one"
        lazy var store = ReminderAccountStore(drafts: EditorDraftStore(directory: directory))
        var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
        var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))! }
        var evidence: ReminderEvidence { .init(goals: .init(calories: 2_000, protein: 120, carbs: 200, fats: 65), waterGoal: 64) }
        func model() -> AccountReminderCoordinator { .init(center: center, store: store, defaults: defaults, currentOwner: { self.owner }) }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }
}

private final class ReminderFakeCenter: UserNotificationScheduling {
    var status = UNAuthorizationStatus.authorized
    var requests: [String: UNNotificationRequest] = [:]
    var removed: [String] = []
    var adds = 0
    var delayStatus = false
    var delayAdd = false
    var pendingAdd: (UNNotificationRequest, ((Error?) -> Void)?)?
    var delivered: [String] = []
    var pendingStatus: ((UNAuthorizationStatus) -> Void)?
    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        if delayStatus { pendingStatus = completion } else { completion(status) }
    }
    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping (Bool, Error?) -> Void) { completion(status == .authorized, nil) }
    func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?) {
        adds += 1
        if delayAdd { pendingAdd = (request, completion) }
        else { requests[request.identifier] = request; completion?(nil) }
    }
    func deliveredRequestIdentifiers(completion: @escaping ([String]) -> Void) { completion(delivered) }
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) { delivered.removeAll { identifiers.contains($0) } }
    func removePendingRequests(withIdentifiers identifiers: [String]) { removed += identifiers; identifiers.forEach { requests[$0] = nil } }
    func setBadgeCount(_ count: Int) {}
    func pendingRequests(completion: @escaping ([UNNotificationRequest]) -> Void) { completion(Array(requests.values)) }
}
