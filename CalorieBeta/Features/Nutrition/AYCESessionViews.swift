import SwiftUI
import MyFitPlateCore
#if canImport(ActivityKit)
import ActivityKit
#endif

// "Beat the buffet": log an all-you-can-eat session and watch the à-la-carte value climb
// past what you paid. All math lives in AYCERules (Core, tested); prices are typical US
// menu estimates and every screen says so.

@MainActor
final class AYCESessionManager: ObservableObject {
    @Published private(set) var session: AYCESession?
    @Published private(set) var hasCelebratedBreakEven = false
    @Published private(set) var hasCelebratedKitchenWin = false

    @AppStorage("ayceSessionDraft") private var draftData: Data = Data()
    @AppStorage("ayceScoreboard") private var scoreboardData: Data = Data()

    #if canImport(ActivityKit)
    private var liveActivity: Activity<AYCEActivityAttributes>?
    #endif

    init() {
        restoreDraft()
        #if canImport(ActivityKit)
        if session != nil {
            if let activity = Activity<AYCEActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
                self.liveActivity = activity
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
        celebrateIfJustBrokeEven()
        persistDraft()
        updateLiveActivity()
    }

    func remove(_ item: AYCECatalogItem) {
        guard var session, let index = session.entries.firstIndex(where: { $0.item.id == item.id }) else { return }
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

    /// Plate-scanned items join as their own one-count entries (unique ids, no merging).
    func addScanned(_ items: [AYCECatalogItem]) {
        guard var session else { return }
        for item in items {
            session.entries.append(AYCESessionEntry(item: item, count: 1))
        }
        self.session = session
        celebrateIfJustBrokeEven()
        persistDraft()
        updateLiveActivity()
    }

    /// Scanned entries appear at the top of a scanned-items strip; catalog tiles keep
    /// their grid. Sorted newest-last so the strip reads in eating order.
    var scannedEntries: [AYCESessionEntry] {
        session?.entries.filter { $0.item.isAIEstimated } ?? []
    }

    func removeEntry(_ entry: AYCESessionEntry) {
        guard var session, let index = session.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        session.entries.remove(at: index)
        self.session = session
        persistDraft()
        updateLiveActivity()
    }

    /// Ends the session and returns it for the summary; the draft is cleared and the
    /// result joins the lifetime scoreboard (empty sessions are ignored by the rules).
    func end() -> AYCESession? {
        endLiveActivity()
        let finished = session
        if let finished {
            let updated = AYCEScoreboard.appending(AYCESessionRecord(session: finished), to: loadScoreboard())
            if let encoded = try? JSONEncoder().encode(updated) {
                scoreboardData = encoded
            }
        }
        session = nil
        draftData = Data()
        return finished
    }

    var scoreboardRecordLine: String? {
        AYCEScoreboard.recordLine(summary: AYCEScoreboard.summary(of: loadScoreboard()))
    }

    private func loadScoreboard() -> [AYCESessionRecord] {
        (try? JSONDecoder().decode([AYCESessionRecord].self, from: scoreboardData)) ?? []
    }

    func discard() {
        endLiveActivity()
        session = nil
        draftData = Data()
    }

    private func celebrateIfJustBrokeEven() {
        guard let session else { return }
        // Two one-time moments, in escalating order: beating the menu, then the rare
        // true win of out-eating the kitchen's own ingredient budget (DESIGN.md 7 —
        // celebrate once, at the moment of reveal).
        if !hasCelebratedBreakEven, AYCERules.breakEvenProgress(session: session) >= 1.0 {
            hasCelebratedBreakEven = true
            HapticManager.instance.notification(.success)
        }
        if !hasCelebratedKitchenWin, AYCERules.hasBeatenKitchen(session: session) {
            hasCelebratedKitchenWin = true
            HapticManager.instance.notification(.success)
        }
    }

    private func persistDraft() {
        draftData = (try? JSONEncoder().encode(session)) ?? Data()
    }

    private func restoreDraft() {
        guard !draftData.isEmpty,
              let restored = try? JSONDecoder().decode(AYCESession.self, from: draftData) else { return }
        session = restored
        hasCelebratedBreakEven = AYCERules.breakEvenProgress(session: restored) >= 1.0
        hasCelebratedKitchenWin = AYCERules.hasBeatenKitchen(session: restored)
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let session else { return }
        do {
            liveActivity = try Activity.request(
                attributes: AYCEActivityAttributes(cuisineName: session.cuisine.displayName),
                content: .init(state: activityState(), staleDate: nil)
            )
        } catch {
            print("AYCE Live Activity failed to start: \(error.localizedDescription)")
        }
        #endif
    }

    private func updateLiveActivity() {
        #if canImport(ActivityKit)
        guard let liveActivity else { return }
        let state = activityState()
        Task {
            await liveActivity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    private func endLiveActivity() {
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
        let value = session != nil ? AYCERules.totals(for: session!).restaurantValue : 0
        let buffetPrice = session?.buffetPrice ?? 0
        let isBeaten = value >= buffetPrice
        let itemsCount = session?.entries.reduce(0) { $0 + $1.count } ?? 0
        
        let buffetPriceText = String(format: "$%.2f", buffetPrice)
        let currentValueText = String(format: "$%.2f", value)
        let statusText = isBeaten ? "🔥 Buffet Beaten!" : String(format: "$%.2f to go", buffetPrice - value)
        
        return AYCEActivityAttributes.ContentState(
            buffetPriceText: buffetPriceText,
            currentValueText: currentValueText,
            itemsCount: itemsCount,
            statusText: statusText,
            isBeaten: isBeaten
        )
    }
    #endif
}

struct AYCEFlowView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AYCESessionManager()
    @State private var finishedSession: AYCESession?

    var body: some View {
        NavigationStack {
            Group {
                if let finished = finishedSession {
                    AYCESummaryView(session: finished, onDone: { logged in
                        if logged {
                            ToastManager.shared.showToast(message: "Buffet session added to your diary.")
                        }
                        dismiss()
                    })
                } else if manager.session != nil {
                    AYCELiveSessionView(manager: manager, onEnd: {
                        finishedSession = manager.end()
                    })
                } else {
                    AYCEStartView(recordLine: manager.scoreboardRecordLine, onStart: { cuisine, price, citySlug in
                        manager.start(cuisine: cuisine, buffetPrice: price, citySlug: citySlug)
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

// MARK: - Start

private struct AYCEStartView: View {
    let recordLine: String?
    let onStart: (AYCECuisine, Double, String?) -> Void

    @State private var cuisine: AYCECuisine = .sushi
    @State private var priceText = ""
    @AppStorage("ayceCitySlug") private var citySlug: String = AYCECityIndex.national.slug
    @FocusState private var priceFocused: Bool

    private var price: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: "."))
    }

    private var selectedCity: AYCECity { AYCECityIndex.city(slug: citySlug) }
    private let cuisineColumns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Beat the buffet")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Log what you eat and see when you've out-eaten the price of admission.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    if let recordLine {
                        Text("Your record: \(recordLine)")
                            .appFont(size: 12, weight: .semibold)
                            .foregroundColor(.brandPrimary)
                            .padding(.top, 2)
                    }
                }

                LazyVGrid(columns: cuisineColumns, spacing: 10) {
                    ForEach(AYCECuisine.allCases, id: \.self) { option in
                        Button {
                            cuisine = option
                            HapticsService.shared.playImpact(style: .light)
                        } label: {
                            VStack(spacing: 6) {
                                Text(option.emoji)
                                    .font(.system(size: 30))
                                    .accessibilityHidden(true)
                                Text(option.displayName)
                                    .appFont(size: 12, weight: .semibold)
                                    .foregroundColor(.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 74)
                            .padding(.vertical, 14)
                            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(cuisine == option ? Color.brandPrimary : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.displayName)
                        .accessibilityAddTraits(cuisine == option ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("What does the buffet cost?")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 6) {
                        Text("$")
                            .appFont(size: 22, weight: .bold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        TextField("32.99", text: $priceText)
                            .keyboardType(.decimalPad)
                            .focused($priceFocused)
                            .appFont(size: 22, weight: .bold)
                    }
                    .padding(14)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pricing region")
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(.textPrimary)
                        Text("Mid-range spots for that market, never the premium ones.")
                            .appFont(size: 11)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    Spacer()
                    Menu {
                        ForEach(AYCECityIndex.pickerOptions) { option in
                            Button(option.name) { citySlug = option.slug }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedCity.name)
                                .appFont(size: 13, weight: .semibold)
                            Image(systemName: "chevron.up.chevron.down")
                                .appFont(size: 10, weight: .bold)
                        }
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.backgroundSecondary, in: Capsule())
                    }
                    .accessibilityLabel("Pricing region: \(selectedCity.name)")
                }

                Button {
                    if let price, price > 0 {
                        HapticsService.shared.playImpact(style: .medium)
                        onStart(cuisine, price, citySlug == AYCECityIndex.national.slug ? nil : citySlug)
                    }
                } label: {
                    Text("Start eating")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background((price ?? 0) > 0 ? Color.brandPrimary : Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled((price ?? 0) <= 0)

                Text("Menu prices are typical mid-range estimates for \(selectedCity.name), not your restaurant's exact menu.")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .onAppear { priceFocused = true }
    }
}

// MARK: - Live session

private struct AYCELiveSessionView: View {
    @ObservedObject var manager: AYCESessionManager
    let onEnd: () -> Void

    @State private var showingScanner = false
    @State private var isPricingScan = false
    private let imageModel = MLImageModel()

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private func handleScannedImage(_ image: UIImage, cuisine: AYCECuisine) {
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
                    manager.addScanned(items)
                    let value = items.reduce(0) { $0 + $1.restaurantPrice }
                    ToastManager.shared.showToast(message: "Added \(items.count) from your plate · about \(AYCERules.money(value))")
                case .success:
                    ToastManager.shared.showToast(message: "Couldn't spot any food in that photo.")
                case .failure:
                    ToastManager.shared.showToast(message: "Plate scan didn't go through. Try the tiles instead.")
                }
                isPricingScan = false
            }
        }
    }

    var body: some View {
        guard let session = manager.session else { return AnyView(EmptyView()) }
        let totals = AYCERules.totals(for: session)
        let progress = AYCERules.breakEvenProgress(session: session)
        let kitchenProgress = session.buffetPrice > 0 ? totals.restaurantFoodCost / session.buffetPrice : 0

        return AnyView(
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Hero: the one question — am I winning yet?
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AYCERules.statusLine(session: session))
                                .appFont(size: 20, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .contentTransition(.numericText())

                            Text(AYCERules.kitchenLine(session: session))
                                .appFont(size: 13, weight: AYCERules.hasBeatenKitchen(session: session) ? .bold : .semibold)
                                .foregroundColor(AYCERules.hasBeatenKitchen(session: session) ? .brandPrimary : Color(UIColor.secondaryLabel))

                            VStack(spacing: 7) {
                                progressRow(
                                    label: "Menu value",
                                    value: progress,
                                    trailing: "\(Int((min(progress, 1) * 100).rounded()))%"
                                )
                                progressRow(
                                    label: "Kitchen spend",
                                    value: kitchenProgress,
                                    trailing: AYCERules.money(totals.restaurantFoodCost)
                                )
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Break-even progress")
                            .accessibilityValue("Menu \(Int((min(progress, 1) * 100).rounded())) percent. Kitchen spend \(AYCERules.money(totals.restaurantFoodCost)).")

                            Text("\(AYCERules.money(totals.restaurantValue)) of the \(AYCERules.money(session.buffetPrice)) you paid · \(Int(totals.calories.rounded()).formatted()) cal")
                                .appFont(size: 12)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .monospacedDigit()
                        }
                        .asCard()

                        Button {
                            showingScanner = true
                        } label: {
                            HStack(spacing: 8) {
                                if isPricingScan {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Pricing your plate")
                                        .appFont(size: 14, weight: .semibold)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .appFont(size: 14, weight: .semibold)
                                    Text("Scan your plate")
                                        .appFont(size: 14, weight: .semibold)
                                }
                            }
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPricingScan)
                        .accessibilityLabel("Scan your plate with the camera")

                        if !manager.scannedEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("From your plate")
                                    .appFont(size: 12, weight: .semibold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                ForEach(manager.scannedEntries) { entry in
                                    HStack(spacing: 8) {
                                        Text(entry.item.emoji)
                                            .font(.system(size: 16))
                                            .accessibilityHidden(true)
                                        Text(entry.item.name)
                                            .appFont(size: 13, weight: .semibold)
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("~\(AYCERules.money(entry.item.restaurantPrice))")
                                            .appFont(size: 12)
                                            .foregroundColor(Color(UIColor.secondaryLabel))
                                            .monospacedDigit()
                                        Button {
                                            manager.removeEntry(entry)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .appFont(size: 15)
                                                .foregroundColor(Color(UIColor.tertiaryLabel))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove \(entry.item.name)")
                                    }
                                }
                            }
                            .asCard()
                        }

                        ForEach(AYCECatalog.sections(for: session.cuisine)) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if !section.title.isEmpty {
                                    Text(section.title)
                                        .appFont(size: 13, weight: .bold)
                                        .foregroundColor(Color(UIColor.secondaryLabel))
                                        .padding(.top, 2)
                                }

                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(section.items) { item in
                                        AYCEItemTile(
                                            item: item,
                                            displayPrice: AYCERules.unitPrices(for: item, in: session).restaurant,
                                            logged: manager.count(for: item),
                                            onAdd: {
                                                HapticsService.shared.playImpact(style: .light)
                                                manager.add(item)
                                            },
                                            onRemove: { manager.remove(item) }
                                        )
                                    }
                                }
                            }
                        }

                        Text("Prices are typical mid-range estimates for \(session.city.name).")
                            .appFont(size: 11)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding()
                    .padding(.bottom, 8)
                }

                Button {
                    HapticsService.shared.playImpact(style: .medium)
                    onEnd()
                } label: {
                    Text("End session")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("\(session.cuisine.emoji) \(session.cuisine.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingScanner) {
                ImagePicker(
                    sourceType: UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary,
                    onImagePicked: { image in
                        handleScannedImage(image, cuisine: session.cuisine)
                    }
                )
                .ignoresSafeArea()
            }
        )
    }

    private func progressRow(label: String, value: Double, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Spacer()
                Text(trailing)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(UIColor.secondarySystemFill))
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
                }
            }
            .frame(height: 7)
        }
    }
}

