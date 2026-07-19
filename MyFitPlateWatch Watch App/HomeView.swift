import SwiftUI
import MyFitPlateCore

// DESIGN.md rule 1: the watch answers "how am I doing today?" the moment it opens.
// The glance IS the home — calories remaining as hero, the macro trio under it,
// then two quiet links. No tile menu between the user and their day.
struct HomeView: View {
    @EnvironmentObject var appDelegate: AppDelegate

    private var remainingCalories: Int {
        max(0, Int(appDelegate.goalCal - appDelegate.userCal))
    }

    private var hasData: Bool {
        appDelegate.goalCal > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hasData {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(remainingCalories.formatted()) cal left")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .contentTransition(.numericText())
                            Gauge(value: min(appDelegate.userCal, appDelegate.goalCal), in: 0...max(appDelegate.goalCal, 1)) {
                                EmptyView()
                            }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(WatchPalette.brandPrimary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(remainingCalories) calories left today")

                        VStack(alignment: .leading, spacing: 8) {
                            MacroGaugeRow(label: "Protein", consumed: appDelegate.userProt, goal: appDelegate.totalProt, color: WatchPalette.accentProtein)
                            MacroGaugeRow(label: "Carbs", consumed: appDelegate.userCarb, goal: appDelegate.totalCarb, color: WatchPalette.accentCarbs)
                            MacroGaugeRow(label: "Fats", consumed: appDelegate.userFat, goal: appDelegate.totalFat, color: WatchPalette.accentFats)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appDelegate.isPhoneReachable ? "No day data yet" : "Phone not connected")
                                .font(.headline)
                            Text(
                                appDelegate.isPhoneReachable
                                    ? "Open MyFitPlate on your phone, then sync again."
                                    : "Open MyFitPlate on both devices to reconnect."
                            )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                        WatchSyncStatusView(
                            freshness: AppDataFreshness(
                                updatedAt: appDelegate.lastSyncDate,
                                now: context.date
                            ),
                            isPhoneReachable: appDelegate.isPhoneReachable,
                            isPending: appDelegate.isSyncRequestPending,
                            retry: appDelegate.requestSync
                        )
                    }

                    VStack(spacing: 6) {
                        if let nextAction = appDelegate.nextAction {
                            NavigationLink(destination: WatchNextActionView(action: nextAction)) {
                                HomeLinkRow(
                                    icon: icon(for: nextAction.kind),
                                    title: nextAction.title,
                                    iconColor: actionColor(for: nextAction.kind)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if let recentMeal = appDelegate.recentMeal {
                            NavigationLink(destination: WatchRepeatMealView(snapshot: recentMeal)) {
                                HomeLinkRow(
                                    icon: "arrow.clockwise",
                                    title: "Repeat \(recentMeal.mealName)",
                                    iconColor: WatchPalette.brandForeground
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink(destination: WaterBottleView()) {
                            HomeLinkRow(icon: "drop.fill", title: "Log water", iconColor: WatchPalette.accentWater)
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: WeightTracker()) {
                            HomeLinkRow(icon: "chart.xyaxis.line", title: "Weight", iconColor: .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 2)
            }
            .navigationTitle("Today")
        }
    }

    private func icon(for kind: DailyNextAction.Kind) -> String {
        switch kind {
        case .preWorkoutFuel: return "bolt.fill"
        case .recoveryMeal: return "fork.knife"
        case .proteinCatchUp: return "chart.bar.fill"
        case .trustReview: return "checkmark.shield.fill"
        case .steadyDay: return "checkmark.circle.fill"
        }
    }

    private func actionColor(for kind: DailyNextAction.Kind) -> Color {
        switch kind {
        case .preWorkoutFuel, .recoveryMeal: return WatchPalette.accentSignal
        case .proteinCatchUp: return WatchPalette.accentProtein
        case .trustReview, .steadyDay: return WatchPalette.brandForeground
        }
    }
}

private struct WatchSyncStatusView: View {
    let freshness: AppDataFreshness
    let isPhoneReachable: Bool
    let isPending: Bool
    let retry: () -> Void

    private var color: Color {
        switch freshness.state {
        case .stale: WatchPalette.accentSignal
        case .current, .aging, .unavailable: .secondary
        }
    }

    private var icon: String {
        if !isPhoneReachable {
            return "iphone.slash"
        }
        switch freshness.state {
        case .current: return "checkmark.circle"
        case .aging: return "arrow.triangle.2.circlepath"
        case .stale: return "clock.badge.exclamationmark"
        case .unavailable: return "iphone.and.arrow.forward"
        }
    }

    private var message: String {
        if !isPhoneReachable {
            return "Phone not reachable"
        }
        if isPending {
            return "Sync requested"
        }
        return freshness.shortLabel
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(message, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(2)

            Spacer(minLength: 2)

            if freshness.state != .current || !isPhoneReachable {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(!isPhoneReachable || isPending)
                .accessibilityLabel("Sync now")
                .accessibilityHint(
                    isPhoneReachable
                        ? "Requests current data from MyFitPlate on your phone"
                        : "Open MyFitPlate on your phone to make sync available"
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            color.opacity(freshness.state == .stale ? 0.12 : 0.07),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct WatchNextActionView: View {
    let action: DailyNextAction

    private var icon: String {
        switch action.kind {
        case .preWorkoutFuel: return "bolt.fill"
        case .recoveryMeal: return "fork.knife"
        case .proteinCatchUp: return "chart.bar.fill"
        case .trustReview: return "checkmark.shield.fill"
        case .steadyDay: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch action.kind {
        case .preWorkoutFuel, .recoveryMeal: return WatchPalette.accentSignal
        case .proteinCatchUp: return WatchPalette.accentProtein
        case .trustReview, .steadyDay: return WatchPalette.brandForeground
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(action.title)
                    .font(.headline)
                Text(action.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if action.kind == .preWorkoutFuel || action.kind == .recoveryMeal {
                    HStack(spacing: 12) {
                        if let protein = action.proteinGrams, protein > 0 {
                            WatchTargetMetric(value: protein, label: "Protein")
                        }
                        if let carbs = action.carbGrams, carbs > 0 {
                            WatchTargetMetric(value: carbs, label: "Carbs")
                        }
                    }
                }

                Text("Continue in MyFitPlate on iPhone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .navigationTitle("Next")
    }
}

private struct WatchTargetMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value) g")
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchRepeatMealView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    let snapshot: WatchMealSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(snapshot.mealName)
                    .font(.headline)
                Text("\(snapshot.foodItems.count) \(snapshot.foodItems.count == 1 ? "item" : "items") · \(snapshot.totalCalories) cal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    appDelegate.repeatRecentMeal()
                } label: {
                    Label("Log again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchPalette.brandPrimary)

                if let status = appDelegate.repeatMealStatus {
                    Label(
                        status,
                        systemImage: appDelegate.repeatMealQueued
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(
                            appDelegate.repeatMealQueued ? Color.secondary : WatchPalette.accentSignal
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .navigationTitle("Repeat Meal")
    }
}

private struct MacroGaugeRow: View {
    let label: String
    let consumed: Double
    let goal: Double
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(consumed / goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(consumed)) / \(Int(goal))g")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Gauge(value: progress) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(consumed)) of \(Int(goal)) grams")
    }
}

private struct HomeLinkRow: View {
    let icon: String
    let title: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HomeView()
        .environmentObject(AppDelegate())
}
