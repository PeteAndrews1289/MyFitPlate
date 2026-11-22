import MyFitPlateCore
import SwiftUI
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class AYCESessionManager: ObservableObject {
    @Published private(set) var session: AYCESession?
    @Published private(set) var hasCelebratedBreakEven = false
    @Published private(set) var hasCelebratedKitchenWin = false
    @Published private(set) var isSavingDiary = false
    @Published private(set) var message: String?
    @Published private(set) var undoSnapshot: AYCESession?
    @Published private(set) var discardedSession: AYCESession?
    @Published private(set) var personalCatalog = BuffetPersonalCatalog()
    @Published private(set) var sessionHistory: [AYCESession] = []

    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol?
    private let accountUserID: String?
    private let draftStorageKey: String?
    private let scoreboardStorageKey: String?
    private let legacyDraftStorageKey = "ayceSessionDraft"
    private let legacyScoreboardStorageKey = "ayceScoreboard"
    private let managesLiveActivity: Bool
    private var hasUnreadableDraft = false
    private var authObserver: Any?
    private var accountInvalidated = false

    #if canImport(ActivityKit)
    private var liveActivity: Activity<AYCEActivityAttributes>?
    #endif

    init(
        initialSession: AYCESession? = nil,
        restoresDraft: Bool = true,
        managesLiveActivity: Bool = true,
        userDefaults: UserDefaults = .standard,
        authService: AuthServiceProtocol? = nil
    ) {
        let resolvedAuthService = authService ?? DIContainer.shared.authService
        let userID = resolvedAuthService?.currentUserID
        self.userDefaults = userDefaults
        self.authService = resolvedAuthService
        self.accountUserID = userID
        self.draftStorageKey = AccountScopedStorageKey.make(
            prefix: legacyDraftStorageKey,
            userID: userID
        )
        self.scoreboardStorageKey = AccountScopedStorageKey.make(
            prefix: legacyScoreboardStorageKey,
            userID: userID
        )
        self.managesLiveActivity = managesLiveActivity
        migrateLegacyStorageIfNeeded()
        if let userID { discardedSession = try? EditorDraftStore().load(AYCESession.self, userID: userID, scope: "buffet-discarded-session")?.value }
        if let userID {
            do { personalCatalog = try BuffetPersonalCatalogStore(userID: userID).load() } catch { message = "Your private buffet preferences could not be read. The saved file is kept." }
            do { sessionHistory = try EditorDraftStore().load([AYCESession].self, userID: userID, scope: "buffet-session-history")?.value ?? [] } catch { message = "Your buffet history could not be read. Its saved file is kept." }
        }

        if let initialSession {
            session = initialSession.submittedAt == nil ? AYCEStableRoundRules.migrated(initialSession) : initialSession
            hasCelebratedBreakEven = AYCERules.breakEvenProgress(session: initialSession) >= 1
            hasCelebratedKitchenWin = AYCERules.hasBeatenKitchen(session: initialSession)
        } else if restoresDraft {
            restoreDraft()
        }

        #if canImport(ActivityKit)
        if managesLiveActivity, let session, session.endedAt == nil {
            if let activity = Activity<AYCEActivityAttributes>.activities.first(where: {
                $0.activityState == .active && $0.attributes.sessionID == session.id && $0.attributes.accountKey == self.draftStorageKey
            }) {
                liveActivity = activity
            } else {
                startLiveActivity()
            }
        }
        #endif
        if let resolvedAuthService {
            authObserver = resolvedAuthService.observeAuthState { [weak self] userID in
                Task { @MainActor [weak self] in self?.accountDidChange(to: userID) }
            }
        }
    }

    deinit {
        if let authObserver { authService?.removeObserver(authObserver) }
    }

    /// Call from the app's authentication lifecycle as well: a buffet manager may not
    /// exist after a cold launch or when the user signs out from another feature.
    static func invalidateActivities(outsideAccount userID: String?) {
        #if canImport(ActivityKit)
        let activeKey = AccountScopedStorageKey.make(prefix: "ayceSessionDraft", userID: userID)
        for activity in Activity<AYCEActivityAttributes>.activities
        where activity.attributes.accountKey == nil || activity.attributes.accountKey != activeKey {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    private func accountDidChange(to userID: String?) {
        guard userID != accountUserID else { return }
        endLiveActivity()
        if managesLiveActivity { Self.invalidateActivities(outsideAccount: userID) }
        // Keep the original account's disk draft; only its in-memory projection is invalidated.
        accountInvalidated = true
        session = nil; discardedSession = nil; sessionHistory = []; personalCatalog = BuffetPersonalCatalog()
        undoSnapshot = nil; hasCelebratedBreakEven = false; hasCelebratedKitchenWin = false
        isSavingDiary = false
        message = "Account changed. Reopen Buffet meal to load the signed-in account's saved session."
    }

    private var canEdit: Bool {
        isCurrentAccount && !isSavingDiary && session?.endedAt == nil && session?.submittedAt == nil
    }
    var editingAccountID: String? { isCurrentAccount ? accountUserID : nil }

    func start(cuisine: AYCECuisine, buffetPrice: Double, citySlug: String?, restaurantName: String? = nil) {
        guard isCurrentAccount, !hasUnreadableDraft, session == nil, buffetPrice.isFinite, buffetPrice >= 0 else { return }
        let next = AYCEStableRoundRules.migrated(AYCESession(cuisine: cuisine, buffetPrice: buffetPrice, citySlug: citySlug, restaurantName: restaurantName))
        guard persist(next) else { return }
        hasCelebratedBreakEven = false
        hasCelebratedKitchenWin = false
        startLiveActivity()
    }

    func add(_ item: AYCECatalogItem) {
        setQuantity(count(for: item) + 1, for: item)
    }

    func remove(_ item: AYCECatalogItem) {
        setQuantity(max(0, count(for: item) - 1), for: item)
    }

    func count(for item: AYCECatalogItem) -> Double {
        session?.entries.filter { $0.item.id == item.id }.reduce(0) { $0 + $1.count } ?? 0
    }

    func setQuantity(_ quantity: Double, for item: AYCECatalogItem) {
        guard canEdit, let session, let next = AYCEStableRoundRules.changeQuantity(quantity, item: item, in: session) else { return }
        commitEdit(next)
    }

    private var preferences: AYCEPreferences { AYCEPreferences(userID: accountUserID, defaults: userDefaults) }

    func isFavorite(_ item: AYCECatalogItem) -> Bool { isCurrentAccount && preferences.isFavorite(item.id) }
    func toggleFavorite(_ item: AYCECatalogItem) {
        guard isCurrentAccount else { return }
        preferences.toggleFavorite(item.id)
        objectWillChange.send()
    }
    func isHidden(_ item: AYCECatalogItem) -> Bool { personalCatalog.hiddenIDs.contains(item.id) }
    func isRecent(_ item: AYCECatalogItem) -> Bool {
        guard let key = BuffetPersonalCatalog.restaurantKey(session?.restaurantName) else { return false }
        return personalCatalog.restaurantRecents[key]?.contains(item.id) == true
    }
    func toggleHidden(_ item: AYCECatalogItem) {
        updatePersonalCatalog { value in
            if value.hiddenIDs.contains(item.id) { value.hiddenIDs.removeAll { $0 == item.id } } else { value.hiddenIDs.append(item.id) }
        }
    }
    func saveCustomFavorite(_ item: AYCECatalogItem) {
        updatePersonalCatalog { value in
            value.customFavorites.removeAll { $0.id == item.id }; value.customFavorites.append(item)
            value.customFavoriteRestaurants = value.customFavoriteRestaurants ?? [:]
            value.customFavoriteRestaurants?[item.id] = BuffetPersonalCatalog.restaurantKey(session?.restaurantName) ?? "unassigned"
        }
    }
    var restaurantFavorites: [AYCECatalogItem] {
        let key = BuffetPersonalCatalog.restaurantKey(session?.restaurantName) ?? "unassigned"
        return personalCatalog.customFavorites.filter { personalCatalog.customFavoriteRestaurants?[$0.id] == key }
    }
    func setLockScreenPrivacy(_ privateDetails: Bool) {
        guard canEdit, var next = session else { return }
        next.hidesLockScreenDetails = privateDetails
        guard persist(next) else { return }
        endLiveActivity(); startLiveActivity()
    }
    private func updatePersonalCatalog(_ edit: (inout BuffetPersonalCatalog) -> Void) {
        guard isCurrentAccount, let userID = accountUserID else { return }
        var next = personalCatalog; edit(&next)
        do {
            try BuffetPersonalCatalogStore(userID: userID).save(next, replacing: personalCatalog)
            personalCatalog = next
        } catch { message = "Could not keep this private catalog change. Existing preferences are kept." }
    }
    func resolvedItem(_ item: AYCECatalogItem) -> AYCECatalogItem {
        preferences.resolve(item, restaurant: session?.restaurantName)
    }
    func savePortion(_ quantity: Double, item: AYCECatalogItem, rememberCut: Bool) {
        guard canEdit else { return }
        setQuantity(quantity, for: item)
        if rememberCut,
           let pieces = item.piecesPerUnit, let restaurant = session?.restaurantName {
            preferences.rememberCut(pieces, for: item, restaurant: restaurant)
        }
    }
    func finishRound() {
        guard canEdit, let session, let next = AYCEStableRoundRules.finishing(session) else { return }
        commitEdit(next)
    }
    func repeatLastRound(reviewedSession: AYCESession) {
        guard canEdit, let session, session == reviewedSession, let reviewed = AYCEStableRoundRules.completed(AYCEStableRoundRules.migrated(reviewedSession)).last,
              let next = AYCEStableRoundRules.repeating(reviewed, in: session, operationID: UUID().uuidString) else { return }
        commitEdit(next)
    }
    func repeatRound(_ reviewed: AYCEStableRound, operationID: String) {
        guard canEdit, let session, let next = AYCEStableRoundRules.repeating(reviewed, in: session, operationID: operationID) else {
            message = "This round changed after review. Reopen it before repeating."; return
        }
        commitEdit(next)
    }
    func editRound(_ reviewed: AYCEStableRound, entries: [AYCESessionEntry]) -> Bool {
        guard canEdit, let session, let next = AYCEStableRoundRules.replacing(reviewed, with: entries, in: session) else {
            message = "This round changed after review. Your current foods are kept."; return false
        }
        commitEdit(next); return self.session == next
    }
    func undo(_ edit: AYCERoundEdit) {
        guard canEdit, let session, let next = AYCEStableRoundRules.undo(edit, in: session) else {
            message = "These foods changed again, so this undo cannot safely replace them."; return
        }
        _ = persist(next); updateLiveActivity()
    }

    func addReviewed(_ items: [AYCECatalogItem], operationID: String? = nil) {
        guard canEdit, let session, operationID.map({ session.reviewedImportIDs?.contains($0) != true }) != false else { return }
        guard var next = AYCEStableRoundRules.appending(items, in: session) else {
            message = "Review each food's amount, nutrition and optional prices before adding. Your previous meal is kept."
            return
        }
        if let operationID { next.reviewedImportIDs = Array(((session.reviewedImportIDs ?? []) + [operationID]).suffix(200)) }
        commitEdit(next)
    }

    var reviewedEntries: [AYCESessionEntry] {
        session?.entries.filter(\.item.isLocallyPriced) ?? []
    }

    func replaceEntry(_ entryID: String, with item: AYCECatalogItem) {
        guard canEdit, let session, let next = AYCEStableRoundRules.replacingEntry(entryID, item: item, in: session) else { return }
        commitEdit(next)
    }

    func removeEntry(_ entry: AYCESessionEntry) {
        guard canEdit, let session, let next = AYCEStableRoundRules.replacingEntry(entry.id, item: nil, in: session) else { return }
        commitEdit(next)
    }

    func undoLastChange() {
        guard let session, let edit = (session.roundEdits ?? []).last(where: { !(session.undoneRoundEditIDs ?? []).contains($0.id) }) else { return }
        undo(edit)
    }

    @discardableResult
    func end() -> AYCESession? {
        guard canEdit, var next = session, !next.entries.isEmpty else { return nil }
        next.endedAt = Date()
        guard persist(next) else { return nil }
        undoSnapshot = nil
        endLiveActivity()
        return next
    }

    func resume() {
        guard isCurrentAccount, !isSavingDiary, var next = session,
              next.endedAt != nil, next.submittedAt == nil else { return }
        next.endedAt = nil
        guard persist(next) else { return }
        startLiveActivity()
    }

    @discardableResult
    func finishWithoutLogging() -> Bool {
        guard isCurrentAccount, !isSavingDiary, let finished = session,
              finished.endedAt != nil, finished.submittedAt == nil else { return false }
        guard recordCompletedSession(finished) else { return false }
        return discard()
    }

    func logToDiary(using service: DailyLogService, completion: @escaping (Bool) -> Void) {
        guard !isSavingDiary else { completion(false); return }
        guard isCurrentAccount, let userID = accountUserID,
              var next = session, next.endedAt != nil, !next.entries.isEmpty else {
            message = "This session can't be saved right now. Return to the account that started it."
            completion(false)
            return
        }
        let submittedAt = next.submittedAt ?? Date()
        if next.submittedAt == nil {
            next.diaryDate = next.diaryDate ?? Calendar.current.startOfDay(for: next.startedAt)
            next.diaryMealName = next.diaryMealName ?? DailyLogRules.determineMealType(for: next.startedAt)
            next.diaryFoodItems = next.entries.map {
                var food = AYCERules.foodItem(from: $0).normalizedForEstimatedSource("ayce_session")
                food.timestamp = submittedAt
                return food
            }
        }
        next.submittedAt = submittedAt
        let foods = next.diaryFoodItems ?? next.entries.map { AYCERules.foodItem(from: $0) }
        guard next.diaryLoggingDate.timeIntervalSinceReferenceDate.isFinite,
              next.diaryLoggingDate >= .distantPast, next.diaryLoggingDate <= .distantFuture,
              !next.diaryLoggingMealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !foods.isEmpty, Set(foods.map(\.id)).count == foods.count,
              foods.allSatisfy({ !$0.id.isEmpty && [$0.calories, $0.protein, $0.carbs, $0.fats].allSatisfy { $0.isFinite && $0 >= 0 } }) else {
            message = "Review this session's foods and diary destination before logging. Your saved session is kept."
            completion(false)
            return
        }
        guard persist(next) else { completion(false); return }
        isSavingDiary = true
        service.addMealGroupsToLog(
            for: userID, date: next.diaryLoggingDate,
            mealGroups: [(mealName: next.diaryLoggingMealName,
                          foodItems: foods)],
            source: "ayce_session", deduplicateFoodIDs: true
        ) { [weak self] accepted in
            guard let self else { completion(false); return }
            self.isSavingDiary = false
            guard self.isCurrentAccount, self.session?.id == next.id else { completion(false); return }
            guard accepted else {
                self.message = "Couldn't save to your diary. Your session is kept. Retry to finish saving it once."
                completion(false)
                return
            }
            guard self.recordCompletedSession(next) else { completion(false); return }
            self.setStoredData(Data(), forKey: self.draftStorageKey)
            self.session = nil
            self.message = nil
            completion(true)
        }
    }

    @discardableResult
    func updateDiaryDestination(date: Date, mealName: String) -> Bool {
        guard isCurrentAccount, !isSavingDiary, var next = session, next.endedAt != nil, next.submittedAt == nil,
              date.timeIntervalSinceReferenceDate.isFinite, date >= .distantPast, date <= .distantFuture,
              ["Breakfast", "Lunch", "Dinner", "Snack"].contains(mealName) else { return false }
        next.diaryDate = Calendar.current.startOfDay(for: date)
        next.diaryMealName = mealName
        return persist(next)
    }

    func prepareDiaryDestination() {
        guard let session, session.submittedAt == nil else { return }
        if session.diaryDate == nil || session.diaryMealName == nil {
            _ = updateDiaryDestination(date: session.diaryLoggingDate, mealName: session.diaryLoggingMealName)
        }
    }

    var scoreboardRecordLine: String? {
        AYCEScoreboard.recordLine(summary: AYCEScoreboard.summary(of: loadScoreboard()))
    }

    @discardableResult
    func discard() -> Bool {
        guard isCurrentAccount, !isSavingDiary, session?.submittedAt == nil else { return false }
        if let session, let userID = accountUserID {
            do { try EditorDraftStore().save(session, userID: userID, scope: "buffet-discarded-session"); discardedSession = session } catch { message = "Could not retain a recoverable copy. This session is still available."; return false }
        }
        endLiveActivity()
        session = nil
        undoSnapshot = nil
        setStoredData(Data(), forKey: draftStorageKey)
        return true
    }
    func restoreDiscarded() {
        guard isCurrentAccount, session == nil, let discardedSession, persist(discardedSession) else { return }
        if discardedSession.endedAt == nil { startLiveActivity() }
    }
    func clearDiscarded() {
        guard isCurrentAccount, let userID = accountUserID else { return }
        do { try EditorDraftStore().remove(userID: userID, scope: "buffet-discarded-session"); discardedSession = nil } catch { message = "Could not clear this device's discarded-session copy." }
    }

    private func commitEdit(_ next: AYCESession) {
        let previous = session
        guard next != previous, persist(next) else { return }
        undoSnapshot = previous
        if let restaurant = next.restaurantName {
            updatePersonalCatalog { value in
                for entry in next.entries where previous?.entries.contains(entry) != true { value.record(entry.item, restaurant: restaurant) }
            }
        }
        // Accurate recording is the success condition; quantity/value crossings are not rewarded.
        updateLiveActivity()
    }

    @discardableResult
    private func persist(_ next: AYCESession) -> Bool {
        guard isCurrentAccount else { message = "Return to the account that started this session."; return false }
        do {
            let encoded = try JSONEncoder().encode(next)
            setStoredData(encoded, forKey: draftStorageKey)
            session = next
            message = nil
            return true
        } catch {
            message = "Couldn't keep this change. Your previous session is still saved."
            return false
        }
    }

    private func loadScoreboard() -> [AYCESessionRecord] {
        guard let data = storedData(forKey: scoreboardStorageKey) else { return [] }
        return (try? JSONDecoder().decode([AYCESessionRecord].self, from: data)) ?? []
    }

    @discardableResult private func recordCompletedSession(_ finished: AYCESession) -> Bool {
        guard isCurrentAccount, let accountUserID else { return false }
        do {
            var history = try EditorDraftStore().load([AYCESession].self, userID: accountUserID, scope: "buffet-session-history")?.value ?? []
            history.removeAll { $0.id == finished.id }; history.insert(finished, at: 0)
            history = Array(history.prefix(100))
            try EditorDraftStore().save(history, userID: accountUserID, scope: "buffet-session-history")
            sessionHistory = history
        } catch { message = "Your meal is kept, but its device-local history could not be saved. Retry to finish cleanup without adding the foods twice."; return false }
        let records = AYCEScoreboard.appending(
            AYCESessionRecord(session: finished, endedAt: finished.endedAt ?? Date()), to: loadScoreboard()
        )
        if let data = try? JSONEncoder().encode(records) { setStoredData(data, forKey: scoreboardStorageKey) }
        return true
    }

    private func celebrateIfNeeded() {
        guard let session else { return }
        if !hasCelebratedBreakEven, AYCERules.breakEvenProgress(session: session) >= 1 {
            hasCelebratedBreakEven = true
            HapticManager.instance.notification(.success)
        }
        if !hasCelebratedKitchenWin, AYCERules.hasBeatenKitchen(session: session) {
            hasCelebratedKitchenWin = true
            HapticManager.instance.notification(.success)
        }
    }

    private func restoreDraft() {
        guard let data = storedData(forKey: draftStorageKey), !data.isEmpty else { return }
        do {
            let restored = try JSONDecoder().decode(AYCESession.self, from: data)
            session = restored.submittedAt == nil ? AYCEStableRoundRules.migrated(restored) : restored
            hasCelebratedBreakEven = AYCERules.breakEvenProgress(session: restored) >= 1
            hasCelebratedKitchenWin = AYCERules.hasBeatenKitchen(session: restored)
        } catch {
            hasUnreadableDraft = true
            message = "Couldn't read the saved buffet session. It has been kept on this device."
        }
    }

    private var isCurrentAccount: Bool {
        guard !accountInvalidated, let accountUserID else { return false }
        return authService?.currentUserID == accountUserID
    }

    private func storedData(forKey key: String?) -> Data? {
        guard isCurrentAccount, let key else { return nil }
        return userDefaults.data(forKey: key)
    }

    private func setStoredData(_ data: Data, forKey key: String?) {
        guard isCurrentAccount, let key else { return }
        if data.isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(data, forKey: key)
        }
    }

    private func migrateLegacyStorageIfNeeded() {
        guard isCurrentAccount,
              let draftStorageKey,
              let scoreboardStorageKey else { return }
        if userDefaults.data(forKey: draftStorageKey) == nil,
           let legacyDraft = userDefaults.data(forKey: legacyDraftStorageKey) {
            userDefaults.set(legacyDraft, forKey: draftStorageKey)
        }
        if userDefaults.data(forKey: scoreboardStorageKey) == nil,
           let legacyScoreboard = userDefaults.data(forKey: legacyScoreboardStorageKey) {
            userDefaults.set(legacyScoreboard, forKey: scoreboardStorageKey)
        }
        userDefaults.removeObject(forKey: legacyDraftStorageKey)
        userDefaults.removeObject(forKey: legacyScoreboardStorageKey)
    }

    private func startLiveActivity() {
        guard managesLiveActivity else { return }
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let session else { return }
        do {
            liveActivity = try Activity.request(
                attributes: AYCEActivityAttributes(cuisineName: session.hidesLockScreenDetails == true ? "Buffet meal" : session.cuisine.displayName,
                    sessionID: session.id, accountKey: draftStorageKey),
                content: .init(
                    state: activityState(),
                    staleDate: Date().addingTimeInterval(45 * 60)
                )
            )
        } catch {
            AppLog.liveActivity.error(
                "AYCE Live Activity failed to start: \(error.localizedDescription, privacy: .public)"
            )
        }
        #endif
    }

    private func updateLiveActivity() {
        guard managesLiveActivity else { return }
        #if canImport(ActivityKit)
        guard let liveActivity else { return }
        let state = activityState()
        Task {
            await liveActivity.update(
                .init(
                    state: state,
                    staleDate: Date().addingTimeInterval(45 * 60)
                )
            )
        }
        #endif
    }

    private func endLiveActivity() {
        guard managesLiveActivity else { return }
        #if canImport(ActivityKit)
        guard let liveActivity else { return }
        let state = activityState()
        Task {
            await liveActivity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
        #endif
    }

    #if canImport(ActivityKit)
    private func activityState() -> AYCEActivityAttributes.ContentState {
        let value = session.map { AYCERules.totals(for: $0).restaurantValue } ?? 0
        let buffetPrice = session?.buffetPrice ?? 0
        let isBeaten = buffetPrice > 0 && value >= buffetPrice
        let itemCount = session?.entries.reduce(0) { $0 + $1.count } ?? 0
        let statusText = session?.hidesLockScreenDetails == true ? "Open your meal to view details"
            : "\(Int(session.map { AYCERules.totals(for: $0).calories } ?? 0)) calories · Open meal"

        return AYCEActivityAttributes.ContentState(
            buffetPriceText: "Nutrition estimate",
            currentValueText: session?.hidesLockScreenDetails == true ? "Private meal" : "\(Int(session.map { AYCERules.totals(for: $0).calories } ?? 0)) cal",
            itemsCount: session?.hidesLockScreenDetails == true ? 0 : itemCount,
            statusText: statusText,
            isBeaten: false
        )
    }
    #endif
}

@MainActor
struct AYCEFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var manager: AYCESessionManager
    @State private var showingHistory = false

    init(
        initialSession: AYCESession? = nil,
        finishedSession: AYCESession? = nil,
        restoresDraft: Bool = true,
        managesLiveActivity: Bool = true
    ) {
        _manager = StateObject(
            wrappedValue: AYCESessionManager(
                initialSession: finishedSession.map { session in
                    var finished = session
                    finished.endedAt = finished.endedAt ?? Date()
                    return finished
                } ?? initialSession,
                restoresDraft: restoresDraft,
                managesLiveActivity: managesLiveActivity
            )
        )
    }

    var body: some View {
        AppSheetScaffold(
            title: screenTitle,
            subtitle: dynamicTypeSize.isAccessibilitySize ? manager.message : screenSubtitle,
            dismiss: { if !manager.isSavingDiary { dismiss() } }
        ) {
            if let finishedSession = manager.session, finishedSession.endedAt != nil {
                AYCESummaryView(
                    session: finishedSession,
                    manager: manager,
                    showsCelebration: !ScreenshotDemoMode.isEnabled
                ) { logged in
                    if logged {
                        ToastManager.shared.showToast(
                            message: "Buffet session added to your diary."
                        )
                    }
                    dismiss()
                }
            } else if manager.session != nil {
                AYCELiveSessionView(manager: manager) {
                    manager.end()
                }
            } else {
                VStack {
                    if !manager.sessionHistory.isEmpty {
                        Button("Meal history (\(manager.sessionHistory.count))") { showingHistory = true }.frame(minHeight: 44)
                    }
                    if manager.discardedSession != nil {
                        HStack {
                            Button("Restore discarded meal") { manager.restoreDiscarded() }
                            Button("Clear saved copy", role: .destructive) { manager.clearDiscarded() }
                        }.font(.footnote).padding()
                    }
                    AYCEStartView(recordLine: manager.scoreboardRecordLine) { cuisine, price, citySlug, restaurant in
                        manager.start(cuisine: cuisine, buffetPrice: price, citySlug: citySlug, restaurantName: restaurant)
                    }
                    .disabled(manager.message != nil)
                }
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brand)
        .interactiveDismissDisabled(manager.isSavingDiary)
        .sheet(isPresented: $showingHistory) { BuffetSessionHistoryView(sessions: manager.sessionHistory) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_flow")
    }

    private var screenTitle: String {
        if manager.session?.endedAt != nil { return "Buffet Summary" }
        if let session = manager.session { return session.cuisine.displayName }
        return "Buffet meal"
    }

    private var screenSubtitle: String {
        if manager.session?.endedAt != nil {
            return "Review the session before adding it to your diary"
        }
        if let session = manager.session {
            return "\(session.city.name) mid-range value estimates"
        }
        return manager.message ?? "Track estimated menu value as you eat"
    }
}

private struct AYCEStartView: View {
    let recordLine: String?
    let onStart: (AYCECuisine, Double, String?, String?) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cuisine: AYCECuisine = .sushi
    @State private var priceText = ""
    @State private var restaurantName = ""
    private enum StartField: Hashable { case price, restaurant }
    @FocusState private var startField: StartField?
    @AppStorage("ayceCitySlug") private var citySlug = AYCECityIndex.national.slug

    private var price: Double? {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : AYCESessionInputRules.buffetPrice(from: priceText)
    }

    private var selectedCity: AYCECity {
        AYCECityIndex.city(slug: citySlug)
    }

    private var cuisineColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if let recordLine {
                    AppListRow(
                        icon: "trophy.fill",
                        iconColor: AppPalette.achievement,
                        title: "Personal Record",
                        subtitle: recordLine
                    )
                    .appSurface(.quiet, padding: 0)
                    .accessibilityIdentifier("ayce_record")
                }

                cuisinePicker
                sessionDetails
                TextField("Restaurant name (optional)", text: $restaurantName)
                    .focused($startField, equals: .restaurant).submitLabel(.done)
                    .onSubmit { startField = nil }
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("ayce_restaurant")
                Text("Use the same name next time to remember this restaurant’s roll cuts.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                estimateNotice
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppPalette.canvas)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { startField = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AYCEBottomActionBar {
                Button {
                    guard let price else { return }
                    startField = nil
                    HapticsService.shared.playImpact(style: .medium)
                    onStart(
                        cuisine,
                        price,
                        citySlug == AYCECityIndex.national.slug ? nil : citySlug,
                        restaurantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : restaurantName
                    )
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(price == nil)
                .accessibilityIdentifier("ayce_start_button")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_start_screen")
    }

    private var cuisinePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Choose Cuisine",
                subtitle: "The catalog and menu-value estimates adapt to this choice"
            )

            LazyVGrid(columns: cuisineColumns, spacing: AppSpacing.row) {
                ForEach(AYCECuisine.allCases, id: \.self) { option in
                    Button {
                        cuisine = option
                        HapticsService.shared.playImpact(style: .light)
                    } label: {
                        HStack(spacing: AppSpacing.compact) {
                            Text(option.emoji)
                                .font(.system(size: 26))
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(option.displayName)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.text)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                            Image(systemName: cuisine == option ? "checkmark.circle.fill" : "circle")
                                .appFont(size: 18, weight: .semibold)
                                .frame(width: 20)
                                .foregroundStyle(cuisine == option ? AppPalette.brandText : .secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, AppSpacing.group)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control)
                                .stroke(
                                    cuisine == option ? AppPalette.brand : AppPalette.separator,
                                    lineWidth: cuisine == option ? 2 : 1
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: AppRadius.control))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.displayName)
                    .accessibilityAddTraits(cuisine == option ? .isSelected : [])
                }
            }
        }
    }

    private var sessionDetails: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Session Details",
                subtitle: "Paid price is optional. Leave blank to track nutrition without a value comparison."
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Buffet Price")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: AppSpacing.compact) {
                    Text("$")
                        .appTextRole(.metric)
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $priceText)
                        .keyboardType(.decimalPad)
                        .focused($startField, equals: .price)
                        .appTextRole(.metric)
                        .foregroundStyle(AppPalette.text)
                        .accessibilityLabel("Buffet price")
                        .accessibilityIdentifier("ayce_price_field")
                }
                .padding(.horizontal, AppSpacing.group)
                .frame(minHeight: 64)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
            }

            Menu {
                ForEach(AYCECityIndex.pickerOptions) { city in
                    Button(city.name) { citySlug = city.slug }
                }
            } label: {
                AppListRow(
                    icon: "mappin.and.ellipse",
                    iconColor: AppPalette.brand,
                    title: "Pricing Region",
                    subtitle: selectedCity.name,
                    hidesTextFromAccessibility: true
                ) {
                    Image(systemName: "chevron.up.chevron.down")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .appSurface(.quiet, padding: 0)
            .accessibilityLabel("Pricing region, \(selectedCity.name)")
            .accessibilityHint("Changes regional menu-value estimates")
        }
    }

    private var estimateNotice: some View {
        AppListRow(
            icon: "info.circle.fill",
            iconColor: AppPalette.caution,
            title: "Estimated Value",
            subtitle: "Catalog prices represent typical mid-range spots in \(selectedCity.name), not this restaurant's exact menu."
        )
        .appSurface(.quiet, padding: 0)
    }
}

