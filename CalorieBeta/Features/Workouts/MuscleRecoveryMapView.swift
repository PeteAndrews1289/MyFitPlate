import MyFitPlateCore
import SwiftUI

struct MuscleRecoveryMapView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject private var workoutService: WorkoutService

    @State private var recoveries: [MuscleRecoveryEstimate]
    @State private var selectedGroup: RecoveryMuscleGroup
    @State private var isLoading: Bool

    private let fixtureRecoveries: [MuscleRecoveryEstimate]?

    init(fixtureRecoveries: [MuscleRecoveryEstimate]? = nil) {
        self.fixtureRecoveries = fixtureRecoveries
        let initial = fixtureRecoveries ?? []
        _recoveries = State(initialValue: initial)
        _selectedGroup = State(
            initialValue: initial.first(where: { $0.status != .noRecentSignal })?.group ?? .chest
        )
        _isLoading = State(initialValue: fixtureRecoveries == nil)
    }

    private var selectedRecovery: MuscleRecoveryEstimate? {
        recoveries.first(where: { $0.group == selectedGroup })
    }

    private var readyCount: Int {
        recoveries.filter(\.isReady).count
    }

    private var recoveringCount: Int {
        recoveries.filter { ![.ready, .noRecentSignal].contains($0.status) }.count
    }

    private var noSignalCount: Int {
        recoveries.filter { $0.status == .noRecentSignal }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Recovery Field",
                subtitle: "An estimate from recent working sets and sleep, shown by muscle region."
            ) {
                AppStatusBadge(
                    readyCount == 1 ? "1 ready" : "\(readyCount) ready",
                    icon: "bolt.fill",
                    role: .current
                )
            }

            if isLoading {
                loadingState
            } else {
                AppMetricStrip(items: [
                    AppMetricItem(label: "Ready", value: readyCount.formatted(), accent: AppPalette.brand),
                    AppMetricItem(label: "Recovering", value: recoveringCount.formatted(), accent: AppPalette.caution),
                    AppMetricItem(label: "No recent signal", value: noSignalCount.formatted(), accent: Color.secondary)
                ])

                RecoveryBodyField(
                    recoveries: recoveries,
                    selectedGroup: $selectedGroup
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Muscle recovery body field")
                .accessibilityIdentifier("muscle_recovery_body_field")

                if let selectedRecovery {
                    RecoveryEvidencePanel(estimate: selectedRecovery)
                        .id(selectedRecovery.id)
                        .transition(.opacity)
                }

                Label(
                    "Recovery is an estimate for planning training, not an injury or medical assessment.",
                    systemImage: "info.circle"
                )
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Muscle recovery")
        .accessibilityIdentifier("muscle_recovery_map")
        .onAppear {
            guard fixtureRecoveries == nil else { return }
            calculateRecovery()
        }
        .onChange(of: dailyLogService.currentDailyLog) { _, _ in
            guard fixtureRecoveries == nil else { return }
            calculateRecovery()
        }
    }

    private var loadingState: some View {
        HStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(AppPalette.brand)

            VStack(alignment: .leading, spacing: 3) {
                Text("Reading recent training")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text("Combining completed sets with your latest sleep signal.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet)
    }

    private func calculateRecovery() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            let now = Date()
            recoveries = RecoveryMuscleGroup.allCases.map {
                MuscleRecoveryRules.estimate(
                    group: $0,
                    lastTrained: nil,
                    sets: nil,
                    sleepScore: nil,
                    asOf: now
                )
            }
            isLoading = false
            return
        }

        isLoading = true
        let now = Date()
        let lookbackDays = 14
        let startDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let sleepScore = healthKitViewModel.sleepSummary.lastNightScore
            ?? healthKitViewModel.sleepSummary.averageScore

        Task {
            var lastTrained: [RecoveryMuscleGroup: Date] = [:]
            var lastSessionSets: [RecoveryMuscleGroup: Int] = [:]

            func record(_ muscleSets: [RecoveryMuscleGroup: Int], at date: Date) {
                for (group, sets) in muscleSets where date > (lastTrained[group] ?? .distantPast) {
                    lastTrained[group] = date
                    lastSessionSets[group] = sets
                }
            }

            let sessions = await workoutService.fetchRecentSessionLogs(sinceDays: lookbackDays)
            for session in sessions {
                var muscleSets: [RecoveryMuscleGroup: Int] = [:]
                for completed in session.completedExercises {
                    for group in MuscleRecoveryRules.muscleGroups(for: completed.exerciseName) {
                        muscleSets[group, default: 0] += completed.sets.count
                    }
                }
                record(muscleSets, at: session.date)
            }

            let history = await dailyLogService.fetchDailyHistory(
                for: userID,
                startDate: startDate,
                endDate: now
            )
            if case .success(let logs) = history {
                for log in logs {
                    guard let exercises = log.exercises else { continue }
                    var muscleSets: [RecoveryMuscleGroup: Int] = [:]
                    for exercise in exercises {
                        for group in MuscleRecoveryRules.muscleGroups(for: exercise.name) {
                            // Daily activity entries do not retain set detail. Six sets is a
                            // conservative proxy and is disclosed as an estimate in the UI.
                            muscleSets[group, default: 0] += 6
                        }
                    }
                    if !muscleSets.isEmpty {
                        record(muscleSets, at: log.date)
                    }
                }
            }

            let estimates = RecoveryMuscleGroup.allCases.map { group in
                MuscleRecoveryRules.estimate(
                    group: group,
                    lastTrained: lastTrained[group],
                    sets: lastSessionSets[group],
                    sleepScore: sleepScore,
                    asOf: now
                )
            }

            await MainActor.run {
                recoveries = estimates
                if recoveries.contains(where: { $0.group == selectedGroup && $0.status != .noRecentSignal }) == false,
                   let firstSignal = recoveries.first(where: { $0.status != .noRecentSignal }) {
                    selectedGroup = firstSignal.group
                }
                isLoading = false
            }
        }
    }
}

