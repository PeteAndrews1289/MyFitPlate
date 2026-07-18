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

    private let userDefaults: UserDefaults
    private let authService: AuthServiceProtocol?
    private let accountUserID: String?
    private let draftStorageKey: String?
    private let scoreboardStorageKey: String?
    private let legacyDraftStorageKey = "ayceSessionDraft"
    private let legacyScoreboardStorageKey = "ayceScoreboard"
    private let managesLiveActivity: Bool

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

        if let initialSession {
            session = initialSession
            hasCelebratedBreakEven = AYCERules.breakEvenProgress(session: initialSession) >= 1
            hasCelebratedKitchenWin = AYCERules.hasBeatenKitchen(session: initialSession)
        } else if restoresDraft {
            restoreDraft()
        }

        #if canImport(ActivityKit)
        if managesLiveActivity, session != nil {
            if let activity = Activity<AYCEActivityAttributes>.activities.first(where: {
                $0.activityState == .active
            }) {
                liveActivity = activity
            } else {
                startLiveActivity()
            }
        }
        #endif
    }

    func start(cuisine: AYCECuisine, buffetPrice: Double, citySlug: String?) {
        session = AYCESession(cuisine: cuisine, buffetPrice: buffetPrice, citySlug: citySlug)
        hasCelebratedBreakEven = false
        hasCelebratedKitchenWin = false
        persistDraft()
        startLiveActivity()
    }

    func add(_ item: AYCECatalogItem) {
        guard var session else { return }
        if let index = session.entries.firstIndex(where: { $0.item.id == item.id }) {
            session.entries[index].count += 1
        } else {
            session.entries.append(AYCESessionEntry(item: item, count: 1))
        }
        self.session = session
        completeSessionMutation()
    }

    func remove(_ item: AYCECatalogItem) {
        guard var session,
              let index = session.entries.firstIndex(where: { $0.item.id == item.id }) else {
            return
        }
        let remaining = session.entries[index].count - 1
        if remaining >= 1 {
            session.entries[index].count = remaining
        } else {
            session.entries.remove(at: index)
        }
        self.session = session
        persistDraft()
        updateLiveActivity()
    }

    func count(for item: AYCECatalogItem) -> Int {
        session?.entries.first(where: { $0.item.id == item.id })?.count ?? 0
    }

    func addReviewed(_ items: [AYCECatalogItem]) {
        guard var session else { return }
        for item in items {
            session.entries.append(AYCESessionEntry(item: item, count: 1))
        }
        self.session = session
        completeSessionMutation()
    }

    var reviewedEntries: [AYCESessionEntry] {
        session?.entries.filter(\.item.isLocallyPriced) ?? []
    }

    func replaceEntry(_ entryID: String, with item: AYCECatalogItem) {
        guard var session,
              let index = session.entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }
        session.entries[index].item = item
        self.session = session
        completeSessionMutation()
    }

    func removeEntry(_ entry: AYCESessionEntry) {
        guard var session,
              let index = session.entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        session.entries.remove(at: index)
        self.session = session
        persistDraft()
        updateLiveActivity()
    }

    func end() -> AYCESession? {
        endLiveActivity()
        let finished = session
        if let finished {
            let updated = AYCEScoreboard.appending(
                AYCESessionRecord(session: finished),
                to: loadScoreboard()
            )
            if let encoded = try? JSONEncoder().encode(updated) {
                setStoredData(encoded, forKey: scoreboardStorageKey)
            }
        }
        session = nil
        setStoredData(Data(), forKey: draftStorageKey)
        return finished
    }

    var scoreboardRecordLine: String? {
        AYCEScoreboard.recordLine(summary: AYCEScoreboard.summary(of: loadScoreboard()))
    }

    func discard() {
        endLiveActivity()
        session = nil
        setStoredData(Data(), forKey: draftStorageKey)
    }

    private func completeSessionMutation() {
        celebrateIfNeeded()
        persistDraft()
        updateLiveActivity()
    }

    private func loadScoreboard() -> [AYCESessionRecord] {
        guard let data = storedData(forKey: scoreboardStorageKey) else { return [] }
        return (try? JSONDecoder().decode([AYCESessionRecord].self, from: data)) ?? []
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

    private func persistDraft() {
        setStoredData((try? JSONEncoder().encode(session)) ?? Data(), forKey: draftStorageKey)
    }

    private func restoreDraft() {
        guard let draftData = storedData(forKey: draftStorageKey),
              !draftData.isEmpty,
              let restored = try? JSONDecoder().decode(AYCESession.self, from: draftData) else {
            return
        }
        session = restored
        hasCelebratedBreakEven = AYCERules.breakEvenProgress(session: restored) >= 1
        hasCelebratedKitchenWin = AYCERules.hasBeatenKitchen(session: restored)
    }

    private var isCurrentAccount: Bool {
        guard let accountUserID else { return false }
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
                attributes: AYCEActivityAttributes(cuisineName: session.cuisine.displayName),
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
        let statusText = isBeaten
            ? "Buffet beaten"
            : "\(AYCERules.money(max(0, buffetPrice - value))) to go"

        return AYCEActivityAttributes.ContentState(
            buffetPriceText: AYCERules.money(buffetPrice),
            currentValueText: AYCERules.money(value),
            itemsCount: itemCount,
            statusText: statusText,
            isBeaten: isBeaten
        )
    }
    #endif
}