private enum AYCEPlateReviewSource: String, Codable {
    case plateScan
    case manual

    var title: String {
        switch self {
        case .plateScan: "Review Plate Estimate"
        case .manual: "Add Custom Item"
        }
    }

    var subtitle: String {
        switch self {
        case .plateScan: "Nothing joins the session until you confirm every item"
        case .manual: "Enter one local item that is missing from the catalog"
        }
    }

    var isAIEstimated: Bool { self == .plateScan }
}

struct AYCEPlateDraft: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var unit: String
    var calories: String
    var protein: String
    var carbs: String
    var fats: String
    var restaurantPrice: String
    var homeCost: String
    var personalAmount: String? = "1"
    var originalRecognizedName: String?
    var catalogMatch: AYCECatalogItem?
    var acceptedCatalogEvidence: AYCECatalogMatchEvidence?

    init(item: AYCECatalogItem) {
        id = item.id
        name = item.name
        unit = item.unit
        calories = Self.numberText(item.calories)
        protein = Self.numberText(item.protein)
        carbs = Self.numberText(item.carbs)
        fats = Self.numberText(item.fats)
        restaurantPrice = String(format: "%.2f", item.restaurantPrice)
        homeCost = String(format: "%.2f", item.homeCost)
        acceptedCatalogEvidence = item.catalogMatch
        originalRecognizedName = item.catalogMatch?.originalText
    }

    init(
        id: String = "manual_\(UUID().uuidString)",
        name: String = "",
        unit: String = "serving",
        calories: String = "",
        protein: String = "",
        carbs: String = "",
        fats: String = "",
        restaurantPrice: String = "",
        homeCost: String = ""
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fats = fats
        self.restaurantPrice = restaurantPrice
        self.homeCost = homeCost
    }

    func reviewedItem(cuisine: AYCECuisine, isAIEstimated: Bool) -> AYCECatalogItem? {
        guard let calories = Self.number(from: calories),
              let protein = Self.number(from: protein),
              let carbs = Self.number(from: carbs),
              let fats = Self.number(from: fats),
              let restaurantPrice = restaurantPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : Self.number(from: restaurantPrice),
              let homeCost = homeCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : Self.number(from: homeCost) else {
            return nil
        }
        guard let amount = Self.number(from: personalAmount ?? "1"), AYCEPortionRules.isValid(amount) else { return nil }
        guard let reviewed = AYCEPricingRules.reviewedCatalogItem(
            name: name,
            unit: amount == 1 ? unit : "\(amount.formatted()) × \(unit)",
            cuisine: cuisine,
            calories: calories * amount,
            protein: protein * amount,
            carbs: carbs * amount,
            fats: fats * amount,
            restaurantPrice: restaurantPrice * amount,
            homeCost: homeCost * amount,
            isAIEstimated: catalogMatch == nil && isAIEstimated
        ) else { return nil }
        let evidence = catalogMatch.map { AYCECatalogMatchEvidence(item: $0, originalText: originalRecognizedName ?? name, personalAmount: amount) }
            ?? acceptedCatalogEvidence.map { original in var value = original; value.personalAmount *= amount; return value }
        guard evidence?.isValid != false else { return nil }
        return AYCECatalogItem(id: id, cuisine: cuisine, name: reviewed.name, emoji: reviewed.emoji, unit: reviewed.unit,
            calories: reviewed.calories, protein: reviewed.protein, carbs: reviewed.carbs, fats: reviewed.fats,
            restaurantPrice: reviewed.restaurantPrice, homeCost: reviewed.homeCost,
            isAIEstimated: reviewed.isAIEstimated, isLocallyPriced: true,
            catalogMatch: evidence)
    }

    private static func number(from text: String) -> Double? {
        AYCESessionInputRules.decimal(from: text)
    }

    private static func numberText(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

private struct BuffetItemReviewCheckpoint: Codable {
    var operationID: String
    var sessionID: String
    var source: AYCEPlateReviewSource
    var editingEntryID: String?
    var drafts: [AYCEPlateDraft]
}

private struct AYCELiveSessionView: View {
    @ObservedObject var manager: AYCESessionManager
    let onEnd: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingScanner = false
    @State private var isPricingScan = false
    @State private var showingPlateReview = false
    @State private var plateDrafts: [AYCEPlateDraft] = []
    @State private var reviewSource: AYCEPlateReviewSource = .plateScan
    @State private var editingEntryID: String?
    @State private var searchText = ""
    @FocusState private var isSearching: Bool
    @State private var category: String?
    @State private var showsSelected = false
    @State private var portionItem: AYCECatalogItem?
    @State private var showsFavorites = false
    @State private var roundToRepeat: AYCESession?
    @State private var showingRoundHistory = false
    @State private var showingSessionDetails = false
    @State private var catalogCuisine: AYCECuisine?
    @State private var showsRecent = false
    @State private var showsHidden = false
    @State private var reviewOperationID = UUID().uuidString
    @State private var reviewFingerprint: String?
    @State private var reviewStorageError: String?
    @State private var reviewStorageUnreadable = false
    @State private var scanRequestID: UUID?

    private let imageModel = MLImageModel()

    private var visibleReviewedEntries: [AYCESessionEntry] {
        guard category == nil else { return [] }
        let tokens = searchText.split(whereSeparator: \.isWhitespace)
        return manager.reviewedEntries.filter { entry in
            tokens.allSatisfy { entry.item.name.localizedStandardContains(String($0)) }
        }
    }

    var body: some View {
        Group {
            if let session = manager.session {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                        if dynamicTypeSize.isAccessibilitySize { catalogFilters(session) }
                        if !isSearching && searchText.isEmpty {
                            valueStatus(session)
                            roundActions(session)
                            captureActions
                        }
                        if let message = manager.message {
                            Text(message).foregroundStyle(AppPalette.caution)
                                .accessibilityIdentifier("ayce_session_status")
                        }
                        if let reviewStorageError { Text(reviewStorageError).foregroundStyle(AppPalette.caution) }
                        if !plateDrafts.isEmpty && !showingPlateReview {
                            Button("Resume unfinished food review") { showingPlateReview = true }.frame(minHeight: 44)
                        }
                        if (session.roundEdits ?? []).contains(where: { !(session.undoneRoundEditIDs ?? []).contains($0.id) }) {
                            Button("Undo last change") { manager.undoLastChange() }
                                .accessibilityIdentifier("ayce_undo_change")
                        }

                        if !visibleReviewedEntries.isEmpty {
                            reviewedItems
                        }
                        if showsFavorites && !manager.restaurantFavorites.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Private favorites at this restaurant").appTextRole(.control)
                                ForEach(manager.restaurantFavorites) { item in
                                    Button("Add \(item.name) · \(item.unit)") { manager.addReviewed([item]) }.frame(minHeight: 44)
                                }
                                Text("Uses your saved personal serving and nutrition snapshot.").font(.caption).foregroundStyle(.secondary)
                            }.appSurface(.quiet)
                        }

                        catalog(session)
                        estimateFooter(session)
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.section)
                }
                .background(AppPalette.canvas)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top) { catalogControls(session) }
                .safeAreaInset(edge: .bottom) {
                    AYCEBottomActionBar {
                        Button {
                            HapticsService.shared.playImpact(style: .medium)
                            onEnd()
                        } label: {
                            Label("Review session", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(session.entries.isEmpty || isPricingScan)
                        .accessibilityIdentifier("ayce_end_button")
                    }
                }
                .sheet(item: $portionItem) { item in
                    AYCEPortionEditor(item: item, session: session, quantity: manager.count(for: item),
                                      isFavorite: manager.isFavorite(item), onToggleFavorite: { manager.toggleFavorite(item) }) { quantity, adjusted, remember in
                        manager.savePortion(quantity, item: adjusted, rememberCut: remember)
                        portionItem = nil
                    }
                }
                .sheet(item: $roundToRepeat) { reviewed in
                    AYCERepeatRoundReview(session: reviewed, onCancel: { roundToRepeat = nil }) {
                        manager.repeatLastRound(reviewedSession: reviewed)
                        roundToRepeat = nil
                    }
                }
                .sheet(isPresented: $showingRoundHistory) { BuffetRoundHistoryView(manager: manager) }
                .sheet(isPresented: $showingSessionDetails) { sessionDetails(session) }
                .sheet(isPresented: $showingScanner) {
                    ImagePicker(
                        sourceType: UIImagePickerController.isSourceTypeAvailable(.camera)
                            ? .camera
                            : .photoLibrary
                    ) { image in
                        scanPlate(image, cuisine: session.cuisine)
                    }
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showingPlateReview) {
                    AYCEPlateReviewView(
                        drafts: $plateDrafts,
                        cuisine: session.cuisine,
                        source: reviewSource,
                        onCancel: { showingPlateReview = false },
                        onDiscard: discardItemReview,
                        onAdd: finishReview
                    )
                }
                .onAppear(perform: restoreItemReview)
                .onChange(of: plateDrafts) { _, _ in saveItemReview() }
                .onChange(of: showingPlateReview) { _, _ in saveItemReview() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_live_screen")
    }

    private func valueStatus(_ session: AYCESession) -> some View {
        let totals = AYCERules.totals(for: session)
        let round = AYCEStableRoundRules.completed(AYCEStableRoundRules.migrated(session)).count + 1
        return HStack(spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text("Round \(round) · \(session.entries.count) \(session.entries.count == 1 ? "food" : "foods") in your meal")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                Text("\(Int(totals.calories.rounded()).formatted()) cal · \(Int(totals.protein.rounded()).formatted()) g protein")
                    .appTextRole(.control).monospacedDigit().contentTransition(.numericText())
                    .accessibilityIdentifier("ayce_live_totals")
            }
            Spacer(minLength: AppSpacing.compact)
            Menu {
                Button("Round history and corrections", systemImage: "clock.arrow.circlepath") { showingRoundHistory = true }
                    .accessibilityIdentifier("ayce_round_history")
                Button("Value and Lock Screen", systemImage: "slider.horizontal.3") { showingSessionDetails = true }
                if session.entries.isEmpty {
                    Button("Change cuisine") { manager.discard() }.disabled(isPricingScan)
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
            }
            .accessibilityLabel("Buffet session options")
            .accessibilityIdentifier("ayce_session_options")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_live_summary")
    }

    private func sessionDetails(_ session: AYCESession) -> some View {
        let totals = AYCERules.totals(for: session)
        let progress = AYCERules.breakEvenProgress(session: session)
        return NavigationStack {
            Form {
                Section("Meal value") {
                    Text(AYCERules.statusLine(session: session)).appTextRole(.control)
                    Text("Est. menu value \(AYCERules.money(totals.restaurantValue)) · Paid \(AYCERules.money(session.buffetPrice))")
                    AYCEProgressRow(label: "Menu break-even", value: progress,
                                    trailing: "\(Int((max(progress, 0) * 100).rounded()))%")
                    Text(AYCERules.kitchenLine(session: session))
                    Text("Ingredient cost is a rough estimate, not the restaurant's profit or loss.").foregroundStyle(.secondary)
                }
                Section("Lock Screen") {
                    Toggle("Hide meal details", isOn: Binding(get: { manager.session?.hidesLockScreenDetails == true }, set: manager.setLockScreenPrivacy))
                }
                Section("Rounds") {
                    Text("Finish a round to remember its additions. Repeating adds only that round, after your review.")
                        .foregroundStyle(.secondary)
                }
            }.appFormStyle()
            .navigationTitle("Session details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSessionDetails = false } } }
        }
    }

    private func roundActions(_ session: AYCESession) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { finishRoundButton(session); repeatRoundButton(session) }
            VStack(alignment: .leading) { finishRoundButton(session); repeatRoundButton(session) }
        }
        .appTextRole(.secondary)
    }
    private func finishRoundButton(_ session: AYCESession) -> some View {
        Button("Finish round") { manager.finishRound() }
            .buttonStyle(.bordered).frame(minHeight: 44)
            .disabled(AYCEStableRoundRules.current(AYCEStableRoundRules.migrated(session))?.entries.isEmpty != false)
            .accessibilityIdentifier("ayce_finish_round")
    }
    private func repeatRoundButton(_ session: AYCESession) -> some View {
        Button("Repeat last round") { roundToRepeat = session }
            .buttonStyle(.bordered).frame(minHeight: 44)
            .disabled(AYCEStableRoundRules.completed(AYCEStableRoundRules.migrated(session)).last?.entries.isEmpty != false)
            .accessibilityIdentifier("ayce_repeat_round")
    }

    private func catalogControls(_ session: AYCESession) -> some View {
        VStack(spacing: AppSpacing.compact) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search foods or menu names", text: $searchText)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .focused($isSearching).submitLabel(.search)
                    .onSubmit { isSearching = false }
                    .accessibilityIdentifier("ayce_catalog_search")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear buffet search")
                }
            }
            .padding(AppSpacing.row).background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
            if !dynamicTypeSize.isAccessibilitySize { catalogFilters(session) }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.compact)
        .background(AppPalette.canvas)
    }

    private func catalogFilters(_ session: AYCESession) -> some View {
        HStack {
                Menu {
                    Button("All categories") { category = nil; showsFavorites = false; showsRecent = false; showsHidden = false; isSearching = false }
                    Button("Recent at this restaurant") { showsRecent = true; showsFavorites = false; showsHidden = false; category = nil }
                    Button("Hidden foods") { showsHidden = true; showsRecent = false; showsFavorites = false; category = nil }
                    Section("Browse another cuisine — keeps all foods") {
                        ForEach(AYCECuisine.allCases, id: \.self) { cuisine in
                            Button(cuisine.displayName) { catalogCuisine = cuisine; category = nil }
                        }
                    }
                    Button(showsFavorites ? "Show all foods" : "Favorites", systemImage: "star") {
                        showsFavorites.toggle(); category = nil; isSearching = false
                    }
                    ForEach(AYCECatalog.sections(for: catalogCuisine ?? session.cuisine)) { section in
                        Button(section.title.isEmpty ? "Menu" : section.title) { category = section.id; isSearching = false }
                    }
                } label: {
                    Label(showsHidden ? "Hidden foods" : showsRecent ? "Restaurant recents" : showsFavorites ? "Favorites" : category ?? (catalogCuisine ?? session.cuisine).displayName, systemImage: "line.3.horizontal.decrease")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("ayce_category_filter")
                Spacer()
                Button {
                    isSearching = false
                    showsSelected.toggle()
                } label: {
                    Text(showsSelected ? "Show menu" : "Your plate (\(session.entries.count))")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("ayce_plate_filter")
        }
        .appTextRole(.secondary).frame(minHeight: 44)
    }

    @ViewBuilder
    private var captureActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.row) {
                scanButton
                customItemButton
            }
        } else {
            HStack(spacing: AppSpacing.row) {
                scanButton
                customItemButton
            }
        }
    }

    private var scanButton: some View {
        Button {
            if !plateDrafts.isEmpty { showingPlateReview = true } else { showingScanner = true }
        } label: {
            if isPricingScan {
                HStack(spacing: AppSpacing.compact) {
                    ProgressView().controlSize(.small)
                    Text("Reading Plate")
                }
            } else {
                Label("Scan plate", systemImage: "camera.viewfinder")
            }
        }
        .buttonStyle(AppListButtonStyle())
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(isPricingScan)
        .accessibilityIdentifier("ayce_scan_plate_button")
    }

    private var customItemButton: some View {
        Button {
            guard !reviewStorageUnreadable else { return }
            if !plateDrafts.isEmpty { showingPlateReview = true; return }
            reviewSource = .manual
            editingEntryID = nil
            reviewOperationID = UUID().uuidString
            plateDrafts = [AYCEPlateDraft()]
            showingPlateReview = true
        } label: {
            Label("Custom item", systemImage: "plus")
        }
        .buttonStyle(AppListButtonStyle())
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(isPricingScan)
        .accessibilityIdentifier("ayce_custom_item_button")
    }

    private var reviewedItems: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Reviewed Items",
                subtitle: "Scanned and custom entries use the values you confirmed"
            )

            VStack(spacing: 0) {
                ForEach(Array(visibleReviewedEntries.enumerated()), id: \.element.id) { index, entry in
                    AYCEReviewedEntryRow(
                        entry: entry,
                        onEdit: { edit(entry) },
                        onRemove: { manager.removeEntry(entry) }
                    )
                        .contextMenu { Button("Save private restaurant favorite") { manager.saveCustomFavorite(entry.item) } }
                    if index < visibleReviewedEntries.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private func catalog(_ session: AYCESession) -> some View {
        let sections = AYCECatalog.matchingSections(for: catalogCuisine ?? session.cuisine, query: searchText, sectionID: category)
            .compactMap { section -> AYCECatalog.MenuSection? in
                let items = section.items.filter { (!showsSelected || manager.count(for: $0) > 0) && (!showsFavorites || manager.isFavorite($0)) &&
                    (!showsRecent || manager.isRecent($0)) && (showsHidden ? manager.isHidden($0) : !manager.isHidden($0)) }
                    .map { manager.resolvedItem($0) }
                return items.isEmpty ? nil : AYCECatalog.MenuSection(title: section.title, items: items)
            }
        return LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
            if sections.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text(showsSelected ? "No matching foods on your plate" : "No matching foods")
                        .appTextRole(.control)
                    Text("Try another name or category, or add a custom item.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Button("Clear filters") { searchText = ""; category = nil; showsSelected = false; showsFavorites = false }
                }
                .appSurface(.quiet)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ayce_empty_results")
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(title: section.title.isEmpty ? "Menu" : section.title,
                                     subtitle: "\(section.items.count) \(section.items.count == 1 ? "food" : "foods") · Tap a food to adjust your portion")
                    LazyVStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            AYCECatalogItemRow(
                                item: item,
                                displayPrice: AYCERules.unitPrices(for: item, in: session).restaurant,
                                logged: manager.count(for: item),
                                onAdd: {
                                    HapticsService.shared.playImpact(style: .light)
                                    manager.add(item)
                                },
                                onRemove: { manager.remove(item) },
                                onPortion: { portionItem = item }
                            )
                            .contextMenu {
                                Button(manager.isFavorite(item) ? "Remove from favorites" : "Add to favorites", systemImage: "star") { manager.toggleFavorite(item) }
                                Button(manager.isHidden(item) ? "Unhide food" : "Hide food", systemImage: "eye.slash") { manager.toggleHidden(item) }
                            }
                            if index < section.items.count - 1 { Divider().padding(.leading, 68) }
                        }
                    }
                    .appSurface(.quiet, padding: 0)
                }
            }
        }
    }

    private func estimateFooter(_ session: AYCESession) -> some View {
        AppListRow(
            icon: "info.circle.fill",
            iconColor: AppPalette.caution,
            title: "Portions and estimates",
            subtitle: "Log only what you ate. Meat weights are cooked, without bones. Marinades are included in named marinated foods; add dipping sauces separately. Nutrition and prices vary by restaurant."
        )
        .appSurface(.quiet, padding: 0)
    }

    private func scanPlate(_ image: UIImage, cuisine: AYCECuisine) {
        let sessionID = manager.session?.id
        let accountID = manager.editingAccountID
        let request = UUID(); scanRequestID = request
        isPricingScan = true
        imageModel.estimateNutritionFromImage(image: image) { result in
            Task { @MainActor in
                guard manager.editingAccountID == accountID, accountID != nil, manager.session?.id == sessionID,
                      manager.session?.endedAt == nil, scanRequestID == request else { return }
                switch result {
                case .success(let foods) where !foods.isEmpty:
                    let items = await AYCEPriceService().pricedCatalogItems(
                        for: foods,
                        cuisine: cuisine,
                        city: manager.session?.city ?? AYCECityIndex.national
                    )
                    guard manager.session?.id == sessionID, manager.session?.endedAt == nil,
                          manager.editingAccountID == accountID, scanRequestID == request, plateDrafts.isEmpty else {
                        isPricingScan = false
                        return
                    }
                    guard !items.isEmpty else {
                        ToastManager.shared.showToast(
                            message: "No reviewable food was found in that photo."
                        )
                        isPricingScan = false
                        return
                    }
                    reviewSource = .plateScan
                    reviewOperationID = UUID().uuidString
                    editingEntryID = nil
                    plateDrafts = items.map(AYCEPlateDraft.init)
                    showingPlateReview = true
                case .success:
                    ToastManager.shared.showToast(
                        message: "No food was found in that photo. Try a clearer angle."
                    )
                case .failure:
                    ToastManager.shared.showToast(
                        message: "The plate scan did not go through. Try again or add a custom item."
                    )
                }
                isPricingScan = false
            }
        }
    }

    private func edit(_ entry: AYCESessionEntry) {
        guard !reviewStorageUnreadable else { return }
        if !plateDrafts.isEmpty { showingPlateReview = true; return }
        reviewOperationID = UUID().uuidString
        editingEntryID = entry.id
        reviewSource = entry.item.isAIEstimated ? .plateScan : .manual
        plateDrafts = [AYCEPlateDraft(item: entry.item)]
        showingPlateReview = true
    }

    private func finishReview(_ items: [AYCECatalogItem]) {
        guard let session = manager.session, manager.editingAccountID != nil else { return }
        if let editingEntryID, let item = items.first {
            manager.replaceEntry(editingEntryID, with: item)
            ToastManager.shared.showToast(message: "Reviewed item updated.")
        } else {
            manager.addReviewed(items, operationID: reviewOperationID)
            let value = items.reduce(0) { $0 + $1.restaurantPrice }
            ToastManager.shared.showToast(
                message: "Added \(items.count) reviewed \(items.count == 1 ? "item" : "items") · est. \(AYCERules.money(value))"
            )
        }
        guard manager.session != session || manager.session?.reviewedImportIDs?.contains(reviewOperationID) == true else { return }
        guard discardItemReview() else { return }
        self.editingEntryID = nil
        plateDrafts = []
        showingPlateReview = false
    }

    private var itemReviewScope: String? { manager.session.map { "buffet-item-review-\($0.id)" } }
    private func restoreItemReview() {
        guard plateDrafts.isEmpty, let account = manager.editingAccountID, let scope = itemReviewScope else { return }
        do {
            if let saved = try EditorDraftStore().load(BuffetItemReviewCheckpoint.self, userID: account, scope: scope), saved.value.sessionID == manager.session?.id {
                reviewFingerprint = try PlanFingerprint.make(saved.value)
                reviewOperationID = saved.value.operationID; plateDrafts = saved.value.drafts
                reviewSource = saved.value.source; editingEntryID = saved.value.editingEntryID
            }
        } catch { reviewStorageUnreadable = true; reviewStorageError = "This meal's unfinished food review could not be read. Its saved file is kept; other meal foods remain usable." }
    }
    private func saveItemReview() {
        guard !reviewStorageUnreadable, !plateDrafts.isEmpty, let account = manager.editingAccountID,
              let sessionID = manager.session?.id, let scope = itemReviewScope else { return }
        do {
            let stored = try EditorDraftStore().load(BuffetItemReviewCheckpoint.self, userID: account, scope: scope)
            guard try stored.map({ try PlanFingerprint.make($0.value) }) == reviewFingerprint else { throw CocoaError(.fileWriteFileExists) }
            let value = BuffetItemReviewCheckpoint(operationID: reviewOperationID, sessionID: sessionID, source: reviewSource,
                editingEntryID: editingEntryID, drafts: plateDrafts)
            try EditorDraftStore().save(value, userID: account, scope: scope)
            reviewFingerprint = try PlanFingerprint.make(value); reviewStorageError = nil
        } catch { reviewStorageError = "Could not keep this unfinished review. Reopen the meal to recover the latest stored copy before replacing it." }
    }
    @discardableResult private func discardItemReview() -> Bool {
        guard let account = manager.editingAccountID, let scope = itemReviewScope else { return false }
        do {
            if let reviewFingerprint {
                guard try EditorDraftStore().removeIfUnchanged(BuffetItemReviewCheckpoint.self, userID: account, scope: scope, fingerprint: reviewFingerprint) else { throw CocoaError(.fileWriteFileExists) }
            }
            reviewFingerprint = nil; plateDrafts = []; editingEntryID = nil; showingPlateReview = false; return true
        } catch { reviewStorageError = "Foods were kept, but this review copy could not be cleared. Retry close without adding it twice."; return false }
    }
}

