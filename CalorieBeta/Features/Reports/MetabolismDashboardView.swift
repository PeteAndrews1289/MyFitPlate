import MyFitPlateCore

import SwiftUI

struct MetabolismDashboardView: View {
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Environment(\.dismiss) private var dismiss

    @State private var showingWeeklyReview = false
    @State private var selectedWeight: AdaptiveWeightEvidence?
    @State private var exclusionReason = ""
    @State private var reviewedRevision = 0
    @State private var reviewOwnerID: String?
    @State private var reviewError: String?
    @State private var isSavingEvidence = false
    @State private var evidenceChoiceSaved = false
    @State private var visibleHistoryCount = 12
    @State private var isLoading: Bool

    private let loadsData: Bool

    init(loadsData: Bool = true) {
        self.loadsData = loadsData
        _isLoading = State(initialValue: loadsData)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Analyzing 21-day metabolism trends...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    dashboardContent
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.group)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Adaptive metabolism")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("adaptive_tdee_screen")
        .sheet(isPresented: $showingWeeklyReview) {
            WeeklyCheckInView(mode: goalSettings.calorieGoalMethod == .dynamicTDEE ? .checkIn : .adaptiveOffer)
        }
        .sheet(item: $selectedWeight) { weight in weightReview(weight) }
        .task {
            reviewOwnerID = DIContainer.shared.authService.currentUserID
            guard loadsData else {
                isLoading = false
                return
            }
            guard let userID = DIContainer.shared.authService.currentUserID else {
                isLoading = false
                return
            }
            await adaptiveGoalService.fetchAndCalculate(userID: userID, goalSettings: goalSettings, dailyLogService: dailyLogService)
            isLoading = false
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("An estimate from 21 days of recorded food and weight.")
                .appTextRole(.secondary).foregroundStyle(.secondary)

            if adaptiveGoalService.dataConfidence == .insufficient {
                let weighInsLeft = max(0, 7 - adaptiveGoalService.recentWeighInCount)
                let logsLeft = max(0, 10 - adaptiveGoalService.recentValidLogCount)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "hourglass")
                            .foregroundColor(AppPalette.effort)
                        Text(adaptiveGoalService.tdeeGuardrailMessage == nil ? "Building your estimate" : "Check your food logs")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                    }