private struct RecoveryBodyField: View {
    let recoveries: [MuscleRecoveryEstimate]
    @Binding var selectedGroup: RecoveryMuscleGroup

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            HStack(spacing: AppSpacing.group) {
                RecoveryBodyFigure(
                    side: .front,
                    recoveries: recoveries,
                    selectedGroup: $selectedGroup
                )

                Divider()

                RecoveryBodyFigure(
                    side: .back,
                    recoveries: recoveries,
                    selectedGroup: $selectedGroup
                )
            }
            .frame(height: 248)

            HStack(spacing: AppSpacing.row) {
                RecoveryLegendItem(title: "Fatigued", role: .critical)
                RecoveryLegendItem(title: "Recovering", role: .caution)
                RecoveryLegendItem(title: "Near ready", role: .recovery)
                RecoveryLegendItem(title: "Ready", role: .current)
            }
        }
        .padding(AppSpacing.group)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
    }
}

private struct RecoveryLegendItem: View {
    let title: String
    let role: AppSignalRole

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(role.color)
                .frame(width: 7, height: 7)
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum RecoveryBodySide: String {
    case front = "Front"
    case back = "Back"
}

private struct RecoveryBodyFigure: View {
    let side: RecoveryBodySide
    let recoveries: [MuscleRecoveryEstimate]
    @Binding var selectedGroup: RecoveryMuscleGroup