private struct AYCEProgressRow: View {
    let label: String
    let value: Double
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(trailing)
                    .appTextRole(.caption)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppPalette.control)
                    Capsule()
                        .fill(AppPalette.brand)
                        .frame(
                            width: geometry.size.width * CGFloat(min(max(value, 0), 1))
                        )
                        .animation(AppMotion.standard, value: value)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(trailing)")
    }
}

private struct AYCECatalogItemRow: View {
    let item: AYCECatalogItem
    let displayPrice: Double
    let logged: Double
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onPortion: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    identity
                    countControl
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    identity
                    Spacer(minLength: AppSpacing.compact)
                    countControl
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_catalog_item_\(item.id)")
    }

    private var identity: some View {
        Button(action: onPortion) {
            HStack(spacing: AppSpacing.row) {
                Text(item.emoji)
                    .font(.system(size: 22))
                    .frame(width: 40, height: 40)
                    .background(
                        AppPalette.surface,
                        in: RoundedRectangle(cornerRadius: AppRadius.control)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Per 1 \(item.unit)")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    Text("Est. \(AYCERules.money(displayPrice)) · \(Int(item.calories.rounded())) cal")
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Adjust portion for \(item.name)")
        .accessibilityValue("Per 1 \(item.unit), \(Int(item.calories.rounded())) calories, estimated menu value \(AYCERules.money(displayPrice))")
        .accessibilityIdentifier("ayce_portion_\(item.id)")
    }

    private var countControl: some View {
        HStack(spacing: 2) {
            Button(action: onRemove) {
                Image(systemName: "minus")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .disabled(logged == 0)
            .accessibilityLabel("Remove one \(item.unit) of \(item.name)")
            .accessibilityIdentifier("ayce_remove_\(item.id)")

            Text(AYCEPortionRules.formatted(logged))
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
                .frame(minWidth: 28)
                .accessibilityHidden(true)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .disabled(logged >= AYCEPortionRules.maximumQuantity)
            .accessibilityLabel("Add one \(item.unit) of \(item.name)")
            .accessibilityIdentifier("ayce_add_\(item.id)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(AYCEPortionRules.formatted(logged)) logged")
    }
}

private struct AYCEReviewedEntryRow: View {
    let entry: AYCESessionEntry
    let onEdit: () -> Void
    let onRemove: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    identity
                    controls
                }
            } else {
                HStack(spacing: AppSpacing.row) {
                    identity
                    Spacer(minLength: AppSpacing.compact)
                    controls
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
    }

    private var identity: some View {
        HStack(spacing: AppSpacing.row) {
            Text(entry.item.emoji)
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(
                    AppPalette.surface,
                    in: RoundedRectangle(cornerRadius: AppRadius.control)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.item.name)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(
                    "\(entry.item.isAIEstimated ? "Reviewed AI estimate" : "User entered") · "
                        + "\(AYCERules.money(entry.item.restaurantPrice))"
                )
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: AppSpacing.compact) {
            Button(action: onEdit) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(AppIconButtonStyle(.brand))
            .accessibilityLabel("Edit \(entry.item.name)")

            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(AppIconButtonStyle(.neutral))
            .accessibilityLabel("Remove \(entry.item.name)")
        }
    }
}

private struct AYCEPlateReviewView: View {
    @Binding var drafts: [AYCEPlateDraft]
    let cuisine: AYCECuisine
    let source: AYCEPlateReviewSource
    let onCancel: () -> Void
    var onDiscard: (() -> Bool)?
    let onAdd: ([AYCECatalogItem]) -> Void

    private var reviewedItems: [AYCECatalogItem] {
        drafts.compactMap {
            $0.reviewedItem(cuisine: cuisine, isAIEstimated: source.isAIEstimated)
        }
    }

    private var canAdd: Bool {
        !drafts.isEmpty && reviewedItems.count == drafts.count
    }

    var body: some View {
        AppSheetScaffold(
            title: source.title,
            subtitle: source.subtitle,
            dismiss: onCancel
        ) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    reviewNotice

                    AppMetricStrip(items: [
                        AppMetricItem(
                            label: "Detected",
                            value: drafts.count.formatted(),
                            accent: AppPalette.brand
                        ),
                        AppMetricItem(
                            label: "Ready",
                            value: reviewedItems.count.formatted(),
                            accent: AppPalette.effort
                        ),
                        AppMetricItem(
                            label: "Est. Value",
                            value: AYCERules.money(
                                reviewedItems.reduce(0) { $0 + $1.restaurantPrice }
                            ),
                            accent: AppPalette.caution
                        )
                    ])
                    .appSurface(.emphasized)
                    .accessibilityIdentifier("ayce_review_summary")

                    if !canAdd {
                        AppListRow(
                            icon: "exclamationmark.triangle.fill",
                            iconColor: AppPalette.caution,
                            title: "Complete Every Item",
                            subtitle: "Add a name and non-negative nutrition. Prices are optional; blank values stay unpriced."
                        )
                        .appSurface(.quiet, padding: 0)
                        .accessibilityIdentifier("ayce_review_validation")
                    }

                    ForEach($drafts) { $draft in
                        AYCEPlateDraftEditor(
                            draft: $draft,
                            canDelete: drafts.count > 1,
                            onDelete: { drafts.removeAll { $0.id == draft.id } }
                        )
                    }
                    Button("Add a missed food or sauce") { drafts.append(AYCEPlateDraft()) }.frame(minHeight: 44)
                    if let onDiscard { Button("Discard only this unfinished review", role: .destructive) { _ = onDiscard() }.frame(minHeight: 44) }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas)
            .safeAreaInset(edge: .bottom) {
                AYCEBottomActionBar {
                    Button {
                        onAdd(reviewedItems)
                    } label: {
                        Label(
                            "Add \(reviewedItems.count.formatted()) "
                                + "\(reviewedItems.count == 1 ? "Item" : "Items")",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!canAdd)
                    .accessibilityIdentifier("ayce_review_add_button")
                }
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_review_screen")
    }

    private var reviewNotice: some View {
        AppListRow(
            icon: source.isAIEstimated ? "wand.and.stars" : "square.and.pencil",
            iconColor: AppPalette.caution,
            title: source.isAIEstimated ? "AI Estimate" : "Custom Entry",
            subtitle: source.isAIEstimated
                ? "Check serving, nutrition, and both value estimates. Photos can miss oils, sauces, or overlapping foods."
                : "These values will be treated as user-entered. Restaurant and home prices still appear as estimates."
        )
        .appSurface(.quiet, padding: 0)
    }
}

private struct AYCEPlateDraftEditor: View {
    @Binding var draft: AYCEPlateDraft
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingCatalogMatch = false

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .center) {
                AppSectionHeader(title: draft.name.isEmpty ? "New Item" : draft.name)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(AppIconButtonStyle(.plain))
                    .accessibilityLabel("Remove item")
                }
            }

            AYCEReviewTextField(title: "Food Name", text: $draft.name)
            AYCEReviewTextField(title: "Serving Unit", text: $draft.unit)
            AYCEReviewNumberField(title: "Personal amount of this unit", text: Binding(get: { draft.personalAmount ?? "1" }, set: { draft.personalAmount = $0 }), unit: "units")
            if let original = draft.originalRecognizedName { Text("Originally recognized: \(original)").font(.caption).foregroundStyle(.secondary) }
            if let matched = draft.catalogMatch { Text("Catalog estimate: \(matched.name). Review the unit; this is not verified restaurant nutrition.").font(.caption) }
            Button("Match to a generic catalog food") { showingCatalogMatch = true }.frame(minHeight: 44)

            AppSectionHeader(
                title: "Estimated Nutrition",
                subtitle: "Values are for one serving"
            )
            LazyVGrid(columns: columns, spacing: AppSpacing.row) {
                AYCEReviewNumberField(title: "Calories", text: $draft.calories, unit: "cal")
                AYCEReviewNumberField(title: "Protein", text: $draft.protein, unit: "g")
                AYCEReviewNumberField(title: "Carbs", text: $draft.carbs, unit: "g")
                AYCEReviewNumberField(title: "Fat", text: $draft.fats, unit: "g")
            }

            AppSectionHeader(
                title: "Estimated Value",
                subtitle: "Restaurant price and approximate grocery cost per serving"
            )
            LazyVGrid(columns: columns, spacing: AppSpacing.row) {
                AYCEReviewNumberField(
                    title: "Restaurant Price",
                    text: $draft.restaurantPrice,
                    prefix: "$"
                )
                AYCEReviewNumberField(
                    title: "Home Cost",
                    text: $draft.homeCost,
                    prefix: "$"
                )
            }
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_review_item_\(draft.id)")
        .sheet(isPresented: $showingCatalogMatch) {
            NavigationStack {
                List {
                    Text("Choosing a match replaces per-unit estimates after your review. Your personal amount is kept; confirm that the new unit matches what you ate.").font(.caption)
                    ForEach(AYCECuisine.allCases, id: \.self) { cuisine in
                        Section(cuisine.displayName) {
                            ForEach(AYCECatalog.sections(for: cuisine).flatMap(\.items)) { item in
                                Button("\(item.name) · \(item.unit) · \(Int(item.calories)) cal") {
                                    let original = draft.originalRecognizedName ?? draft.name, amount = draft.personalAmount
                                    let stableID = draft.id
                                    var selected = AYCEPlateDraft(id: stableID, name: item.name, unit: item.unit,
                                        calories: String(item.calories), protein: String(item.protein), carbs: String(item.carbs), fats: String(item.fats),
                                        restaurantPrice: String(item.restaurantPrice), homeCost: String(item.homeCost))
                                    selected.personalAmount = amount; selected.originalRecognizedName = original; selected.catalogMatch = item
                                    draft = selected; showingCatalogMatch = false
                                }
                            }
                        }
                    }
                }.appFormStyle().buttonStyle(AppListButtonStyle()).navigationTitle("Review catalog match")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingCatalogMatch = false } } }
            }
        }
    }
}

