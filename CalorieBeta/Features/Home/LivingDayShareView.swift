import MyFitPlateCore
import SwiftUI
import UIKit

final class PrivateDayShareCapture: Identifiable {
    let id = UUID()
    let ownerID: String
    let snapshot: LivingDaySnapshot
    let calendar: Calendar
    let log: DailyLog?
    let weightPounds: Double?
    let metric: Bool

    init(ownerID: String, snapshot: LivingDaySnapshot, calendar: Calendar, log: DailyLog?, weightPounds: Double?, metric: Bool) {
        self.ownerID = ownerID
        self.snapshot = snapshot
        self.calendar = calendar
        self.log = log
        self.weightPounds = weightPounds
        self.metric = metric
    }
}

struct LivingDayShareOptionsView: View {
    let capture: PrivateDayShareCapture
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var options = LivingDayPrivateShare.Options()
    @State private var caption = ""
    @State private var invalidated = false
    @State private var authObserver: Any?
    @State private var observedAuth: (any AuthServiceProtocol)?
    @State private var shareImage: UIImage?
    @State private var showingActivity = false
    @State private var exportDocument: LivingDayPrivateShare?
    @State private var exportImage: UIImage?

    private var document: LivingDayPrivateShare {
        let log = capture.log.flatMap { capture.calendar.isDate($0.date, inSameDayAs: capture.snapshot.date) ? $0 : nil }
        return LivingDayPrivateShare(snapshot: capture.snapshot, options: options,
                                    foodNames: log?.meals.flatMap(\.foodItems).map(\.name) ?? [],
                                    weightPounds: capture.weightPounds, metric: capture.metric,
                                    dayStatus: log.map(NutritionDayEvidence.status) ?? .unknown,
                                    caption: caption, calendar: capture.calendar)
    }
    private var ownerIsCurrent: Bool { !invalidated && capture.ownerID == DIContainer.shared.authService.currentUserID }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose what to share").appTextRole(.sectionTitle)
                    Text("Your day path is included first. Add numbers, food names or weight only if you want to share them.")
                        .appTextRole(.secondary)
                    HStack {
                        Button("Public summary") { options = .init(preset: .publicSummary) }
                            .accessibilityIdentifier("livingDaySharePublicPreset")
                        Button("Private check-in") { options = .init(preset: .privateCheckIn) }
                            .accessibilityIdentifier("livingDaySharePrivatePreset")
                    }.buttonStyle(.bordered)
                    VStack {
                        Toggle("Nutrition budget · kcal and grams", isOn: $options.budget).accessibilityIdentifier("livingDayShareBudgetToggle")
                        Toggle("Generic day path", isOn: $options.path).accessibilityIdentifier("livingDaySharePathToggle")
                        Toggle("Logged food names", isOn: $options.foodNames).accessibilityIdentifier("livingDayShareFoodsToggle")
                        Toggle("Weight measured on this day", isOn: $options.weight).accessibilityIdentifier("livingDayShareWeightToggle")
                        Toggle("Data review markers", isOn: $options.trust).accessibilityIdentifier("livingDayShareTrustToggle")
                        Toggle("Next-step text", isOn: $options.action).accessibilityIdentifier("livingDayShareActionToggle")
                    }.tint(.brandPrimary)
                    TextField("Optional caption", text: $caption, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3)
                        .onChange(of: caption) { _, value in if value.count > 180 { caption = String(value.prefix(180)) } }
                    if let shareImage, ownerIsCurrent {
                        Image(uiImage: shareImage).resizable().scaledToFit()
                            .accessibilityLabel(document.text)
                            .accessibilityIdentifier("livingDaySharePreview")
                    }
                    if ownerIsCurrent {
                        DisclosureGroup("View text version") {
                            Text(document.text).textSelection(.enabled).appTextRole(.secondary)
                        }.accessibilityIdentifier("livingDayShareText")
                    }
                }.padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                shareAction.padding(AppSpacing.row).background(.bar)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Share my day").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { observeOwner(); render() }
            .onChange(of: document) { _, _ in render() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { validateOwner() } }
            .onDisappear {
                if let authObserver { observedAuth?.removeObserver(authObserver) }
                authObserver = nil; observedAuth = nil; shareImage = nil; exportImage = nil; exportDocument = nil
            }
            .sheet(isPresented: $showingActivity, onDismiss: { exportImage = nil; exportDocument = nil }) {
                if ownerIsCurrent, let exportImage, let exportDocument {
                    PrivateDayShareActivity(image: exportImage, text: exportDocument.text)
                }
            }
        }
    }
    private var shareAction: some View {
        Button {
                        guard ownerIsCurrent, let shareImage else { dismiss(); return }
                        exportDocument = document; exportImage = shareImage; showingActivity = true
                    } label: {
                        Label("Share image and text", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(!ownerIsCurrent || shareImage == nil)
                        .accessibilityIdentifier("livingDayShareCommitButton")
    }

    private func observeOwner() {
        guard authObserver == nil, ownerIsCurrent else { validateOwner(); return }
        guard let service = DIContainer.shared.authService else { invalidated = true; validateOwner(); return }
        observedAuth = service
        authObserver = service.observeAuthState { userID in
            Task { @MainActor in
                if userID != capture.ownerID { invalidated = true; validateOwner() }
            }
        }
    }
    private func validateOwner() {
        guard ownerIsCurrent else {
            shareImage = nil; exportImage = nil; exportDocument = nil; showingActivity = false
            invalidated = true; dismiss(); return
        }
    }
    @MainActor private func render() {
        guard ownerIsCurrent else { shareImage = nil; return }
        let renderer = ImageRenderer(content: PrivateDayShareCard(document: document).frame(width: 360).environment(\.colorScheme, .light))
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

private struct PrivateDayShareCard: View {
    let document: LivingDayPrivateShare
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MYFITPLATE · MY DAY").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.brandForeground)
            Text(document.title).font(.system(size: 23, weight: .bold)).foregroundStyle(.black)
            if !document.caption.isEmpty { Text(document.caption).font(.system(size: 14)).foregroundStyle(.black) }
            ForEach(document.lines) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.title).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.brandForeground)
                    Text(line.value).font(.system(size: 14)).foregroundStyle(.black).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }
        }.padding(24).background(.white).environment(\.dynamicTypeSize, .medium)
    }
}
private struct PrivateDayShareActivity: UIViewControllerRepresentable {
    let image: UIImage
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image, text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct LivingDayShareCard: View {
    let snapshot: LivingDayShareSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let budget = snapshot.budget {
                shareBudget(budget)
            }

            if !snapshot.events.isEmpty {
                sharePath
            }

            if let trustReviewCount = snapshot.trustReviewCount {
                shareTrust(reviewCount: trustReviewCount)
            }

            Spacer(minLength: 0)
            if let nextActionKind = snapshot.nextActionKind {
                shareAction(nextActionKind)
            }
        }
        .padding(20)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MY DAY")
                    .appFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.brandForeground)
                Text(snapshot.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .appFont(size: 22, weight: .bold)
                    .foregroundStyle(.black)
            }

            Spacer()
            Text("MyFitPlate")
                .appFont(size: 11, weight: .bold)
                .foregroundStyle(.secondary)
        }
    }

    private func shareBudget(_ budget: LivingDaySnapshot.Budget) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Budget")
                .appFont(size: 13, weight: .bold)
                .foregroundStyle(.black)

            ForEach(budget.nutrients, id: \.kind) { nutrient in
                HStack(spacing: 8) {
                    Text(nutrient.shareShortTitle)
                        .appFont(size: 10, weight: .bold)
                        .foregroundStyle(nutrient.shareColor)
                        .frame(width: 24, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.08))
                            Capsule()
                                .fill(nutrient.shareColor.opacity(0.25))
                                .frame(width: geometry.size.width * nutrient.shareTotalWidth)
                            Capsule()
                                .fill(nutrient.shareColor)
                                .frame(width: geometry.size.width * nutrient.shareConsumedWidth)
                        }
                    }
                    .frame(height: 6)
                    Text(nutrient.shareRemainingText)
                        .appFont(size: 9, weight: .semibold)
                        .foregroundStyle(.black)
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    private var sharePath: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Your Day")
                .appFont(size: 13, weight: .bold)
                .foregroundStyle(.black)

            ForEach(Array(snapshot.events.prefix(5).enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 9) {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .appFont(size: 9, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)

                    VStack(spacing: 0) {
                        ZStack {
                            event.shareNodeBackground
                            Image(systemName: event.shareIcon)
                                .appFont(size: 9, weight: .bold)
                                .foregroundStyle(event.state == .planned ? event.shareColor : AppPalette.onSignal)
                        }
                        .frame(width: 24, height: 24)

                        if index < min(5, snapshot.events.count) - 1 {
                            Rectangle()
                                .fill(Color.black.opacity(0.12))
                                .frame(width: 1, height: 8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.shareTitle)
                            .appFont(size: 10, weight: .bold)
                            .foregroundStyle(.black)
                        Text(event.shareStateTitle)
                            .appFont(size: 8, weight: .semibold)
                            .foregroundStyle(event.needsTrustReview ? AppPalette.caution : .secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 28)
            }
        }
    }

    private func shareTrust(reviewCount: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: reviewCount == 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(reviewCount == 0 ? Color.brandForeground : AppPalette.caution)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trust")
                    .appFont(size: 10, weight: .bold)
                    .foregroundStyle(.black)
                Text(reviewCount == 0 ? "No review markers" : "\(reviewCount) review marker\(reviewCount == 1 ? "" : "s")")
                    .appFont(size: 9, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shareAction(_ actionKind: DailyNextAction.Kind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: actionKind.shareIcon)
                .appFont(size: 12, weight: .bold)
                .foregroundStyle(Color.brandForeground)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("NEXT MOVE")
                    .appFont(size: 8, weight: .bold)
                    .foregroundStyle(Color.brandForeground)
                Text(actionKind.shareTitle)
                    .appFont(size: 12, weight: .bold)
                    .foregroundStyle(.black)
            }
            Spacer()
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct FixedShareCardPreview<Content: View>: View {
    private let content: Content
    private let canvasWidth: CGFloat = 360
    private let canvasHeight: CGFloat = 500
    private let maximumScale: CGFloat = 0.82

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(maximumScale, max(0, geometry.size.width / canvasWidth))

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(width: canvasWidth, height: canvasHeight)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: canvasWidth * scale,
                        height: canvasHeight * scale,
                        alignment: .topLeading
                    )
                Spacer(minLength: 0)
            }
        }
        .frame(height: canvasHeight * maximumScale)
    }
}