    private var groups: [RecoveryMuscleGroup] {
        switch side {
        case .front: [.shoulders, .chest, .arms, .core, .legs]
        case .back: [.back]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RecoverySilhouetteShape()
                    .fill(AppPalette.text.opacity(0.07))
                    .overlay {
                        RecoverySilhouetteShape()
                            .stroke(AppPalette.separator, lineWidth: 1)
                    }
                    .padding(.horizontal, geometry.size.width * 0.12)
                    .padding(.top, 22)
                    .padding(.bottom, 2)

                ForEach(groups, id: \.self) { group in
                    if let recovery = recoveries.first(where: { $0.group == group }) {
                        RecoveryZoneButton(
                            estimate: recovery,
                            side: side,
                            isSelected: selectedGroup == group,
                            action: { withAnimation(AppMotion.standard) { selectedGroup = group } }
                        )
                    }
                }

                Text(side.rawValue.uppercased())
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

private struct RecoverySilhouetteShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.addEllipse(in: CGRect(x: width * 0.40, y: 0, width: width * 0.20, height: height * 0.13))
        path.addRoundedRect(
            in: CGRect(x: width * 0.32, y: height * 0.14, width: width * 0.36, height: height * 0.36),
            cornerSize: CGSize(width: width * 0.11, height: width * 0.11)
        )
        path.addRoundedRect(
            in: CGRect(x: width * 0.18, y: height * 0.16, width: width * 0.13, height: height * 0.42),
            cornerSize: CGSize(width: width * 0.07, height: width * 0.07)
        )
        path.addRoundedRect(
            in: CGRect(x: width * 0.69, y: height * 0.16, width: width * 0.13, height: height * 0.42),
            cornerSize: CGSize(width: width * 0.07, height: width * 0.07)
        )
        path.addRoundedRect(
            in: CGRect(x: width * 0.34, y: height * 0.47, width: width * 0.15, height: height * 0.52),
            cornerSize: CGSize(width: width * 0.08, height: width * 0.08)
        )
        path.addRoundedRect(
            in: CGRect(x: width * 0.51, y: height * 0.47, width: width * 0.15, height: height * 0.52),
            cornerSize: CGSize(width: width * 0.08, height: width * 0.08)
        )
        return path
    }
}

private struct RecoveryZoneButton: View {
    let estimate: MuscleRecoveryEstimate
    let side: RecoveryBodySide
    let isSelected: Bool
    let action: () -> Void

    private var role: AppSignalRole {
        estimate.status.signalRole
    }

    var body: some View {
        GeometryReader { geometry in
            Button(action: action) {
                zoneGlyph
                    .fill(role.color.opacity(estimate.status == .noRecentSignal ? 0.34 : 0.88))
                    .overlay {
                        if isSelected {
                            zoneGlyph
                                .stroke(AppPalette.canvas, lineWidth: 4)

                            zoneGlyph
                                .stroke(role.color, lineWidth: 1.25)
                        }
                    }
                    .scaleEffect(isSelected ? 1.04 : 1)
                    .frame(width: zoneSize.width, height: zoneSize.height)
                    .position(position(in: geometry.size))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(estimate.group.displayName), \(estimate.status.displayName)")
            .accessibilityValue(
                estimate.status == .noRecentSignal
                    ? "No recent training signal"
                    : "About \(estimate.roundedPercentage) percent recovered"
            )
        }
    }

    private var zoneGlyph: RecoveryZoneShape {
        RecoveryZoneShape(group: estimate.group)
    }

    private var zoneSize: CGSize {
        switch estimate.group {
        case .shoulders: CGSize(width: 86, height: 18)
        case .chest: CGSize(width: 66, height: 29)
        case .arms: CGSize(width: 98, height: 62)
        case .core: CGSize(width: 34, height: 48)
        case .legs: CGSize(width: 52, height: 90)
        case .back: CGSize(width: 72, height: 82)
        }
    }

    private func position(in size: CGSize) -> CGPoint {
        switch estimate.group {
        case .shoulders: CGPoint(x: size.width * 0.50, y: size.height * 0.26)
        case .chest: CGPoint(x: size.width * 0.50, y: size.height * 0.34)
        case .arms: CGPoint(x: size.width * 0.50, y: size.height * 0.43)
        case .core: CGPoint(x: size.width * 0.50, y: size.height * 0.49)
        case .legs: CGPoint(x: size.width * 0.50, y: size.height * 0.76)
        case .back: CGPoint(x: size.width * 0.50, y: size.height * 0.39)
        }
    }
}

private struct RecoveryZoneShape: Shape {
    let group: RecoveryMuscleGroup