private struct AYCEReviewTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .appTextRole(.body)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, AppSpacing.row)
                .frame(minHeight: 48)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control)
                )
        }
    }
}

private struct AYCEReviewNumberField: View {
    let title: String
    @Binding var text: String
    var prefix: String?
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if let prefix {
                    Text(prefix)
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                }
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .appTextRole(.body)
                if let unit {
                    Text(unit)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.row)
            .frame(minHeight: 48)
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.control)
            )
        }
    }
}

private struct AYCESummaryView: View {
    let session: AYCESession
    @ObservedObject var manager: AYCESessionManager
    let showsCelebration: Bool
    let onDone: (_ logged: Bool) -> Void

    @EnvironmentObject private var dailyLogService: DailyLogService
    @State private var hasAppeared = false
    @State private var confirmsDiscard = false
    @State private var showingCelebration = false

    private var totals: AYCERules.Totals { AYCERules.totals(for: session) }
    private var won: Bool { AYCERules.beatByAmount(session: session) >= 0 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                totalsSummary
                diaryDestination
                sessionItems
                DisclosureGroup("Value details") {
                    VStack(alignment: .leading, spacing: AppSpacing.group) {
                        verdict
                        costComparison
                    }.padding(.top, AppSpacing.row)
                }.tint(AppPalette.text)

                if session.submittedAt == nil {
                    Button("Keep adding foods") { manager.resume() }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .accessibilityIdentifier("ayce_resume_session")
                    Menu("Session options") {
                        Button("Finish without logging") {
                            if manager.finishWithoutLogging() { onDone(false) }
                        }
                        Button("Discard session", role: .destructive) { confirmsDiscard = true }
                    }
                } else {
                    Text("This meal's foods and date are kept together while saving. Retry won't add duplicates.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }

                Text("All values are mid-range estimates for \(session.city.name).")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppPalette.canvas)
        .safeAreaInset(edge: .bottom) {
            AYCEBottomActionBar {
                Text("\(session.diaryLoggingMealName) · \(session.diaryLoggingDate.formatted(date: .abbreviated, time: .omitted))")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("ayce_diary_destination")
                if let message = manager.message {
                    Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("ayce_save_error")
                }
                Button(action: logToDiary) {
                    Label(manager.isSavingDiary ? "Saving meal…" : "Add to diary", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(manager.isSavingDiary || session.entries.isEmpty)
                .accessibilityIdentifier("ayce_log_diary_button")
            }
        }
        .confirmationDialog("Discard this buffet session?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard session", role: .destructive) {
                if manager.discard() { onDone(false) }
            }
        } message: { Text("These foods have not been added to your diary.") }
        .onAppear {
            manager.prepareDiaryDestination()
            withAnimation(AppMotion.standard) {
                hasAppeared = true
            }
            if won, showsCelebration {
                HapticManager.instance.notification(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showingCelebration = true
                }
            }
        }
        .celebrationOverlay(type: .ayceWin, isPresented: $showingCelebration)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ayce_summary_screen")
    }

    private var diaryDestination: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Log to").appTextRole(.caption).foregroundStyle(.secondary)
            if session.submittedAt == nil {
                HStack(spacing: AppSpacing.row) {
                    DatePicker("Diary date", selection: Binding(
                        get: { (manager.session ?? session).diaryLoggingDate },
                        set: { _ = manager.updateDiaryDestination(date: $0, mealName: (manager.session ?? session).diaryLoggingMealName) }
                    ), displayedComponents: .date)
                    .labelsHidden().accessibilityLabel("Diary date")
                    .accessibilityIdentifier("ayce_diary_date")
                    Spacer(minLength: 0)
                    Picker("Meal", selection: Binding(
                        get: { (manager.session ?? session).diaryLoggingMealName },
                        set: { _ = manager.updateDiaryDestination(date: (manager.session ?? session).diaryLoggingDate, mealName: $0) }
                    )) {
                        ForEach(["Breakfast", "Lunch", "Dinner", "Snack"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("ayce_diary_meal")
                }
            } else {
                Text("The submitted foods and destination are kept for safe retry.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
        .disabled(manager.isSavingDiary)
        .appSurface(.quiet)
    }

    private var verdict: some View {
        HStack(alignment: .top, spacing: AppSpacing.group) {
            Image(systemName: won ? "trophy.fill" : "fork.knife")
                .appFont(size: 26, weight: .semibold)
                .foregroundStyle(won ? AppPalette.achievement : AppPalette.brandText)
                .frame(width: 56, height: 56)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.surface)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(AYCERules.verdictHeadline(session: session))
                    .appTextRole(.screenTitle)
                    .foregroundStyle(AppPalette.text)
                if let kitchenWin = AYCERules.kitchenWinLine(session: session) {
                    Text(kitchenWin)
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.brandText)
                }
            }
        }
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .opacity(hasAppeared ? 1 : 0)
    }

    private var totalsSummary: some View {
        AppMetricStrip(items: [
            AppMetricItem(
                label: "Portions",
                value: AYCEPortionRules.formatted(totals.itemCount),
                accent: AppPalette.brand
            ),
            AppMetricItem(
                label: "Calories",
                value: "\(Int(totals.calories.rounded()).formatted()) cal",
                accent: AppPalette.energy
            ),
            AppMetricItem(
                label: "Protein",
                value: "\(Int(totals.protein.rounded()).formatted()) g",
                accent: AppPalette.protein
            )
        ])
        .appSurface(.emphasized)
        .accessibilityIdentifier("ayce_summary_metrics")
    }

    private var costComparison: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Value Comparison",
                subtitle: "Three different ways to estimate the same meal"
            )
            VStack(spacing: 0) {
                summaryRow("You Paid", AYCERules.money(session.buffetPrice), icon: "creditcard.fill")
                Divider().padding(.leading, 68)
                summaryRow(
                    "Menu Value",
                    AYCERules.money(totals.restaurantValue),
                    icon: "menucard.fill"
                )
                Divider().padding(.leading, 68)
                summaryRow("Home Cost", AYCERules.money(totals.homeCost), icon: "house.fill")
                Divider().padding(.leading, 68)
                summaryRow(
                    "Est. ingredients",
                    AYCERules.money(totals.restaurantFoodCost),
                    icon: "takeoutbag.and.cup.and.straw.fill"
                )
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private var sessionItems: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Diary Items",
                subtitle: "These entries will be added together as one meal"
            )
            VStack(spacing: 0) {
                ForEach(Array(session.entries.enumerated()), id: \.element.id) { index, entry in
                    AppListRow(
                        icon: entry.item.isAIEstimated ? "wand.and.stars" : "fork.knife",
                        iconColor: entry.item.isAIEstimated ? AppPalette.caution : AppPalette.brand,
                        title: entry.count != 1
                            ? "\(entry.item.name) ×\(AYCEPortionRules.formatted(entry.count))"
                            : entry.item.name,
                        subtitle: "\(AYCEPortionRules.servingDescription(item: entry.item, quantity: entry.count)) · \(Int(entry.calories.rounded()).formatted()) cal"
                    ) {
                        if entry.item.isAIEstimated {
                            Text("Estimate")
                                .appTextRole(.caption)
                                .foregroundStyle(AppPalette.caution)
                        }
                    }
                    if index < session.entries.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private func summaryRow(_ title: String, _ value: String, icon: String) -> some View {
        AppListRow(icon: icon, iconColor: AppPalette.brand, title: title) {
            Text(value)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
        }
    }

    private func logToDiary() {
        manager.logToDiary(using: dailyLogService) { accepted in
            if accepted { onDone(true) }
        }
    }
}

private struct AYCEPortionEditor: View {
    enum Unit: String, CaseIterable, Identifiable {
        case servings = "Servings", pieces = "Pieces", grams = "Cooked grams"
        var id: String { rawValue }
    }

    let item: AYCECatalogItem
    let session: AYCESession
    let onSave: (Double, AYCECatalogItem, Bool) -> Void
    let onToggleFavorite: () -> Void
    @State private var isFavorite: Bool
    @State private var piecesPerRoll: Int
    @State private var rememberCut = true
    @State private var isShared = false
    @State private var diners = 2
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var unit: Unit
    @State private var amount: String
    @FocusState private var editingAmount: Bool

    init(item: AYCECatalogItem, session: AYCESession, quantity: Double, isFavorite: Bool, onToggleFavorite: @escaping () -> Void,
         onSave: @escaping (Double, AYCECatalogItem, Bool) -> Void) {
        self.item = item
        self.session = session
        self.onSave = onSave
        self.onToggleFavorite = onToggleFavorite
        _isFavorite = State(initialValue: isFavorite)
        _piecesPerRoll = State(initialValue: item.piecesPerUnit ?? 1)
        // Reopening a shared roll must not round 3/8 from 0.375 to the row's display value of 0.38.
        // Start in the concrete measure so pieces and cooked weights need fewer taps.
        let initialUnit: Unit = item.piecesPerUnit != nil ? .pieces : item.cookedGramsPerUnit != nil ? .grams : .servings
        let multiplier = initialUnit == .pieces ? Double(item.piecesPerUnit ?? 1) : item.cookedGramsPerUnit ?? 1
        _unit = State(initialValue: initialUnit)
        _amount = State(initialValue: ((quantity > 0 ? quantity : 1) * multiplier)
            .formatted(.number.precision(.fractionLength(0...12)).grouping(.never)))
    }

    private var units: [Unit] {
        [.servings] + (item.piecesPerUnit == nil ? [] : [.pieces]) + (item.cookedGramsPerUnit == nil ? [] : [.grams])
    }

    private var effectiveItem: AYCECatalogItem {
        guard (item.piecesPerUnit ?? 0) > 1 else { return item }
        return AYCEPortionRules.changingCut(of: item, pieces: piecesPerRoll) ?? item
    }
    private func personalQuantity() -> Double? {
        guard let amount = quantity(in: unit) else { return nil }
        return AYCEPortionRules.personalShare(quantity: amount, diners: isShared ? diners : 1)
    }
    private func quantity(in unit: Unit) -> Double? {
        guard let number = AYCESessionInputRules.decimal(from: amount) else { return nil }
        switch unit {
        case .servings: return AYCEPortionRules.isValid(number) ? number : nil
        case .pieces: return AYCEPortionRules.quantity(pieces: number, item: effectiveItem)
        case .grams: return AYCEPortionRules.quantity(cookedGrams: number, item: item)
        }
    }

    private func show(_ quantity: Double, in unit: Unit) {
        let multiplier: Double
        switch unit {
        case .servings: multiplier = 1
        case .pieces: multiplier = Double(effectiveItem.piecesPerUnit ?? 1)
        case .grams: multiplier = item.cookedGramsPerUnit ?? 1
        }
        amount = (quantity * multiplier).formatted(.number.precision(.fractionLength(0...12)).grouping(.never))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(item.name).fontWeight(.semibold)
                        Spacer()
                        Button {
                            onToggleFavorite(); isFavorite.toggle()
                        } label: { Image(systemName: isFavorite ? "star.fill" : "star") }
                            .buttonStyle(AppIconButtonStyle(.plain))
                            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                            .accessibilityIdentifier("ayce_toggle_favorite")
                    }
                    Text("Catalog portion: 1 \(item.unit)").foregroundStyle(.secondary)
                    if item.cookedGramsPerUnit != nil {
                        Text("Use cooked, edible weight without bones.")
                            .foregroundStyle(.secondary)
                    } else if item.piecesPerUnit != nil {
                        Text("Count the pieces you ate, including your share of a roll.").foregroundStyle(.secondary)
                    }
                }
                if (item.piecesPerUnit ?? 0) > 1 {
                    Section {
                        DisclosureGroup {
                            Stepper("\(piecesPerRoll) pieces per roll", value: $piecesPerRoll, in: 2...24)
                                .accessibilityIdentifier("ayce_roll_cut")
                            Text("The whole roll keeps the same estimated nutrition; adjust this to match how the restaurant cuts it.")
                                .foregroundStyle(.secondary)
                            if let restaurant = session.restaurantName {
                                Toggle("Remember for \(restaurant)", isOn: $rememberCut)
                            }
                        } label: {
                            Text("Roll cut · \(piecesPerRoll) pieces")
                        }
                    }
                }
                if item.cookedGramsPerUnit != nil {
                    Section("Who ate this portion?") {
                        Toggle("Split equally with others", isOn: $isShared)
                            .accessibilityIdentifier("ayce_shared_portion")
                        if isShared {
                            Stepper("\(diners) people, including you", value: $diners, in: 2...20)
                            Text("Enter the whole cooked portion below. Only your equal share is added. For unequal shares, turn this off and enter what you ate.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(isShared ? "Whole shared portion" : "Your total portion") {
                    if units.count > 1 {
                        Picker("Measure in", selection: $unit) {
                            ForEach(units) { Text($0.rawValue).tag($0) }
                        }
                        .accessibilityIdentifier("ayce_portion_unit")
                        .onChange(of: unit) { old, new in show(quantity(in: old) ?? 1, in: new) }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            Text(unit.rawValue)
                            amountInput
                        }
                    } else {
                        HStack {
                            Text(unit.rawValue)
                            amountInput
                        }
                    }
                    HStack {
                        ForEach([0.5, 1, 2], id: \.self) { quantity in
                            Button("\(AYCEPortionRules.formatted(quantity))×") { show(quantity, in: unit) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("\(AYCEPortionRules.formatted(quantity)) \(quantity == 1 ? "serving" : "servings")")
                        }
                    }
                }
                Section {
                    if let quantity = personalQuantity() {
                        Text("Menu value \(AYCERules.money(AYCERules.unitPrices(for: item, in: session).restaurant * quantity))")
                            .foregroundStyle(.secondary)
                    }
                    Text("Generic recipe estimate. Rice, cut, cooking, and sauces can change the result.")
                        .foregroundStyle(.secondary)
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Adjust portion").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingAmount = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                AYCEBottomActionBar {
                    if let quantity = personalQuantity() {
                        VStack(spacing: AppSpacing.compact) {
                            Text("Your portion: " + AYCEPortionRules.servingDescription(item: effectiveItem, quantity: quantity))
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            Text("\(Int((item.calories * quantity).rounded()).formatted()) cal · \(Int((item.protein * quantity).rounded()).formatted()) g protein")
                                .appTextRole(.control).monospacedDigit()
                                .accessibilityIdentifier("ayce_portion_preview")
                        }.frame(maxWidth: .infinity).padding(.bottom, AppSpacing.row)
                    } else {
                        Text("Enter an amount greater than zero, up to 100 servings.")
                            .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                            .padding(.bottom, AppSpacing.row)
                    }
                    Button("Save portion") { if let quantity = personalQuantity() { onSave(quantity, effectiveItem, rememberCut) } }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(personalQuantity() == nil)
                        .accessibilityIdentifier("ayce_save_portion")
                }
            }
        }
    }

    private var amountInput: some View {
        HStack(spacing: AppSpacing.compact) {
            TextField("Amount", text: $amount)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                .focused($editingAmount)
                .accessibilityLabel(unit.rawValue)
                .accessibilityIdentifier("ayce_portion_amount")
            if !amount.isEmpty {
                Button {
                    amount = ""
                    editingAmount = true
                } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(AppIconButtonStyle(.plain))
                    .accessibilityLabel("Clear portion amount")
                    .accessibilityIdentifier("ayce_clear_portion")
            }
        }
    }
}

private struct AYCERepeatRoundReview: View {
    let session: AYCESession
    let onCancel: () -> Void
    let onAdd: () -> Void

    private var entries: [AYCESessionEntry] { session.lastRound ?? [] }
    private var calories: Int { Int(entries.reduce(0) { $0 + $1.calories }.rounded()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Same portions, another round")
                            .appTextRole(.sectionTitle)
                        Text("Review the foods you’ll add to this buffet session.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            HStack(alignment: .top, spacing: AppSpacing.row) {
                                Text(entry.item.emoji)
                                    .font(.system(size: 26))
                                    .frame(width: 44, height: 44)
                                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: AppRadius.control))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.item.name).appTextRole(.control)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(AYCEPortionRules.servingDescription(item: entry.item, quantity: entry.count))
                                        .appTextRole(.secondary).foregroundStyle(.secondary)
                                    Text("\(Int(entry.calories.rounded()).formatted()) cal")
                                        .appTextRole(.secondary).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AppSpacing.row)
                            if index < entries.count - 1 { Divider().padding(.leading, 44 + AppSpacing.row) }
                        }
                    }
                    .appSurface(.quiet, padding: AppSpacing.group)