private extension LivingDaySnapshot.NutrientBudget {
    var shareShortTitle: String {
        switch kind {
        case .calories: return "Cal"
        case .protein: return "P"
        case .carbs: return "C"
        case .fats: return "F"
        }
    }

    var shareColor: Color {
        switch kind {
        case .calories: return .brandPrimary
        case .protein: return .accentProtein
        case .carbs: return .accentCarbs
        case .fats: return .accentFats
        }
    }

    var shareRemainingText: String {
        guard let remaining else { return "Unavailable" }
        let unit = kind == .calories ? "cal" : "g"
        let amount = Int(abs(remaining).rounded())
        return remaining >= 0 ? "\(amount) \(unit) left" : "\(amount) \(unit) over"
    }

    var shareConsumedWidth: CGFloat {
        CGFloat(min(1, max(0, consumedFraction ?? 0)))
    }

    var shareTotalWidth: CGFloat {
        guard let consumed, let planned, let target, target > 0 else { return 0 }
        return CGFloat(min(1, max(0, (consumed + planned) / target)))
    }
}

private extension LivingDayShareSnapshot.Event {
    var shareTitle: String {
        switch kind {
        case .meal: return "Meal"
        case .strength: return "Strength"
        case .run: return "Run"
        case .activity: return "Activity"
        case .recovery: return "Recovery"
        }
    }