private struct AYCEItemTile: View {
    let item: AYCECatalogItem
    let displayPrice: Double
    let logged: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.emoji)
                        .font(.system(size: 26))
                        .frame(width: 40, height: 40)
                        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)

                    Spacer(minLength: 4)

                    if logged >= 1 {
                        Text("×\(logged)")
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.brandPrimary, in: Capsule())
                            .contentTransition(.numericText())
                    }
                }

                Text(item.name)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack {
                    Text("~\(AYCERules.money(displayPrice)) · \(Int(item.calories)) cal")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if logged >= 1 {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                                .appFont(size: 16)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove one \(item.name)")
                    }
                }
            }
            .padding(10)
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), about \(AYCERules.money(displayPrice)), \(Int(item.calories)) calories")
        .accessibilityValue(logged >= 1 ? "\(logged) logged" : "")
        .accessibilityHint("Adds one")
    }
}

// MARK: - Summary

private struct AYCESummaryView: View {
    let session: AYCESession
    let onDone: (_ logged: Bool) -> Void

    @EnvironmentObject var dailyLogService: DailyLogService
    @State private var hasAppeared = false
    @State private var isLogging = false
    @State private var showingCelebration = false

    private var totals: AYCERules.Totals { AYCERules.totals(for: session) }
    private var won: Bool { AYCERules.beatByAmount(session: session) >= 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(won ? "🏆" : "🍽️")
                        .font(.system(size: 44))
                        .accessibilityHidden(true)
                    Text(AYCERules.verdictHeadline(session: session))
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)
                    if let kitchenWin = AYCERules.kitchenWinLine(session: session) {
                        Text(kitchenWin)
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(.brandPrimary)
                    }
                    Text(AYCERules.homeCostLine(session: session))
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text(AYCERules.ingredientCostLine(session: session))
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .scaleEffect(hasAppeared ? 1 : 0.92)
                .opacity(hasAppeared ? 1 : 0)

