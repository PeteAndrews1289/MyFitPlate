import SwiftUI
import MyFitPlateCore

// "Beat the buffet": log an all-you-can-eat session and watch the à-la-carte value climb
// past what you paid. All math lives in AYCERules (Core, tested); prices are typical US
// menu estimates and every screen says so.

@MainActor
final class AYCESessionManager: ObservableObject {
    @Published private(set) var session: AYCESession?
    @Published private(set) var hasCelebratedBreakEven = false

    @AppStorage("ayceSessionDraft") private var draftData: Data = Data()

    init() {
        restoreDraft()
    }

    func start(cuisine: AYCECuisine, buffetPrice: Double) {
        session = AYCESession(cuisine: cuisine, buffetPrice: buffetPrice)
        hasCelebratedBreakEven = false
        persistDraft()
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
    }

    /// Ends the session and returns it for the summary; the draft is cleared.
    func end() -> AYCESession? {
        let finished = session
        session = nil
        draftData = Data()
        return finished
    }

    func discard() {
        session = nil
        draftData = Data()
    }

    private func celebrateIfJustBrokeEven() {
        guard let session, !hasCelebratedBreakEven,
              AYCERules.breakEvenProgress(session: session) >= 1.0 else { return }
        hasCelebratedBreakEven = true
        HapticManager.instance.notification(.success)
    }

    private func persistDraft() {
        draftData = (try? JSONEncoder().encode(session)) ?? Data()
    }

    private func restoreDraft() {
        guard !draftData.isEmpty,
              let restored = try? JSONDecoder().decode(AYCESession.self, from: draftData) else { return }
        session = restored
        hasCelebratedBreakEven = AYCERules.breakEvenProgress(session: restored) >= 1.0
    }
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
                    AYCEStartView(onStart: { cuisine, price in
                        manager.start(cuisine: cuisine, buffetPrice: price)
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
    let onStart: (AYCECuisine, Double) -> Void

    @State private var cuisine: AYCECuisine = .sushi
    @State private var priceText = ""
    @FocusState private var priceFocused: Bool

    private var price: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: "."))
    }

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
                }

                HStack(spacing: 10) {
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
                            }
                            .frame(maxWidth: .infinity)
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

                Button {
                    if let price, price > 0 {
                        HapticsService.shared.playImpact(style: .medium)
                        onStart(cuisine, price)
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

                Text("Menu prices are typical US estimates, not your restaurant's exact menu.")
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
                    let items = await AYCEPriceService().pricedCatalogItems(for: foods, cuisine: cuisine)
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

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(UIColor.secondarySystemFill))
                                    Capsule()
                                        .fill(Color.brandPrimary)
                                        .frame(width: geometry.size.width * CGFloat(min(progress, 1)))
                                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progress)
                                }
                            }
                            .frame(height: 8)
                            .accessibilityElement()
                            .accessibilityLabel("Break-even progress")
                            .accessibilityValue("\(Int((min(progress, 1) * 100).rounded())) percent")

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

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(AYCECatalog.items(for: session.cuisine)) { item in
                                AYCEItemTile(
                                    item: item,
                                    logged: manager.count(for: item),
                                    onAdd: {
                                        HapticsService.shared.playImpact(style: .light)
                                        manager.add(item)
                                    },
                                    onRemove: { manager.remove(item) }
                                )
                            }
                        }

                        Text("Prices are typical US menu estimates.")
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
}

private struct AYCEItemTile: View {
    let item: AYCECatalogItem
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
                    Text("~\(AYCERules.money(item.restaurantPrice)) · \(Int(item.calories)) cal")
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
        .accessibilityLabel("\(item.name), about \(AYCERules.money(item.restaurantPrice)), \(Int(item.calories)) calories")
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
                    Text(AYCERules.homeCostLine(session: session))
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

                Text("Values are estimates from typical US menu prices.")
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
            }
        }
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
        let mealName = AYCERules.mealName(for: session.cuisine)
        for entry in session.entries {
            dailyLogService.addFoodToLog(
                for: userID,
                date: session.startedAt,
                mealName: mealName,
                foodItem: AYCERules.foodItem(from: entry),
                source: "ayce_session"
            )
        }
        onDone(true)
    }
}
