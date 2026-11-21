import SwiftUI
import MyFitPlateCore

@MainActor enum ReminderEvidenceLoader {
    static func load(ownerID: String, goals: GoalSettings, fuelStore: TrainingFuelPlanStore, experimentStore: MealExperimentStore? = nil, now: Date = Date(),
                     calendar: Calendar = .current) async -> ReminderEvidence? {
        guard DIContainer.shared.authService.currentUserID == ownerID else { return nil }
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        var logs: [String: DailyLog] = [:], unavailable = Set<String>()
        do {
            for log in try await DIContainer.shared.nutritionRepository.fetchDailyHistory(userID: ownerID, startDate: start, endDate: end) {
                guard let date = LoggingHabitRules.civilDate(for: log, calendar: calendar) else { continue }
                logs[ReminderPolicy.dayKey(date, calendar: calendar)] = log
            }
        } catch {
            for offset in -1..<7 {
                if let date = calendar.date(byAdding: .day, value: offset, to: now) { unavailable.insert(ReminderPolicy.dayKey(date, calendar: calendar)) }
            }
        }
        guard DIContainer.shared.authService.currentUserID == ownerID else { return nil }
        let drafts = EditorDraftStore()
        var pendingWeight = Set<String>(), pendingFood = Set<String>()
        if let draft = try? drafts.load(WeightMeasurementDraft.self, userID: ownerID, scope: "weight-measurement-save")?.value,
           draft.userID == ownerID { pendingWeight.insert(ReminderPolicy.dayKey(draft.date, calendar: calendar)) }
        let reviews = (try? drafts.valuesMatchingScope(MealReviewCheckpoint.self, userID: ownerID,
            scopeForValue: { MealReviewSaveSession.scope(for: $0.source) })) ?? []
        for review in reviews where review.draft.isSubmitted && review.draft.dayContext?.isOwned(by: ownerID) == true {
            pendingFood.insert(review.draft.dayContext!.dayKey)
        }
        let weightDays = Set(goals.weightHistory.filter { $0.weight.isFinite && $0.weight > 0 }.map { ReminderPolicy.dayKey($0.date, calendar: calendar) })
        let plans = fuelStore.history.filter { $0.archivedAt == nil && !fuelStore.conflictingPlanIDs.contains($0.plan.id) }.map(\.plan)
        var evidence = ReminderEvidence(logs: logs, unavailableDays: unavailable, weightDayKeys: weightDays,
            pendingWeightDayKeys: pendingWeight, pendingFoodDayKeys: pendingFood, fuelPlans: plans,
            goals: TodayFuelPlanGoals(calories: goals.calories ?? 0, protein: goals.protein, carbs: goals.carbs, fats: goals.fats), waterGoal: goals.isWaterTrackingOnly ? 0 : goals.waterGoal)
        do {
            evidence.recentWaterAcceptedAt = try ReminderWaterEvidenceStore.shared.recentAcceptedTimes(ownerID: ownerID, logs: logs, now: now)
            let scope = WatchAccountScopeStore().scope(for: ownerID)
            for receipt in try SharedDataManager.shared.waterInbox?.pending(accountScope: scope) ?? []
                where receipt.ounces.isFinite && receipt.ounces > 0 && receipt.capturedAt <= now {
                evidence.pendingWaterDayKeys.insert(ReminderPolicy.dayKey(receipt.capturedAt, calendar: calendar))
            }
        } catch { evidence.waterEvidenceUnavailable = true }
        if AccountReminderCoordinator.shared.preferences[.experimentCheckIn].enabled,
           let experimentStore, experimentStore.userID == ownerID, experimentStore.errorMessage == nil {
            if let sessions = try? await DIContainer.shared.workoutRepository.fetchRecentSessionLogs(userID: ownerID, sinceDays: 3) {
                guard DIContainer.shared.authService.currentUserID == ownerID, experimentStore.userID == ownerID else { return nil }
                evidence.experimentCheckIns = ReminderExperimentEvidence.eligible(ownerID: ownerID,
                    experiments: experimentStore.experiments, sessions: sessions, now: now)
            }
        }
        return evidence
    }
}

