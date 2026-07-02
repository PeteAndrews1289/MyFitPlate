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

    private var headline: (value: String, label: String, color: Color) {
        if let wellnessScore {
            return ("\(wellnessScore.overallScore)", "wellness score", wellnessScore.color)
        }

        if let summary, summary.daysLogged > 0 {
            return (Int(summary.averageCalories.rounded()).formatted(), "cal/day", .orange)
        }

        if let workoutReport {
            return (workoutReport.totalWorkouts.formatted(), "workouts", .blue)
        }

        if let sleepReport {
            return (sleepReport.averageSleepScore.formatted(), "sleep score", .purple)
        }

        return ("--", "trend pending", Color(UIColor.secondaryLabel))
    }

    private var supportingLine: String {
        var parts: [String] = []

        if let summary, summary.daysLogged > 0 {
            parts.append("\(summary.daysLogged.formatted()) \(summary.daysLogged == 1 ? "day" : "days") logged")
        }

        if let workoutReport {
            parts.append("\(workoutReport.totalWorkouts.formatted()) \(workoutReport.totalWorkouts == 1 ? "workout" : "workouts")")
        }

        if let sleepReport {
            parts.append("\(sleepReport.averageSleepScore.formatted()) sleep score")
        }

        return parts.isEmpty ? "Log consistently to reveal your trend." : parts.joined(separator: " | ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Headline trend")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(periodTitle)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(headline.value)
                            .appFont(size: 34, weight: .bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(headline.label)
                            .appFont(size: 13, weight: .bold)
                            .foregroundColor(headline.color)
                            .lineLimit(1)
                    }

                    Text(supportingLine)
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(2)

                    Text(overviewMessage)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                Spacer()

                Button(action: onOpenInsights) {
                    Image(systemName: "wand.and.stars")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 40, height: 40)
                        .background(Color.backgroundSecondary.opacity(0.78), in: Circle())
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
                    color: wellnessScore?.color ?? Color(UIColor.secondaryLabel)
                )

                ReportMetricTile(
                    title: "Avg calories",
                    value: summary.map { Int($0.averageCalories.rounded()).formatted() } ?? "--",
                    subtitle: "per logged day",
                    icon: "flame.fill",
                    color: .orange
                )

                ReportMetricTile(
                    title: "Workouts",
                    value: workoutReport.map { $0.totalWorkouts.formatted() } ?? "--",
                    subtitle: "sessions",
                    icon: "figure.run",
                    color: .blue
                )

                ReportMetricTile(
                    title: "Sleep",
                    value: sleepReport.map { $0.averageSleepScore.formatted() } ?? "--",
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
                    .background(Color(UIColor.secondarySystemFill), in: Circle())
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
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SmartReportInsightCard: View {
    let insight: UserInsight

    private var title: String {
        insight.title.lowercased() == "have a great day!" ? "Have a great day" : insight.title
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(width: 38, height: 38)
                .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

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
                .background(Color(UIColor.secondarySystemFill), in: Circle())

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
                .appFont(size: 19, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