                    Text("Your previous round stays unchanged. You can undo the addition from the session.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                .padding(AppSpacing.screenHorizontal)
            }
            .background(AppPalette.canvas)
            .navigationTitle("Repeat last round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AYCEBottomActionBar {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Adding to this session").appTextRole(.secondary).foregroundStyle(.secondary)
                        Spacer(minLength: AppSpacing.compact)
                        Text("\(calories.formatted()) cal").appTextRole(.control).monospacedDigit()
                            .accessibilityIdentifier("ayce_repeat_calories")
                    }
                    .padding(.bottom, AppSpacing.row)
                    Button("Add this round", action: onAdd)
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("ayce_confirm_repeat")
                }
            }
        }
    }
}

private struct AYCEBottomActionBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .dynamicTypeSize(.xSmall ... .accessibility1)
        }
        .background(AppPalette.canvas.ignoresSafeArea(edges: .bottom))
    }
}

#if DEBUG
@MainActor
struct AYCEPlateReviewDemoView: View {
    @State private var drafts = [
        AYCEPlateDraft(
            id: "ayce-review-dragon-roll",
            name: "Dragon Roll",
            unit: "roll",
            calories: "480",
            protein: "18",
            carbs: "62",
            fats: "18",
            restaurantPrice: "13.50",
            homeCost: "4.25"
        ),
        AYCEPlateDraft(
            id: "ayce-review-miso-soup",
            name: "Miso Soup",
            unit: "bowl",
            calories: "60",
            protein: "4",
            carbs: "7",
            fats: "2",
            restaurantPrice: "4.50",
            homeCost: "0.85"
        )
    ]