struct ReminderTaskView: View {
    let target: ReminderTarget
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var status = NutritionDayStatus.unknown
    @State private var error: String?
    @State private var waterAmount = 8.0
    @State private var submittedWater: Double?
    @State private var operationID = UUID().uuidString
    @State private var openingSearch = false

    var body: some View {
        if target.kind == .experimentCheckIn {
            NavigationStack {
                MealExperimentsView(openCheckIn: true, preferredSessionID: target.experimentSessionID, reminderTarget: target)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            }
        } else if target.kind == .weighIn, let day = target.day() {
            CurrentWeightView(initialDate: day.displayDate).environmentObject(goals)
        } else {
            NavigationStack {
                Form {
                    Section {
                        Text(target.day()?.displayDate.formatted(date: .complete, time: .omitted) ?? target.dayKey)
                            .appTextRole(.control)
                        if target.kind == .hydration {
                            Text("Recorded: \((currentLog?.waterTracker?.totalOunces ?? 0).formatted(.number.precision(.fractionLength(0...1)))) oz")
                            Stepper("Add \(waterAmount.formatted(.number.precision(.fractionLength(0...1)))) oz", value: $waterAmount, in: 1...64, step: 4)
                                .disabled(saving || submittedWater != nil).accessibilityIdentifier("reminder_water_amount")
                            Button(saving ? "Saving…" : "Save water") { saveWater() }
                                .disabled(saving).accessibilityIdentifier("reminder_water_save")
                        } else {
                            Text("\((currentLog?.meals.flatMap(\.foodItems).count ?? 0).formatted()) foods recorded")
                            Button("Add food") { openingSearch = true }.accessibilityIdentifier("reminder_add_food")
                            Picker("How complete is this day?", selection: $status) {
                                ForEach(NutritionDayStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            Button(saving ? "Saving…" : "Save day review") { saveDayReview() }
                                .disabled(saving).accessibilityIdentifier("reminder_day_review_save")
                        }
                    }
                    if let error { Text(error).foregroundStyle(AppPalette.caution) }
                }
                .appFormStyle()
                .navigationTitle(target.kind.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } }
                .onAppear { status = currentLog.map(NutritionDayEvidence.status) ?? .unknown }
                .sheet(isPresented: $openingSearch) {
                    FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, onFoodItemLogged: { openingSearch = false }, searchContext: "reminder_exact_day")
                }
            }.interactiveDismissDisabled(saving)
        }
    }
    private var currentLog: DailyLog? {
        guard dailyLogService.isActiveAccount(target.ownerID), dailyLogService.activelyViewedDayContext?.dayKey == target.dayKey else { return nil }
        return dailyLogService.currentDailyLog
    }
    private var valid: Bool {
        target.isAvailable(ownerID: DIContainer.shared.authService.currentUserID, now: Date())
            && dailyLogService.activelyViewedDayContext?.dayKey == target.dayKey
    }
    private func saveWater() {
        guard valid, let day = target.day() else { error = "This reminder's day or account changed. Reopen the diary before logging."; return }
        saving = true
        if submittedWater == nil { submittedWater = waterAmount }
        dailyLogService.addWaterToLog(for: target.ownerID, amount: submittedWater ?? waterAmount, goalOunces: goals.hydrationTarget(for: day.displayDate, recordedGoal: currentLog?.waterTracker?.goalOunces) ?? 0,
            capturedAt: day.isToday() ? Date() : day.startOfDay, entryID: operationID) { accepted in
                saving = false
                guard DIContainer.shared.authService.currentUserID == target.ownerID else { return }
                if accepted { NotificationCenter.default.post(name: .reminderEvidenceChanged, object: target.ownerID); dismiss() } else { error = "Your submitted water entry is kept for retry; it will not be added twice." }
            }
    }
    private func saveDayReview() {
        guard valid, let day = target.day(), let reviewed = currentLog else { error = "This reminder's day or account changed. Reopen the diary before reviewing."; return }
        saving = true
        dailyLogService.setNutritionDayStatus(status, for: target.ownerID, date: day.startOfDay, reviewedLog: reviewed) { accepted in
            saving = false
            guard DIContainer.shared.authService.currentUserID == target.ownerID else { return }
            if accepted { NotificationCenter.default.post(name: .reminderEvidenceChanged, object: target.ownerID); dismiss() } else { error = "The day review is waiting to save. Retry safely." }
        }
    }
}
