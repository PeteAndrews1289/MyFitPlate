import SwiftUI
import MyFitPlateCore

// The Sunday screen: one week of effort, told back to the user — and rendered as a
// shareable card (free marketing every time it's posted). DESIGN.md: the headline is the
// hero, stats are neutral tiles, Share is the single filled CTA.
struct WeeklyRecapView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    // WorkoutService is NOT an app-wide environment object — each consumer owns its
    // instance (the codebase idiom). Reading it from the environment here crashed the
    // sheet on device: "No ObservableObject of type WorkoutService found."
    @StateObject private var workoutService = WorkoutService()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    @State private var recap: WeeklyRecap?
    @State private var isLoading = true
    @State private var shareImage: Image?

    private var unit: String { BodyUnits.weightUnit(metric: useMetric) }

    private var weekRangeText: String {
        guard let recap else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: recap.weekStart)) – \(formatter.string(from: recap.weekEnd))"
    }

    private var headline: String {
        guard let recap else { return "" }
        if !recap.hasAnyActivity {
            return "A quiet week"
        }
        if recap.personalRecords > 0 {
            return recap.personalRecords == 1 ? "You set a personal record" : "You set \(recap.personalRecords) personal records"
        }
        let activeDays = max(recap.daysLogged, recap.workoutsCompleted)
        return "You showed up \(activeDays) \(activeDays == 1 ? "day" : "days") this week"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let recap {
                    VStack(spacing: 16) {
                        VStack(spacing: 6) {
                            Text(weekRangeText)
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .textCase(.uppercase)

                            Text(headline)
                                .appFont(size: 26, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.center)

                            if recap.hasAnyActivity {
                                Text("Here's what the week added up to.")
                                    .appFont(size: 13)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            } else {
                                Text("Log a meal or a workout and next week's recap fills up.")
                                    .appFont(size: 13)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .asCard()

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            RecapStatTile(
                                title: "Days logged",
                                value: "\(recap.daysLogged) of 7",
                                icon: "calendar"
                            )
                            RecapStatTile(
                                title: "Workouts",
                                value: "\(recap.workoutsCompleted)",
                                icon: "figure.strengthtraining.traditional"
                            )
                            RecapStatTile(
                                title: "Avg calories",
                                value: recap.averageCalories.map { "\(Int($0.rounded()).formatted()) cal" } ?? "—",
                                detail: recap.calorieGoal.map { "goal \(Int($0.rounded()).formatted())" },
                                icon: "flame"
                            )
                            RecapStatTile(
                                title: "Avg protein",
                                value: recap.averageProtein.map { "\(Int($0.rounded()).formatted()) g" } ?? "—",
                                icon: "bolt"
                            )
                            RecapStatTile(
                                title: "Volume moved",
                                value: recap.totalVolume > 0 ? "\(Int(recap.totalVolume.rounded()).formatted()) lbs" : "—",
                                icon: "scalemass"
                            )
                            RecapStatTile(
                                title: "Weight change",
                                value: recap.weightChange.map { String(format: "%+.1f %@", BodyUnits.weightDisplayValue(lbs: $0, metric: useMetric), unit) } ?? "—",
                                icon: "chart.line.flattrend.xyaxis"
                            )
                        }

                        if recap.personalRecords > 0 {
                            HStack(spacing: 10) {
                                Image(systemName: "star.fill")
                                    .appFont(size: 15, weight: .bold)
                                    .foregroundColor(.accentPositive)
                                Text("\(recap.personalRecords) \(recap.personalRecords == 1 ? "lift hit" : "lifts hit") an all-time best this week.")
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(Color.accentPositive.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview("My week with MyFitPlate", image: shareImage)
                            ) {
                                Label("Share your week", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded {
                                DIContainer.shared.analyticsManager?.logEvent("weekly_recap_share_opened", parameters: nil)
                            })
                        }
                    }
                    .padding()
                } else if isLoading {
                    ProgressView("Adding up your week")
                        .padding(.top, 120)
                }
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadRecap() }
        }
    }

    private func loadRecap() async {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            isLoading = false
            return
        }

        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()

        // One session fetch covers the week and the PR baseline; the builder splits by date.
        async let logsResult = dailyLogService.fetchDailyHistory(for: userID, startDate: weekStart, endDate: Date())
        async let allSessions = workoutService.fetchRecentSessionLogs(sinceDays: 180)

        let dailyLogs = (try? await logsResult.get()) ?? []
        let sessions = await allSessions
        let weekSessions = sessions.filter { $0.date >= weekStart }
        let priorSessions = sessions.filter { $0.date < weekStart }

        let built = WeeklyRecapBuilder.build(
            weekEnding: Date(),
            calendar: calendar,
            dailyLogs: dailyLogs,
            sessionLogs: weekSessions,
            priorSessionLogs: priorSessions,
            weightHistory: goalSettings.weightHistory,
            calorieGoal: goalSettings.calories
        )

        recap = built
        isLoading = false
        DIContainer.shared.analyticsManager?.logEvent("weekly_recap_viewed", parameters: [
            "days_logged": built.daysLogged,
            "workouts": built.workoutsCompleted,
            "prs": built.personalRecords
        ])
        renderShareImage(for: built)
    }

    @MainActor
    private func renderShareImage(for recap: WeeklyRecap) {
        let renderer = ImageRenderer(content: WeeklyRecapShareCard(
            recap: recap,
            weekRangeText: weekRangeText,
            headline: headline,
            unit: unit,
            useMetric: useMetric
        ))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }
}

private struct RecapStatTile: View {
    let title: String
    let value: String
    var detail: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(title)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }

            Text(value)
                .appFont(size: 19, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()

            if let detail {
                Text(detail)
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Fixed-size branded card rendered to the share image — solid backgrounds only
/// (ImageRenderer can't resolve materials), sized for social.
struct WeeklyRecapShareCard: View {
    let recap: WeeklyRecap
    let weekRangeText: String
    let headline: String
    let unit: String
    let useMetric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("MyFitPlate")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                Text(weekRangeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }

            Text(headline)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                shareRow(label: "Days logged", value: "\(recap.daysLogged) of 7")
                shareRow(label: "Workouts", value: "\(recap.workoutsCompleted)")
                if recap.totalVolume > 0 {
                    shareRow(label: "Volume moved", value: "\(Int(recap.totalVolume.rounded()).formatted()) lbs")
                }
                if recap.personalRecords > 0 {
                    shareRow(label: "Personal records", value: "\(recap.personalRecords) ★")
                }
                if let change = recap.weightChange {
                    shareRow(label: "Weight", value: String(format: "%+.1f %@", BodyUnits.weightDisplayValue(lbs: change, metric: useMetric), unit))
                }
            }

            Spacer(minLength: 0)

            Text("Tracked with MyFitPlate")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(26)
        .frame(width: 360, height: 440, alignment: .topLeading)
        .background(Color(red: 0.09, green: 0.22, blue: 0.16))
    }

    private func shareRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
