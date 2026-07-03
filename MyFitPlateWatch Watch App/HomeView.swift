import SwiftUI

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
                            Text("No data yet")
                                .font(.headline)
                            Text("Open MyFitPlate on your phone to sync today.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 6) {
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