                VStack(spacing: 0) {
                    summaryRow("You paid", AYCERules.money(session.buffetPrice))
                    Divider()
                    summaryRow("À-la-carte value", AYCERules.money(totals.restaurantValue))
                    Divider()
                    summaryRow("Items", "\(totals.itemCount)")
                    Divider()
                    summaryRow("Calories", "\(Int(totals.calories.rounded()).formatted()) cal")
                    Divider()
                    summaryRow("Protein", "\(Int(totals.protein.rounded())) g")
                }
                .asCard()

                Button {
                    logToDiary()
                } label: {
                    Text(isLogging ? "Adding…" : "Add to today's diary")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLogging || session.entries.isEmpty)

                Button {
                    onDone(false)
                } label: {
                    Text("Discard session")
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Text("Values are mid-range estimates for \(session.city.name).")
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Session over")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                hasAppeared = true
            }
            if won {
                HapticManager.instance.notification(.success)
                if AYCERules.kitchenWinLine(session: session) != nil || won {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingCelebration = true
                    }
                }
            }
        }
        .celebrationOverlay(type: .ayceWin, isPresented: $showingCelebration)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Spacer()
            Text(value)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    private func logToDiary() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            onDone(false)
            return
        }
        isLogging = true
        // One batched write. Looping addFoodToLog races itself (each call fetches the
        // same original log, last save wins) and exactly one buffet item survived.
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