                    Text(adaptiveGoalService.tdeeGuardrailMessage ?? "The estimate needs \(weighInsLeft) more weigh-in day\(weighInsLeft == 1 ? "" : "s") and \(logsLeft) more fully logged food day\(logsLeft == 1 ? "" : "s") within the evidence window. These are separate requirements, not a countdown.")
                        .appFont(size: 14)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)

                    AdaptiveProgressRow(label: "Weight check-ins", current: adaptiveGoalService.recentWeighInCount, goal: 7, icon: "scalemass.fill")
                    AdaptiveProgressRow(label: "Complete food-log days", current: adaptiveGoalService.recentValidLogCount, goal: 10, icon: "fork.knife")

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .appFont(size: 12)
                            .foregroundColor(AppPalette.caution)
                        Text("Weigh in regularly (ideally daily, around the same time) and log your food honestly. Your estimate is only as accurate as the data you give it.")
                            .appFont(size: 13)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .appSurface(.quiet)
            }

            if let guardrailMessage = adaptiveGoalService.tdeeGuardrailMessage,
               adaptiveGoalService.dataConfidence != .insufficient {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Label("Estimate not ready to use", systemImage: "exclamationmark.shield.fill")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.caution)

                    Text(guardrailMessage)
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppSpacing.group) {
                        Text("\(adaptiveGoalService.recentValidLogCount)/21 complete")
                        Text("\(adaptiveGoalService.partialLogCount) partial")
                        Text("\(adaptiveGoalService.recentWeighInCount) weigh-ins")
                    }
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppSpacing.compact)
                .overlay(alignment: .bottom) { Divider() }
                .accessibilityIdentifier("adaptive_tdee_guardrail")
            }

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(adaptiveGoalService.dataConfidence.rawValue)
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(adaptiveGoalService.dataConfidence.colorName))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(adaptiveGoalService.dataConfidence.colorName).opacity(0.1), in: Capsule())
                        
                        if let tdee = validTDEE {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Int(tdee.rounded()).formatted())
                                    .appFont(size: 48, weight: .heavy)
                                    .foregroundColor(.textPrimary)
                                Text(" cal/day")
                                    .appFont(size: 20, weight: .bold)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        } else {
                            Text("Needs data")
                                .appFont(size: 26, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }

                Divider()

                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Average intake (21 days)",
                        value: averageIntakeText,
                        accent: .brandPrimary
                    ),
                    AppMetricItem(
                        label: "Weight trend",
                        value: weightTrendText,
                        accent: weightTrendAccent
                    )
                ])
            }
            .appSurface(validTDEE == nil ? .quiet : .interpreted)

            Button(action: {
                HapticManager.instance.feedback(.light)
                showingWeeklyReview = true
            }) {
                Text("Review weekly targets")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("adaptive_weekly_review")

            if !canUseAdaptiveTDEE {
                Text("Adaptive TDEE stays unavailable until the food-log and weigh-in evidence is consistent enough to trust.")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            evidenceHistory

            DisclosureGroup("About this estimate") {
                Text("Standard equations estimate energy needs from measurements such as height, weight, and age. Adaptive TDEE also considers your logged intake and weight trend, which can make the estimate more personal over time. It is still an estimate, and missing or inconsistent logs can move it.")
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appTextRole(.control)
            .appSurface(.quiet)
        }
    }

    private var evidenceHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notice = adaptiveGoalService.estimateHistoryNotice {
                Text(notice).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
            }
            if let current = adaptiveGoalService.estimateHistory.first {
                DisclosureGroup("Review weigh-in evidence") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exclude an atypical measurement from this estimate with a reason, or include it again. Your saved weigh-ins and food logs remain intact.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(current.inputs.weights.reversed()) { weight in
                            Button {
                                reviewedRevision = adaptiveGoalService.evidenceReview.revision
                                exclusionReason = adaptiveGoalService.evidenceReview.excludedWeights.first { $0.source == weight }?.reason ?? ""
                                reviewError = nil; evidenceChoiceSaved = false; selectedWeight = weight
                            } label: {
                                HStack {
                                    Text(weight.date.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    Text(BodyUnits.weightString(lbs: weight.pounds, metric: useMetric))
                                    if adaptiveGoalService.evidenceReview.excludes(weight) {
                                        Text("Excluded").foregroundStyle(AppPalette.caution)
                                    }
                                }.appTextRole(.secondary).frame(minHeight: 44)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("adaptive_weight_review_\(weight.id)")
                        }
                    }.padding(.top, 12)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("adaptive_weight_evidence")

                DisclosureGroup("Estimate history · this device") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Each snapshot keeps its input window and reviewed exclusions. Refreshing an estimate does not change your approved targets.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        ForEach(Array(adaptiveGoalService.estimateHistory.prefix(visibleHistoryCount))) { record in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.calculatedAt.formatted(date: .abbreviated, time: .shortened)).appTextRole(.control)
                                Text(record.baseline.calculatedTDEE.map { "\(Int($0.rounded()).formatted()) cal/day" } ?? "Estimate withheld")
                                    .appTextRole(.body)
                                Text("\(record.baseline.validLogCount) complete days · \(record.baseline.recentWeighInCount) weigh-ins · \(record.review.excludedWeights.count) reviewed exclusions")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                                Text("Baseline: \(record.baselineVersion). Evidence inspected: \(record.inputs.start.formatted(date: .abbreviated, time: .omitted))–\(record.inputs.end.formatted(date: .abbreviated, time: .omitted)).")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if adaptiveGoalService.estimateHistory.count > visibleHistoryCount {
                            Button("Show earlier estimates") { visibleHistoryCount += 12 }
                        }
                    }.padding(.top, 12)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("adaptive_estimate_history")

                DisclosureGroup("Robustness comparison") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.shadow.message).appTextRole(.secondary).foregroundStyle(.secondary)
                        if let estimate = current.shadow.estimatedBurn {
                            Text("Comparison: \(Int(estimate.rounded()).formatted()) cal/day over \(current.shadow.evidenceDays) days")
                                .appTextRole(.body)
                        }
                        Text("Experimental comparison, not used for your targets. It uses a longer evidence window and a weight trend less sensitive to individual spikes. It cannot determine how much of a weight change is water or account for unlogged food.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 12)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("adaptive_shadow_comparison")
            }
        }
    }

    private func weightReview(_ weight: AdaptiveWeightEvidence) -> some View {
        let excluded = adaptiveGoalService.evidenceReview.excludes(weight)
        return NavigationStack {
            Form {
                Section {
                    Text(BodyUnits.weightString(lbs: weight.pounds, metric: useMetric)).appTextRole(.screenTitle)
                    Text(weight.date.formatted(date: .complete, time: .shortened))
                    Text(excluded ? "This exact measurement is excluded from the estimate. Including it again may change the estimate and its evidence coverage." : "This exact measurement contributes to the estimate. Excluding it may reduce the usable evidence; your original record stays saved.")
                }
                if !excluded && !evidenceChoiceSaved {
                    Section("Reason for exclusion") {
                        TextField("For example: unusual weighing conditions", text: $exclusionReason, axis: .vertical)
                            .accessibilityIdentifier("adaptive_exclusion_reason")
                    }
                }
                if let reviewError { Text(reviewError).foregroundStyle(AppPalette.caution) }
                if evidenceChoiceSaved {
                    Button("Retry estimate refresh") { refreshAfterEvidenceChoice() }
                        .disabled(isSavingEvidence)
                } else {
                    Button(excluded ? "Include in estimate" : "Exclude from estimate") {
                        saveWeightReview(weight, excluded: !excluded)
                    }.disabled(isSavingEvidence || !excluded && exclusionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("adaptive_exclusion_save")
                }
                if isSavingEvidence { ProgressView("Refreshing evidence…") }
            }
            .appFormStyle()
            .navigationTitle("Review measurement").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSavingEvidence)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(evidenceChoiceSaved ? "Done" : "Cancel") { selectedWeight = nil }.disabled(isSavingEvidence)
            } }
        }
    }

    private func saveWeightReview(_ weight: AdaptiveWeightEvidence, excluded: Bool) {
        guard !isSavingEvidence, let owner = reviewOwnerID else { return }
        isSavingEvidence = true; reviewError = nil
        Task { @MainActor in
            defer { isSavingEvidence = false }
            do {
                try AdaptiveEstimateHistoryStore().setExclusion(weight, excluded: excluded, reason: exclusionReason,
                    userID: owner, currentUserID: DIContainer.shared.authService.currentUserID, expectedRevision: reviewedRevision)
                evidenceChoiceSaved = true
                await adaptiveGoalService.fetchAndCalculate(userID: owner, goalSettings: goalSettings,
                    dailyLogService: dailyLogService, requireServer: true)
                guard DIContainer.shared.authService.currentUserID == owner else { throw WeeklyTargetReviewError.accountChanged }
                if !adaptiveGoalService.lastEvidenceRefreshSucceeded {
                    reviewError = "The evidence choice was saved on this device. The estimate needs a refresh when your records are available."
                } else { selectedWeight = nil }
            } catch { reviewError = error.localizedDescription }
        }
    }

    private func refreshAfterEvidenceChoice() {
        guard !isSavingEvidence, let owner = reviewOwnerID else { return }
        isSavingEvidence = true
        Task { @MainActor in
            defer { isSavingEvidence = false }
            await adaptiveGoalService.fetchAndCalculate(userID: owner, goalSettings: goalSettings,
                dailyLogService: dailyLogService, requireServer: true)
            guard DIContainer.shared.authService.currentUserID == owner else {
                reviewError = WeeklyTargetReviewError.accountChanged.localizedDescription; return
            }
            if adaptiveGoalService.lastEvidenceRefreshSucceeded { selectedWeight = nil } else { reviewError = "Your evidence choice remains saved. The estimate could not be refreshed yet." }
        }
    }

    private var validTDEE: Double? {
        guard let value = adaptiveGoalService.calculatedTDEE, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    private var canUseAdaptiveTDEE: Bool {
        adaptiveGoalService.isEstimateActionable && validTDEE != nil
    }

    private var averageIntakeText: String {
        guard let value = adaptiveGoalService.last21DaysCalorieAverage,
              value.isFinite,
              value >= 0 else {
            return "--"
        }
        return "\(Int(value.rounded()).formatted()) cal"
    }

    private var weightTrendText: String {
        guard let rate = adaptiveGoalService.weightChangeRatePerDay, rate.isFinite else {
            return "--"
        }
        let weeklyRate = BodyUnits.weightDisplayValue(lbs: rate * 7, metric: useMetric)
        let sign = weeklyRate > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", weeklyRate)) \(BodyUnits.weightUnit(metric: useMetric))/wk"
    }

    private var weightTrendAccent: Color {
        guard let rate = adaptiveGoalService.weightChangeRatePerDay, rate.isFinite else {
            return Color(UIColor.secondaryLabel)
        }
        return AppPalette.effort
    }
}

struct AdaptiveProgressRow: View {
    let label: String
    let current: Int
    let goal: Int
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(AppPalette.effort)
                Text(label)
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(min(current, goal)) / \(goal)")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(current >= goal ? .accentPositive : Color(UIColor.secondaryLabel))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(UIColor.secondarySystemFill))
                    Capsule().fill(current >= goal ? AppPalette.positive : AppPalette.effort)
                        .frame(width: geo.size.width * CGFloat(min(Double(current) / Double(max(goal, 1)), 1.0)))
                }
            }
            .frame(height: 7)
        }
    }
}

struct MetabolismReportCard: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(AppPalette.effort)
                    Text("Adaptive metabolism")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                }
                
                Text("Review your adaptive TDEE estimate and weight trend.")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .appFont(size: 14, weight: .semibold)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(AppSpacing.group)
        .appSurface(.quiet, padding: 0)
    }
}