    var body: some View {
        AYCEPlateReviewView(
            drafts: $drafts,
            cuisine: .sushi,
            source: .plateScan,
            onCancel: {},
            onAdd: { _ in }
        )
    }
}
#endif

@MainActor
private struct BuffetRoundHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: AYCESessionManager
    @State private var editingRound: AYCEStableRound?
    var body: some View {
        NavigationStack {
            List {
                if let session = manager.session {
                    Section("Stable rounds · this meal") {
                        ForEach(AYCEStableRoundRules.completed(AYCEStableRoundRules.migrated(session))) { round in
                            Button { editingRound = round } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(round.migrated == true ? "Earlier foods (migrated)" : "Round")
                                    if let date = round.finishedAt { Text(date.formatted(date: .omitted, time: .shortened)).font(.caption) }
                                    Text("\(round.entries.count) \(round.entries.count == 1 ? "food" : "foods") · \(Int(round.calories.rounded())) cal").font(.subheadline)
                                    if round.repeatedFromRoundID != nil { Text("Repeated from a reviewed round").font(.caption) }
                                }
                            }
                        }
                    }
                    Section("Recent changes · retained after relaunch") {
                        ForEach((session.roundEdits ?? []).reversed()) { edit in
                            VStack(alignment: .leading) {
                                Text(edit.title)
                                Text(edit.recordedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                                if session.undoneRoundEditIDs?.contains(edit.id) == true { Text("Undone").font(.caption) } else {
                                    Button("Undo only this change") { manager.undo(edit) }
                                        .frame(minHeight: 44)
                                }
                            }
                        }
                    }
                    Text("Your last 100 round changes stay with this session. Undo keeps other additions; later edits to the same food may need review.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = manager.message { Text(message).foregroundStyle(AppPalette.caution) }
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Rounds and changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $editingRound) { round in BuffetRoundEditor(manager: manager, reviewed: round) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("ayce_round_history_screen")
    }
}

@MainActor
private struct BuffetRoundEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: AYCESessionManager
    let reviewed: AYCEStableRound
    @State private var entries: [AYCESessionEntry]
    @State private var amountTexts: [String: String]
    @State private var repeatOperationID = UUID().uuidString
    @State private var error: String?
    init(manager: AYCESessionManager, reviewed: AYCEStableRound) {
        self.manager = manager; self.reviewed = reviewed
        _entries = State(initialValue: reviewed.entries)
        _amountTexts = State(initialValue: Dictionary(uniqueKeysWithValues: reviewed.entries.map { ($0.id, String($0.count)) }))
    }
    private var parsedEntries: [AYCESessionEntry]? {
        var result: [AYCESessionEntry] = []
        for entry in entries {
            guard let amount = AYCESessionInputRules.decimal(from: amountTexts[entry.id] ?? ""),
                  AYCEPortionRules.isValid(amount, allowsZero: true) else { return nil }
            if amount > 0 { result.append(AYCESessionEntry(id: entry.id, item: entry.item, count: amount)) }
        }
        return result
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal amounts in this round") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.item.name)
                            TextField("Amount", text: Binding(get: { amountTexts[entry.id] ?? "" }, set: { amountTexts[entry.id] = $0 }))
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("\(entry.item.name), \(entry.item.unit)")
                            Text("Unit: \(entry.item.unit) · \(Int(entry.item.calories.rounded())) cal each").font(.caption)
                            Button("Remove from round", role: .destructive) { entries.removeAll { $0.id == entry.id } }.frame(minHeight: 44)
                        }
                    }
                }
                Section {
                    Button("Clear all foods in this round", role: .destructive) { entries = [] }.frame(minHeight: 44)
                    DisclosureGroup("Repeat the original round") {
                        Text("Adds \(Int(reviewed.calories.rounded())) cal as another round. Unsaved corrections above are not included.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        Button("Add this reviewed round again") {
                            let before = manager.session
                            manager.repeatRound(reviewed, operationID: repeatOperationID)
                            if manager.session != before { dismiss() } else { error = manager.message }
                        }.frame(minHeight: 44).disabled(reviewed.entries.isEmpty).accessibilityIdentifier("ayce_round_repeat_reviewed")
                    }
                }
                if let error { Text(error).foregroundStyle(AppPalette.caution) }
            }.appFormStyle().buttonStyle(AppListButtonStyle()).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: AppSpacing.compact) {
                        Text("\(Int(reviewed.calories.rounded())) → \(Int((parsedEntries ?? []).reduce(0) { $0 + $1.calories }.rounded())) cal")
                            .appTextRole(.control).monospacedDigit()
                        Button("Save round corrections") {
                            guard let parsedEntries else { return }
                            if manager.editRound(reviewed, entries: parsedEntries) { dismiss() } else { error = manager.message }
                        }.buttonStyle(AppActionButtonStyle(.primary))
                            .disabled(parsedEntries == nil).accessibilityIdentifier("ayce_round_save")
                    }.padding(.horizontal, AppSpacing.screenHorizontal).padding(.vertical, AppSpacing.row).background(AppPalette.canvas)
                }
                .navigationTitle("Correct a round").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("ayce_round_editor")
    }
}