@MainActor
struct AYCEFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager: AYCESessionManager
    @State private var finishedSession: AYCESession?

    init(
        initialSession: AYCESession? = nil,
        finishedSession: AYCESession? = nil,
        restoresDraft: Bool = true,
        managesLiveActivity: Bool = true
    ) {
        _manager = StateObject(
            wrappedValue: AYCESessionManager(
                initialSession: initialSession,
                restoresDraft: restoresDraft,
                managesLiveActivity: managesLiveActivity
            )
        )
        _finishedSession = State(initialValue: finishedSession)
    }

    var body: some View {
        AppSheetScaffold(
            title: screenTitle,
            subtitle: screenSubtitle,
            dismiss: { dismiss() }
        ) {
            if let finishedSession {
                AYCESummaryView(
                    session: finishedSession,
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
                    finishedSession = manager.end()
                }
            } else {
                AYCEStartView(recordLine: manager.scoreboardRecordLine) { cuisine, price, citySlug in
                    manager.start(cuisine: cuisine, buffetPrice: price, citySlug: citySlug)
                }
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brand)
        .accessibilityIdentifier("ayce_flow")
    }

    private var screenTitle: String {
        if finishedSession != nil { return "Buffet Summary" }
        if let session = manager.session { return session.cuisine.displayName }
        return "Beat the Buffet"
    }

    private var screenSubtitle: String {
        if finishedSession != nil {
            return "Review the session before adding it to your diary"
        }
        if let session = manager.session {
            return "\(session.city.name) mid-range value estimates"
        }
        return "Track estimated menu value as you eat"
    }
}

private struct AYCEStartView: View {
    let recordLine: String?
    let onStart: (AYCECuisine, Double, String?) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cuisine: AYCECuisine = .sushi
    @State private var priceText = ""
    @AppStorage("ayceCitySlug") private var citySlug = AYCECityIndex.national.slug

