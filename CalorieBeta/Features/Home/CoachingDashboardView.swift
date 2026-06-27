import SwiftUI

struct CoachingDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var insightsService: InsightsService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .appFont(size: 24, weight: .bold)
                                .foregroundColor(.brandPrimary)
                            Text("Maia's Strategy")
                                .appFont(size: 22, weight: .bold)
                        }

                        Text("What I'm seeing in your recent nutrition, sleep, and activity.")
                            .appFont(size: 15)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.bottom, 10)

                        content
                    }
                    .padding(20)
                    .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Coaching Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        insightsService.generateAndFetchInsights()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(insightsService.isLoadingInsights)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .onAppear {
                if insightsService.currentInsights.isEmpty && !insightsService.isLoadingInsights {
                    insightsService.generateAndFetchInsights()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if insightsService.isLoadingInsights && insightsService.currentInsights.isEmpty {
            HStack(spacing: 12) {
                ProgressView().tint(.brandPrimary)
                Text("Reviewing your recent data…")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 30)
        } else if insightsService.currentInsights.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .appFont(size: 28)
                    .foregroundColor(.brandPrimary)
                Text("Keep logging and I'll build your strategy")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text("A few days of meals, workouts, and sleep give me enough to spot patterns and tailor your targets.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(insightsService.currentInsights.sorted { $0.priority > $1.priority }) { insight in
                    let style = Self.style(for: insight.category)
                    CoachingInsightRow(
                        icon: style.icon,
                        title: insight.title,
                        description: insight.message,
                        color: style.color
                    )
                }
            }
        }
    }

    private static func style(for category: UserInsight.InsightCategory) -> (icon: String, color: Color) {
        switch category {
        case .hydration: return ("drop.fill", .blue)
        case .macroBalance: return ("chart.pie.fill", .purple)
        case .microNutrient, .fiberIntake: return ("leaf.fill", .green)
        case .mealTiming: return ("clock.fill", .orange)
        case .consistency: return ("flame.fill", .red)
        case .postWorkout, .exerciseSynergy: return ("figure.strengthtraining.traditional", .accentPositive)
        case .foodVariety: return ("square.grid.3x3.fill", .teal)
        case .positiveReinforcement: return ("star.fill", .yellow)
        case .sugarAwareness: return ("cube.fill", .pink)
        case .saturatedFat: return ("drop.triangle.fill", .orange)
        case .smartSuggestion: return ("lightbulb.fill", .yellow)
        case .sleep: return ("moon.zzz.fill", .indigo)
        case .calorieFluctuation: return ("waveform.path.ecg", .orange)
        case .weekendTrends: return ("calendar", .blue)
        default: return ("fork.knife", .brandPrimary)
        }
    }
}

private struct CoachingInsightRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(description)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
        }
    }
}