private struct BuffetSessionHistoryView: View {
    let sessions: [AYCESession]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("Your last 100 buffet receipts on this device. Receipts show what was submitted; later changes appear in your diary.").font(.caption).foregroundStyle(.secondary)
                ForEach(sessions) { session in
                    DisclosureGroup {
                        Text(session.submittedAt == nil ? "Finished without logging" : "Submitted to \(session.diaryLoggingMealName) · \(session.diaryLoggingDate.formatted(date: .abbreviated, time: .omitted))")
                        ForEach(session.entries) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.item.name)
                                Text("\(AYCEPortionRules.servingDescription(item: entry.item, quantity: entry.count)) · \(Int(entry.calories.rounded())) cal").font(.caption)
                            }
                        }
                        Text("Catalog: \(session.catalogVersion ?? "legacy snapshot") · Amounts and estimates remain as reviewed.").font(.caption)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(session.restaurantName ?? session.cuisine.displayName)
                            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(AYCERules.totals(for: session).calories.rounded())) cal").font(.caption)
                        }
                    }
                }
            }.appFormStyle().buttonStyle(AppListButtonStyle()).navigationTitle("Buffet meal receipts").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("ayce_session_history")
    }
}

#if DEBUG
@MainActor
struct BuffetDesignGallery: View {
    let screen: String
    @StateObject private var manager = AYCESessionManager(initialSession: AYCEStableRoundRules.finishing(ScreenshotDemoData.ayceLiveSession) ?? ScreenshotDemoData.ayceLiveSession, restoresDraft: false, managesLiveActivity: false)
    private var session: AYCESession { manager.session ?? ScreenshotDemoData.ayceLiveSession }
    @ViewBuilder var body: some View {
        switch screen {
        case "buffet-sushi-portion", "buffet-kbbq-portion":
            let item = AYCECatalog.item(id: screen == "buffet-sushi-portion" ? "sushi_california_roll" : "kbbq_bulgogi") ?? session.entries[0].item
            AYCEPortionEditor(item: item, session: session, quantity: 1, isFavorite: false, onToggleFavorite: {}, onSave: { _, _, _ in })
        case "buffet-rounds": BuffetRoundHistoryView(manager: manager)
        case "buffet-round-edit":
            if let round = session.rounds?.first { BuffetRoundEditor(manager: manager, reviewed: round) }
        case "buffet-repeat": AYCERepeatRoundReview(session: session, onCancel: {}, onAdd: {})
        default: BuffetSessionHistoryView(sessions: [session])
        }
    }
}
#endif