    private var price: Double? {
        AYCESessionInputRules.buffetPrice(from: priceText)
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
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
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
                estimateNotice
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.section)
        }
        .background(AppPalette.canvas)
        .safeAreaInset(edge: .bottom) {
            AYCEBottomActionBar {
                Button {
                    guard let price else { return }
                    HapticsService.shared.playImpact(style: .medium)
                    onStart(
                        cuisine,
                        price,
                        citySlug == AYCECityIndex.national.slug ? nil : citySlug
                    )
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(price == nil)
                .accessibilityIdentifier("ayce_start_button")
            }
        }
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
                        HStack(spacing: AppSpacing.row) {
                            Text(option.emoji)
                                .font(.system(size: 26))
                                .accessibilityHidden(true)
                            Text(option.displayName)
                                .appTextRole(.control)
                                .foregroundStyle(AppPalette.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: cuisine == option ? "checkmark.circle.fill" : "circle")
                                .appFont(size: 18, weight: .semibold)
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
                subtitle: "Enter the total price you paid before tax and tip"
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

private enum AYCEPlateReviewSource {
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

struct AYCEPlateDraft: Identifiable, Equatable {
    let id: String
    var name: String
    var unit: String
    var calories: String
    var protein: String
    var carbs: String
    var fats: String
    var restaurantPrice: String
    var homeCost: String

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
              let restaurantPrice = Self.number(from: restaurantPrice),
              let homeCost = Self.number(from: homeCost) else {
            return nil
        }
        return AYCEPricingRules.reviewedCatalogItem(
            name: name,
            unit: unit,
            cuisine: cuisine,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            restaurantPrice: restaurantPrice,
            homeCost: homeCost,
            isAIEstimated: isAIEstimated
        )
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

    private let imageModel = MLImageModel()

    var body: some View {
        Group {
            if let session = manager.session {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                        valueStatus(session)
                        captureActions

                        if !manager.reviewedEntries.isEmpty {
                            reviewedItems
                        }

                        catalog(session)
                        estimateFooter(session)
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.section)
                }
                .background(AppPalette.canvas)
                .safeAreaInset(edge: .bottom) {
                    AYCEBottomActionBar {
                        Button {
                            HapticsService.shared.playImpact(style: .medium)
                            onEnd()
                        } label: {
                            Label("End Session", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .accessibilityIdentifier("ayce_end_button")
                    }
                }
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
                        onAdd: finishReview
                    )
                }
            }
        }
        .accessibilityIdentifier("ayce_live_screen")
    }

    private func valueStatus(_ session: AYCESession) -> some View {
        let totals = AYCERules.totals(for: session)
        let menuProgress = AYCERules.breakEvenProgress(session: session)
        let kitchenProgress = totals.restaurantFoodCost / session.buffetPrice

        return VStack(alignment: .leading, spacing: AppSpacing.group) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AYCERules.statusLine(session: session))
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)
                    .contentTransition(.numericText())
                Text(AYCERules.kitchenLine(session: session))
                    .appTextRole(.secondary)
                    .foregroundStyle(
                        AYCERules.hasBeatenKitchen(session: session)
                            ? AppPalette.brand
                            : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Menu Value",
                    value: AYCERules.money(totals.restaurantValue),
                    accent: AppPalette.brand
                ),
                AppMetricItem(
                    label: "You Paid",
                    value: AYCERules.money(session.buffetPrice),
                    accent: AppPalette.achievement
                ),
                AppMetricItem(
                    label: "Calories",
                    value: "\(Int(totals.calories.rounded()).formatted()) cal",
                    accent: AppPalette.energy
                )
            ])

            VStack(spacing: AppSpacing.row) {
                AYCEProgressRow(
                    label: "Menu break-even",
                    value: menuProgress,
                    trailing: "\(Int((max(menuProgress, 0) * 100).rounded()))%"
                )
                AYCEProgressRow(
                    label: "Estimated kitchen spend",
                    value: kitchenProgress,
                    trailing: AYCERules.money(totals.restaurantFoodCost)
                )
            }
        }
        .appSurface(.emphasized)
        .accessibilityIdentifier("ayce_live_summary")
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
            showingScanner = true
        } label: {
            if isPricingScan {
                HStack(spacing: AppSpacing.compact) {
                    ProgressView().controlSize(.small)
                    Text("Reading Plate")
                }
            } else {
                Label("Scan Plate", systemImage: "camera.viewfinder")
            }
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .disabled(isPricingScan)
        .accessibilityIdentifier("ayce_scan_plate_button")
    }

    private var customItemButton: some View {
        Button {
            reviewSource = .manual
            editingEntryID = nil
            plateDrafts = [AYCEPlateDraft()]
            showingPlateReview = true
        } label: {
            Label("Custom Item", systemImage: "plus")
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
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
                ForEach(Array(manager.reviewedEntries.enumerated()), id: \.element.id) { index, entry in
                    AYCEReviewedEntryRow(
                        entry: entry,
                        onEdit: { edit(entry) },
                        onRemove: { manager.removeEntry(entry) }
                    )
                    if index < manager.reviewedEntries.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private func catalog(_ session: AYCESession) -> some View {
        LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
            ForEach(AYCECatalog.sections(for: session.cuisine)) { section in
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    AppSectionHeader(
                        title: section.title.isEmpty ? "Menu" : section.title,
                        subtitle: "Typical \(session.city.name) mid-range estimates"
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            AYCECatalogItemRow(
                                item: item,
                                displayPrice: AYCERules.unitPrices(for: item, in: session).restaurant,
                                logged: manager.count(for: item),
                                onAdd: {
                                    HapticsService.shared.playImpact(style: .light)
                                    manager.add(item)
                                },
                                onRemove: { manager.remove(item) }
                            )
                            if index < section.items.count - 1 {
                                Divider().padding(.leading, 68)
                            }
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
            title: "Value Estimates",
            subtitle: "Catalog prices represent typical mid-range spots in \(session.city.name). Plate estimates stay marked until logged."
        )
        .appSurface(.quiet, padding: 0)
    }

    private func scanPlate(_ image: UIImage, cuisine: AYCECuisine) {
        isPricingScan = true
        imageModel.estimateNutritionFromImage(image: image) { result in
            Task { @MainActor in
                switch result {
                case .success(let foods) where !foods.isEmpty:
                    let items = await AYCEPriceService().pricedCatalogItems(
                        for: foods,
                        cuisine: cuisine,
                        city: manager.session?.city ?? AYCECityIndex.national
                    )
                    guard !items.isEmpty else {
                        ToastManager.shared.showToast(
                            message: "No reviewable food was found in that photo."
                        )
                        isPricingScan = false
                        return
                    }
                    reviewSource = .plateScan
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
        editingEntryID = entry.id
        reviewSource = entry.item.isAIEstimated ? .plateScan : .manual
        plateDrafts = [AYCEPlateDraft(item: entry.item)]
        showingPlateReview = true
    }

    private func finishReview(_ items: [AYCECatalogItem]) {
        if let editingEntryID, let item = items.first {
            manager.replaceEntry(editingEntryID, with: item)
            ToastManager.shared.showToast(message: "Reviewed item updated.")
        } else {
            manager.addReviewed(items)
            let value = items.reduce(0) { $0 + $1.restaurantPrice }
            ToastManager.shared.showToast(
                message: "Added \(items.count) reviewed \(items.count == 1 ? "item" : "items") · est. \(AYCERules.money(value))"
            )
        }
        self.editingEntryID = nil
        plateDrafts = []
        showingPlateReview = false
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
    let logged: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

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
        .accessibilityIdentifier("ayce_catalog_item_\(item.id)")
    }

    private var identity: some View {
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
                Text("Est. \(AYCERules.money(displayPrice)) · \(Int(item.calories.rounded())) cal")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countControl: some View {
        HStack(spacing: 2) {
            Button(action: onRemove) {
                Image(systemName: "minus")
            }
            .buttonStyle(AppIconButtonStyle(.plain))
            .disabled(logged == 0)
            .accessibilityLabel("Remove one \(item.name)")

            Text(logged.formatted())
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
                .frame(minWidth: 28)
                .accessibilityHidden(true)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(AppIconButtonStyle(.brand))
            .accessibilityLabel("Add one \(item.name)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(logged) logged")
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
                            subtitle: "Add a name, non-negative nutrition, and a restaurant price above zero."
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
        .accessibilityIdentifier("ayce_review_item_\(draft.id)")
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
    let showsCelebration: Bool
    let onDone: (_ logged: Bool) -> Void

    @EnvironmentObject private var dailyLogService: DailyLogService
    @State private var hasAppeared = false
    @State private var isLogging = false
    @State private var showingCelebration = false

    private var totals: AYCERules.Totals { AYCERules.totals(for: session) }
    private var won: Bool { AYCERules.beatByAmount(session: session) >= 0 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                verdict
                totalsSummary
                costComparison
                sessionItems

                Button {
                    onDone(false)
                } label: {
                    Label("Discard Session", systemImage: "trash")
                }
                .buttonStyle(AppActionButtonStyle(.ghost))

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
                Button(action: logToDiary) {
                    Label(
                        isLogging ? "Adding to Diary" : "Add to Today's Diary",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(isLogging || session.entries.isEmpty)
                .accessibilityIdentifier("ayce_log_diary_button")
            }
        }
        .onAppear {
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
        .accessibilityIdentifier("ayce_summary_screen")
    }

    private var verdict: some View {
        HStack(alignment: .top, spacing: AppSpacing.group) {
            Image(systemName: won ? "trophy.fill" : "fork.knife")
                .appFont(size: 26, weight: .semibold)
                .foregroundStyle(won ? AppPalette.achievement : AppPalette.brandText)
                .frame(width: 56, height: 56)
                .background(
                    (won ? AppPalette.achievement : AppPalette.brand).opacity(0.10),
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
                label: "Items",
                value: totals.itemCount.formatted(),
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
                    "Kitchen Spend",
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
                        title: entry.count > 1
                            ? "\(entry.item.name) ×\(entry.count)"
                            : entry.item.name,
                        subtitle: "\(Int(entry.calories.rounded()).formatted()) cal"
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
        guard let userID = DIContainer.shared.authService.currentUserID else {
            onDone(false)
            return
        }
        isLogging = true
        dailyLogService.addMealToLog(
            for: userID,
            date: session.startedAt,
            mealName: AYCERules.mealName(for: session.cuisine),
            foodItems: session.entries.map { AYCERules.foodItem(from: $0) },
            source: "ayce_session"
        )
        onDone(true)
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
        .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
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
