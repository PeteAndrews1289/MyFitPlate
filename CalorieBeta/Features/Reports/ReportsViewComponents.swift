import SwiftUI
import Charts

struct ReportsOverviewCard: View {
    let selectedTimeframe: ReportTimeframe
    let customStartDate: Date
    let customEndDate: Date
    let summary: ReportSummary?
    let wellnessScore: WellnessScore?
    let workoutReport: WorkoutReport?
    let sleepReport: EnhancedSleepReport?
    let onOpenInsights: () -> Void

    private var periodTitle: String {
        if selectedTimeframe == .custom {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
        return selectedTimeframe.rawValue
    }

    private var overviewMessage: String {
        if let wellnessScore {
            return wellnessScore.summary
        }
        if let summary, summary.daysLogged > 0 {
            return "\(summary.daysLogged) logged \(summary.daysLogged == 1 ? "day" : "days") in this timeframe."
        }
        if workoutReport != nil || sleepReport != nil {
            return "Activity or sleep data is available for this timeframe."
        }
        return "Start logging to build a useful report."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Report")
                        .appFont(size: 25, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(periodTitle)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.brandPrimary)

                    Text(overviewMessage)
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onOpenInsights) {
                    Image(systemName: "wand.and.stars")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.brandPrimary.opacity(0.12), in: Circle())
                }
                .buttonStyle(AnimatedCardButtonStyle())
                .accessibilityLabel("Generate detailed insights")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ReportMetricTile(
                    title: "Wellness",
                    value: wellnessScore.map { "\($0.overallScore)" } ?? "--",
                    subtitle: "overall score",
                    icon: "heart.fill",
                    color: wellnessScore?.color ?? .brandPrimary
                )

                ReportMetricTile(
                    title: "Avg Calories",
                    value: summary.map { "\(Int($0.averageCalories.rounded()))" } ?? "--",
                    subtitle: "per logged day",
                    icon: "flame.fill",
                    color: .orange
                )

                ReportMetricTile(
                    title: "Workouts",
                    value: workoutReport.map { "\($0.totalWorkouts)" } ?? "--",
                    subtitle: "sessions",
                    icon: "figure.run",
                    color: .blue
                )

                ReportMetricTile(
                    title: "Sleep",
                    value: sleepReport.map { "\($0.averageSleepScore)" } ?? "--",
                    subtitle: "avg score",
                    icon: "bed.double.fill",
                    color: .purple
                )
            }
        }
        .asCard()
    }
}

struct ReportMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: Circle())
                Spacer()
            }

            Text(value)
                .appFont(size: 23, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 11)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SmartReportInsightCard: View {
    let insight: UserInsight

    private var title: String {
        insight.title.lowercased() == "have a great day!" ? "Have a Great Day!" : insight.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 38, height: 38)
                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 16, weight: .semibold)
                    .foregroundColor(.textPrimary)

                Text(insight.message)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .asCard()
    }
}

struct ReportsLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            // Overview card placeholder
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 140, height: 16)
                SkeletonBlock(height: 44)
                HStack(spacing: 10) {
                    SkeletonBlock(height: 30)
                    SkeletonBlock(height: 30)
                    SkeletonBlock(height: 30)
                }
            }
            .padding()
            .asCard()

            // The two side-by-side cards (meal donut + weight)
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        SkeletonBlock(width: 80, height: 14)
                        SkeletonBlock(height: 92, cornerRadius: 12)
                        SkeletonBlock(width: 100, height: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .asCard()
                }
            }
        }
        .skeletonPulse()
    }
}

struct ReportsMessageState: View {
    let icon: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .appFont(size: 28, weight: .semibold)
                .foregroundColor(color)
                .frame(width: 62, height: 62)
                .background(color.opacity(0.12), in: Circle())

            Text(title)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)

            Text(message)
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .asCard()
    }
}

struct ReportSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