    func path(in rect: CGRect) -> Path {
        switch group {
        case .shoulders:
            pairedRoundedRects(in: rect, width: 0.36, height: 0.58, y: 0.21, radius: rect.height * 0.26)
        case .chest:
            pairedRoundedRects(in: rect, width: 0.46, height: 0.82, y: 0.08, radius: rect.height * 0.24)
        case .arms:
            pairedRoundedRects(in: rect, width: 0.14, height: 0.90, y: 0.05, radius: rect.width * 0.08)
        case .core:
            coreSegments(in: rect)
        case .legs:
            pairedRoundedRects(in: rect, width: 0.34, height: 0.96, y: 0.02, radius: rect.width * 0.16)
        case .back:
            backPanels(in: rect)
        }
    }

    private func pairedRoundedRects(
        in rect: CGRect,
        width: CGFloat,
        height: CGFloat,
        y: CGFloat,
        radius: CGFloat
    ) -> Path {
        var path = Path()
        let panelWidth = rect.width * width
        let panelHeight = rect.height * height
        let inset = rect.width * 0.02
        path.addRoundedRect(
            in: CGRect(x: inset, y: rect.height * y, width: panelWidth, height: panelHeight),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: rect.width - panelWidth - inset, y: rect.height * y, width: panelWidth, height: panelHeight),
            cornerSize: CGSize(width: radius, height: radius)
        )
        return path
    }

    private func coreSegments(in rect: CGRect) -> Path {
        var path = Path()
        let gap = rect.width * 0.08
        let segmentWidth = (rect.width - gap) / 2
        let segmentHeight = rect.height * 0.27
        for row in 0..<3 {
            let y = CGFloat(row) * rect.height * 0.34
            path.addRoundedRect(
                in: CGRect(x: 0, y: y, width: segmentWidth, height: segmentHeight),
                cornerSize: CGSize(width: 4, height: 4)
            )
            path.addRoundedRect(
                in: CGRect(x: segmentWidth + gap, y: y, width: segmentWidth, height: segmentHeight),
                cornerSize: CGSize(width: 4, height: 4)
            )
        }
        return path
    }

    private func backPanels(in rect: CGRect) -> Path {
        var path = Path()
        let center = rect.midX

        var left = Path()
        left.move(to: CGPoint(x: center - rect.width * 0.03, y: rect.minY + rect.height * 0.04))
        left.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.30),
            control1: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.04),
            control2: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.15)
        )
        left.addCurve(
            to: CGPoint(x: center - rect.width * 0.08, y: rect.maxY - rect.height * 0.04),
            control1: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.62),
            control2: CGPoint(x: center - rect.width * 0.18, y: rect.maxY - rect.height * 0.12)
        )
        left.closeSubpath()
        path.addPath(left)

        var transform = CGAffineTransform(translationX: rect.midX, y: 0)
        transform = transform.scaledBy(x: -1, y: 1)
        transform = transform.translatedBy(x: -rect.midX, y: 0)
        path.addPath(left.applying(transform))
        return path
    }
}

private struct RecoveryEvidencePanel: View {
    let estimate: MuscleRecoveryEstimate

    private var role: AppSignalRole {
        estimate.status.signalRole
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(estimate.group.displayName)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)

