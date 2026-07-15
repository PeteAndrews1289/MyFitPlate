import MyFitPlateCore
import SwiftUI
import UIKit

struct LivingDayShareOptionsView: View {
    let snapshot: LivingDaySnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var includesBudget = true
    @State private var includesPath = true
    @State private var includesTrust = false
    @State private var includesAction = true
    @State private var shareImage: Image?

    private var selection: LivingDayShareSelection {
        var selection: LivingDayShareSelection = []
        if includesBudget { selection.insert(.budget) }
        if includesPath { selection.insert(.path) }
        if includesTrust { selection.insert(.trust) }
        if includesAction { selection.insert(.action) }
        return selection
    }

    private var selectedCount: Int {
        [includesBudget, includesPath, includesTrust, includesAction].filter { $0 }.count
    }

    private var shareSnapshot: LivingDayShareSnapshot {
        LivingDayShareBuilder.make(from: snapshot, selection: selection)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Include in image")
                        .appFont(size: 20, weight: .bold)

                    VStack(spacing: 0) {
                        selectionToggle(
                            title: "Nutrition budget",
                            systemImage: "chart.bar.fill",
                            identifier: "livingDayShareBudgetToggle",
                            isOn: $includesBudget
                        )
                        Divider()
                        selectionToggle(
                            title: "Day path",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            identifier: "livingDaySharePathToggle",
                            isOn: $includesPath
                        )
                        Divider()
                        selectionToggle(
                            title: "Trust markers",
                            systemImage: "checkmark.shield.fill",
                            identifier: "livingDayShareTrustToggle",
                            isOn: $includesTrust
                        )
                        Divider()
                        selectionToggle(
                            title: "Next action",
                            systemImage: "arrow.forward.circle.fill",
                            identifier: "livingDayShareActionToggle",
                            isOn: $includesAction
                        )
                    }

                    FixedShareCardPreview {
                        LivingDayShareCard(snapshot: shareSnapshot)
                    }
                        .accessibilityHidden(true)

                    if let shareImage {
                        ShareLink(
                            item: shareImage,
                            subject: Text("My Living Day"),
                            message: Text(MyFitPlateLinks.shareMessage(
                                "How food and training fit together in my Living Day."
                            )),
                            preview: SharePreview("My Living Day", image: shareImage)
                        ) {
                            Label("Share Living Day", systemImage: "square.and.arrow.up")
                                .appFont(size: 16, weight: .bold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .simultaneousGesture(TapGesture().onEnded(logShareOpened))
                        .accessibilityIdentifier("livingDayShareCommitButton")
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .padding(20)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Share Living Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: selection.rawValue) {
                renderShareImage()
            }
            .onAppear {
                DIContainer.shared.analyticsManager?.logEvent(
                    ProductAnalytics.Event.livingDayShareOptionsOpened.rawValue,
                    parameters: nil
                )
            }
        }
    }

    private func selectionToggle(
        title: String,
        systemImage: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .appFont(size: 15, weight: .semibold)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(.brandPrimary)
        .padding(.vertical, 13)
        .disabled(isOn.wrappedValue && selectedCount == 1)
        .accessibilityIdentifier(identifier)
    }

    @MainActor
    private func renderShareImage() {
        let renderer = ImageRenderer(
            content: LivingDayShareCard(snapshot: shareSnapshot)
                .frame(width: 360, height: 500)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        shareImage = renderer.uiImage.map(Image.init(uiImage:))
    }

    private func logShareOpened() {
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.livingDayShareOpened.rawValue, parameters: [
            "includes_budget": includesBudget,
            "includes_path": includesPath,
            "includes_trust": includesTrust,
            "includes_action": includesAction,
            "path_event_count": shareSnapshot.events.count
        ])
    }
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
                Text("LIVING DAY")
                    .appFont(size: 11, weight: .bold)
                    .foregroundStyle(Color.brandPrimary)
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
                                .foregroundStyle(event.state == .planned ? event.shareColor : .white)
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
                .foregroundStyle(reviewCount == 0 ? Color.brandPrimary : AppPalette.caution)
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
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 30, height: 30)
                .background(Color.brandPrimary.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("NEXT MOVE")
                    .appFont(size: 8, weight: .bold)
                    .foregroundStyle(Color.brandPrimary)
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