    var shareIcon: String {
        switch kind {
        case .meal: return "fork.knife"
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .activity: return "figure.mixed.cardio"
        case .recovery: return "bolt.heart.fill"
        }
    }

    var shareColor: Color {
        switch kind {
        case .meal: return .brandPrimary
        case .strength: return AppPalette.effort
        case .run: return AppPalette.effort
        case .activity: return AppPalette.achievement
        case .recovery: return AppPalette.recovery
        }
    }

    @ViewBuilder
    var shareNodeBackground: some View {
        switch state {
        case .completed:
            Circle().fill(shareColor)
        case .planned:
            Circle().fill(.white).overlay(Circle().stroke(shareColor, lineWidth: 1.5))
        case .active:
            RoundedRectangle(cornerRadius: 5).fill(shareColor)
        }
    }

    var shareStateTitle: String {
        let timing = isApproximate ? "Approx. " : ""
        let stateTitle: String
        switch state {
        case .completed: stateTitle = "Completed"
        case .planned: stateTitle = "Planned"
        case .active: stateTitle = "In progress"
        }
        return timing + (needsTrustReview ? "Review" : stateTitle)
    }
}

private extension DailyNextAction.Kind {
    var shareTitle: String {
        switch self {
        case .preWorkoutFuel: return "Fuel before training"
        case .recoveryMeal: return "Recovery fuel"
        case .proteinCatchUp: return "Close the protein gap"
        case .trustReview: return "Review food data"
        case .steadyDay: return "Stay steady"
        }
    }

    var shareIcon: String {
        switch self {
        case .preWorkoutFuel: return "bolt.fill"
        case .recoveryMeal: return "bolt.heart.fill"
        case .proteinCatchUp: return "fork.knife"
        case .trustReview: return "checkmark.shield.fill"
        case .steadyDay: return "checkmark"
        }
    }
}