                    Text(estimate.status.detailText(for: estimate))
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppSpacing.compact)

                AppStatusBadge(
                    estimate.status.displayName,
                    icon: estimate.status.icon,
                    role: role
                )
            }

            RecoveryHorizonView(estimate: estimate, role: role)

            Divider()

            VStack(spacing: 0) {
                RecoveryEvidenceRow(
                    icon: "clock.arrow.circlepath",
                    title: "Last trained",
                    value: lastTrainedText
                )
                Divider().padding(.leading, 34)
                RecoveryEvidenceRow(
                    icon: "list.number",
                    title: "Recent volume",
                    value: volumeText
                )
                Divider().padding(.leading, 34)
                RecoveryEvidenceRow(
                    icon: "bed.double.fill",
                    title: "Sleep adjustment",
                    value: sleepAdjustmentText
                )
            }
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected muscle recovery evidence")
        .accessibilityIdentifier("muscle_recovery_evidence")
    }

    private var lastTrainedText: String {
        guard let hours = estimate.hoursSinceTraining else { return "No session in the last 14 days" }
        if hours < 1 { return "Less than an hour ago" }
        if hours < 24 {
            let roundedHours = Int(hours.rounded(.down))
            return roundedHours == 1 ? "1 hour ago" : "\(roundedHours) hours ago"
        }

        let days = Int((hours / 24).rounded(.down))
        return days == 1 ? "Yesterday" : "\(days) days ago"
    }

    private var volumeText: String {
        guard estimate.lastSessionSets > 0 else { return "No set detail available" }
        let suffix = estimate.lastSessionSets == 1 ? "working set" : "working sets"
        return "\(estimate.lastSessionSets) \(suffix) · ~\(Int(estimate.recoveryHours.rounded()))h window"
    }

    private var sleepAdjustmentText: String {
        if estimate.sleepMultiplier < 1 {
            return "Strong sleep shortened the estimate by about 10%"
        }
        if estimate.sleepMultiplier > 1 {
            let percent = Int(((estimate.sleepMultiplier - 1) * 100).rounded())
            return "Recent sleep extended the estimate by about \(percent)%"
        }
        return "No sleep adjustment applied"
    }
}

private struct RecoveryEvidenceRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .semibold)
                .foregroundStyle(AppPalette.text)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .appTextRole(.body)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.compact)
        .accessibilityElement(children: .combine)
    }
}

private struct RecoveryHorizonView: View {
    let estimate: MuscleRecoveryEstimate
    let role: AppSignalRole

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                Text("Estimated recovery")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(estimate.status == .noRecentSignal ? "No signal" : "~\(estimate.roundedPercentage)%")
                    .appTextRole(.control)
                    .foregroundStyle(role.color)
                    .monospacedDigit()
            }

            AppProgressTrack(progress: estimate.progress, role: role, height: 8)

            HStack {
                Text("Training")
                Spacer()
                Text(midpointLabel)
                Spacer()
                Text("Ready")
            }
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated recovery for \(estimate.group.displayName)")
        .accessibilityValue(
            estimate.status == .noRecentSignal
                ? "No recent signal"
                : "About \(estimate.roundedPercentage) percent, \(estimate.status.displayName)"
        )
    }

    private var midpointLabel: String {
        guard estimate.status != .noRecentSignal else { return "No recent data" }
        return "~\(Int((estimate.recoveryHours / 2).rounded()))h"
    }
}

private extension MuscleRecoveryStatus {
    var signalRole: AppSignalRole {
        switch self {
        case .noRecentSignal: .neutral
        case .fatigued: .critical
        case .recovering: .caution
        case .nearlyReady: .recovery
        case .ready: .current
        }
    }

    var displayName: String {
        switch self {
        case .noRecentSignal: "No recent signal"
        case .fatigued: "Fatigued"
        case .recovering: "Recovering"
        case .nearlyReady: "Near ready"
        case .ready: "Ready"
        }
    }

    var icon: String {
        switch self {
        case .noRecentSignal: "minus"
        case .fatigued: "waveform.path.ecg"
        case .recovering: "clock.fill"
        case .nearlyReady: "arrow.up.right"
        case .ready: "bolt.fill"
        }
    }

    func detailText(for estimate: MuscleRecoveryEstimate) -> String {
        switch self {
        case .noRecentSignal:
            return "No matching strength session was found in the last 14 days."
        case .ready:
            return estimate.wasNotTrainedRecently
                ? "Estimated ready, with no recent session for this region."
                : "The estimated recovery window has passed."
        case .fatigued, .recovering, .nearlyReady:
            let hours = estimate.hoursUntilReady
            if hours < 1 { return "Expected to move into ready soon." }
            if hours < 20 { return "Expected ready in about \(Int(hours.rounded())) hours." }
            let days = Int((hours / 24).rounded(.up))
            return days == 1 ? "Expected ready tomorrow." : "Expected ready in about \(days) days."
        }
    }
}
