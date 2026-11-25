import MyFitPlateCore
import SwiftUI

struct MuscleRecoveryMapView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject private var workoutService: WorkoutService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var recoveries: [MuscleRecoveryEstimate]
    @State private var evidence: [RecoveryRegionEvidence] = []
    @State private var observations: [RecoveryCheckIn] = []
    @State private var selectedGroup: RecoveryMuscleGroup
    @State private var isLoading: Bool
    @State private var showingMap = false
    @State private var recoveryTask: Task<Void, Never>?
    @State private var loadGeneration = UUID()
    @State private var checkInRequest: RecoveryCheckInRequest?
    @State private var removingCheckIn: RecoveryCheckIn?
    @State private var loadMessage: String?
    @State private var observationMessage: String?
    private let fixtureRecoveries: [MuscleRecoveryEstimate]?
    init(fixtureRecoveries: [MuscleRecoveryEstimate]? = nil) {
        self.fixtureRecoveries = fixtureRecoveries
        let initial = fixtureRecoveries ?? []
        _recoveries = State(initialValue: initial)
        _selectedGroup = State(initialValue: initial.first(where: { $0.status != .noRecentSignal })?.group ?? .chest)
        _isLoading = State(initialValue: fixtureRecoveries == nil)
    }
    private var selectedRecovery: MuscleRecoveryEstimate? { recoveries.first { $0.group == selectedGroup } }
    private var selectedEvidence: RecoveryRegionEvidence? { evidence.first { $0.group == selectedGroup } }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Recovery & training exposure", subtitle: "Your recent work, sleep and check-in. A planning aid, with no readiness score.")
            if isLoading {
                HStack { ProgressView(); Text("Reading dated training evidence").appTextRole(.secondary) }
            } else {
                if let loadMessage { Label(loadMessage, systemImage: "exclamationmark.circle").appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
                if let selectedEvidence {
                    RecoveryEvidencePanel(evidence: selectedEvidence)
                    checkInActions
                    RecoveryPlanningActionsView(evidence: selectedEvidence, workoutService: workoutService)
                        .appSurface(.quiet).id(selectedEvidence.id)
                } else if let selectedRecovery {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(selectedRecovery.group.displayName).appTextRole(.sectionTitle)
                        Text(selectedRecovery.status.displayName).appTextRole(.control)
                        Text("Example training exposure. No measured tissue-readiness percentage is shown.").appTextRole(.secondary).foregroundStyle(.secondary)
                    }.appSurface(.quiet)
                }
                RecoveryRegionList(recoveries: recoveries, evidence: evidence, selectedGroup: $selectedGroup)
                Button {
                    showingMap.toggle()
                } label: {
                    HStack {
                        Text(showingMap ? "Hide body map" : "Show body map")
                        Spacer()
                        Image(systemName: showingMap ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showingMap ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("muscle_recovery_map_toggle")
                if showingMap {
                    RecoveryBodyField(recoveries: recoveries, selectedGroup: $selectedGroup)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Muscle training exposure body field")
                        .accessibilityIdentifier("muscle_recovery_body_field")
                }
                Label("Unknown means missing evidence, not fully recovered. Stop or change painful movements; this map does not assess injuries.", systemImage: "info.circle")
                    .appTextRole(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Muscle recovery")
        .accessibilityIdentifier("muscle_recovery_map")
        .onAppear { if fixtureRecoveries == nil { calculateRecovery() } }
        .onChange(of: dailyLogService.currentDailyLog) { _, _ in if fixtureRecoveries == nil { calculateRecovery() } }
        .onChange(of: healthKitViewModel.sleepSummary.lastNightScore) { _, _ in if fixtureRecoveries == nil { calculateRecovery() } }
        .onReceive(NotificationCenter.default.publisher(for: .workoutSessionCorrected)) { note in
            if note.object as? String == DIContainer.shared.authService.currentUserID { calculateRecovery() }
        }
        .onDisappear { recoveryTask?.cancel() }
        .sheet(item: $checkInRequest) { request in
            NavigationStack { RecoveryCheckInView(request: request) { calculateRecovery() } }
        }
        .confirmationDialog("Remove this dated check-in?", isPresented: Binding(get: { removingCheckIn != nil }, set: { if !$0 { removingCheckIn = nil } }), titleVisibility: .visible) {
            Button("Remove check-in", role: .destructive) { removeObservation() }
            Button("Cancel", role: .cancel) { removingCheckIn = nil }
        } message: { Text("Workout history and program targets stay intact.") }
    }
    private var checkInActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Button("Add \(selectedGroup.displayName.lowercased()) check-in") { openCheckIn(nil) }
                .frame(minHeight: 44).accessibilityIdentifier("recovery_add_check_in")
            if let observationMessage { Text(observationMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
            let selected = observations.filter { $0.group == selectedGroup }
            if !selected.isEmpty {
                DisclosureGroup("Dated check-ins · on this device") {
                    ForEach(selected.prefix(12)) { value in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(value.observedAt.formatted(date: .abbreviated, time: .shortened)).appTextRole(.control)
                            Text("Soreness: \(value.soreness?.title ?? "Unknown") · Fatigue: \(value.fatigue?.title ?? "Unknown")")
                                .appTextRole(.secondary)
                            if !value.note.isEmpty { Text(value.note).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true) }
                            HStack {
                                Button("Edit") { openCheckIn(value) }.frame(minHeight: 44)
                                Button("Remove", role: .destructive) { removingCheckIn = value }.frame(minHeight: 44)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, AppSpacing.compact)
                    }
                }
            }
        }
    }
    private func openCheckIn(_ existing: RecoveryCheckIn?) {
        guard let owner = DIContainer.shared.authService.currentUserID else { return }
        checkInRequest = .init(userID: owner, group: selectedGroup, existing: existing)
    }
    private func removeObservation() {
        guard let value = removingCheckIn, let owner = DIContainer.shared.authService.currentUserID else { return }
        do { try RecoveryCheckInStore().remove(value, userID: owner); removingCheckIn = nil; calculateRecovery() } catch { observationMessage = error.localizedDescription }
    }
    private func calculateRecovery() {
        recoveryTask?.cancel(); let requestID = UUID(); loadGeneration = requestID
        guard let userID = DIContainer.shared.authService.currentUserID else {
            recoveries = []; evidence = []; observations = []; isLoading = false; return
        }
        let now = Date(); isLoading = true; loadMessage = nil
        recoveryTask = Task { @MainActor in
            let result = await workoutService.fetchRecentSessionLogsResult(sinceDays: 14)
            guard !Task.isCancelled, loadGeneration == requestID, DIContainer.shared.authService.currentUserID == userID else { return }
            let sessions: [WorkoutSessionLog]
            switch result {
            case .success(let values): sessions = values
            case .failure: sessions = []; loadMessage = "Training history could not be refreshed. Missing history is unknown; no plan changes were made."
            }
            do { observations = try RecoveryCheckInStore().observations(userID: userID); observationMessage = nil } catch { observations = []; observationMessage = "Check-ins could not be read. Saved records are preserved. " + error.localizedDescription }
            let runResult: Result<[Run], Error> = await withCheckedContinuation { continuation in
                RunImportService().fetchRunsResult(since: now.addingTimeInterval(-7 * 86_400), userID: userID) { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled, loadGeneration == requestID, DIContainer.shared.authService.currentUserID == userID else { return }
            let runs: [Run]
            switch runResult {
            case .success(let values): runs = values
            case .failure: runs = RunFallbackStore.shared.runs(since: now.addingTimeInterval(-7 * 86_400), for: userID)
                loadMessage = [loadMessage, "Running context includes saved local runs only; Apple Health history was unavailable."].compactMap { $0 }.joined(separator: " ")
            }
            let sleepScore = healthKitViewModel.sleepSummary.lastNightScore
            let sleepDate = healthKitViewModel.coachingRecoveryEvidence(now: now).sleepUpdatedAt
            evidence = MuscleRecoveryRules.regionEvidence(sessions: sessions, runs: runs, checkIns: observations,
                sleepScore: sleepScore, sleepDate: sleepDate, asOf: now)
            recoveries = evidence.map { item in
                let status: MuscleRecoveryStatus
                switch item.state {
                case .unknown: status = .noRecentSignal
                case .stopAndChange, .reviewCheckIn: status = .fatigued
                case .accumulatedExposure: status = .recovering
                case .recentExposure: status = .nearlyReady
                case .lowerRecentLoad: status = .ready
                }
                return .init(group: item.group, lastTrained: item.training.first?.date, lastSessionSets: item.training.first?.workingSets ?? 0,
                    recoveryHours: 1, sleepMultiplier: 1, asOf: now, planningStatus: status)
            }
            isLoading = false
        }
    }
}

private struct RecoveryBodyField: View {
    let recoveries: [MuscleRecoveryEstimate]
    @Binding var selectedGroup: RecoveryMuscleGroup
    @State private var side: RecoveryBodySide = .front

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Picker("Body side", selection: $side) {
                ForEach(RecoveryBodySide.allCases, id: \.self) { side in
                    Text(side.rawValue).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Switches between the front and back muscle map")

            RecoveryBodyFigure(
                side: side,
                recoveries: recoveries,
                selectedGroup: $selectedGroup
            )
            .frame(height: 320)

            HStack(alignment: .top, spacing: 4) {
                RecoveryLegendItem(title: "Recent", role: .critical)
                RecoveryLegendItem(title: "Exposure", role: .caution)
                RecoveryLegendItem(title: "Less recent", role: .recovery)
                RecoveryLegendItem(title: "Lower load", role: .current)
                RecoveryLegendItem(title: "Unknown", role: .neutral)
            }
        }
        .padding(AppSpacing.group)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
        .onChange(of: selectedGroup) { _, group in
            if group == .back {
                side = .back
            } else if group == .chest || group == .core {
                side = .front
            }
        }
    }
}

private struct RecoveryRegionList: View {
    let recoveries: [MuscleRecoveryEstimate]
    var evidence: [RecoveryRegionEvidence] = []
    @Binding var selectedGroup: RecoveryMuscleGroup

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Choose a Muscle Region",
                subtitle: "Select a region to review its latest training signal."
            )

            VStack(spacing: 0) {
                ForEach(Array(recoveries.enumerated()), id: \.element.id) { index, estimate in
                    Button {
                        selectedGroup = estimate.group
                    } label: {
                        HStack(alignment: .top, spacing: AppSpacing.row) {
                            Image(systemName: estimate.status.icon)
                                .appFont(size: 16, weight: .semibold)
                                .foregroundStyle(estimate.status.signalRole.color)
                                .frame(width: 40, height: 40)
                                .background(
                                    estimate.status.signalRole.color.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                )
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(estimate.group.displayName)
                                    .appTextRole(.control)
                                    .foregroundStyle(AppPalette.text)
                                Text(regionSummary(estimate))
                                    .appTextRole(.secondary)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                            if selectedGroup == estimate.group {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppPalette.brandText)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(AppSpacing.group)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedGroup == estimate.group
                                ? AppPalette.interpreted
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(estimate.group.displayName)
                    .accessibilityValue(regionSummary(estimate))
                    .accessibilityAddTraits(selectedGroup == estimate.group ? .isSelected : [])

                    if index < recoveries.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private func regionSummary(_ estimate: MuscleRecoveryEstimate) -> String {
        evidence.first(where: { $0.group == estimate.group })?.state.title ?? estimate.status.displayName
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

private enum RecoveryBodySide: String, CaseIterable {
    case front = "Front"
    case back = "Back"
}

private struct RecoveryBodyFigure: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let side: RecoveryBodySide
    let recoveries: [MuscleRecoveryEstimate]
    @Binding var selectedGroup: RecoveryMuscleGroup

    private var groups: [RecoveryMuscleGroup] {
        switch side {
        case .front: [.shoulders, .chest, .arms, .core, .legs]
        case .back: [.shoulders, .back, .arms, .legs]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let anatomyRect = anatomyRect(in: geometry.size)

            ZStack {
                RecoveryAnatomySilhouette()
                    .fill(AppPalette.canvas.opacity(0.78))
                    .overlay {
                        RecoveryAnatomySilhouette()
                            .stroke(AppPalette.text.opacity(0.18), lineWidth: 0.9)
                    }
                    .frame(width: anatomyRect.width, height: anatomyRect.height)
                    .position(x: anatomyRect.midX, y: anatomyRect.midY)

                RecoveryAnatomyDetails(side: side)
                    .stroke(
                        AppPalette.text.opacity(0.13),
                        style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: anatomyRect.width, height: anatomyRect.height)
                    .position(x: anatomyRect.midX, y: anatomyRect.midY)
                    .allowsHitTesting(false)

                ForEach(groups, id: \.self) { group in
                    if let recovery = recoveries.first(where: { $0.group == group }) {
                        RecoveryZoneButton(
                            estimate: recovery,
                            side: side,
                            isSelected: selectedGroup == group,
                            anatomyRect: anatomyRect,
                            action: {
                                if reduceMotion {
                                    selectedGroup = group
                                } else {
                                    withAnimation(AppMotion.standard) { selectedGroup = group }
                                }
                            }
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

    private func anatomyRect(in size: CGSize) -> CGRect {
        let topInset: CGFloat = 22
        let availableHeight = max(0, size.height - topInset - 2)
        let width = min(size.width * 0.72, availableHeight * 0.58)
        return CGRect(
            x: (size.width - width) / 2,
            y: topInset,
            width: width,
            height: availableHeight
        )
    }
}

private struct RecoveryAnatomySilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }

        path.addEllipse(
            in: CGRect(
                x: rect.minX + rect.width * 0.405,
                y: rect.minY + rect.height * 0.01,
                width: rect.width * 0.19,
                height: rect.height * 0.105
            )
        )

        var torso = Path()
        torso.move(to: point(0.445, 0.108))
        torso.addLine(to: point(0.445, 0.145))
        torso.addCurve(
            to: point(0.315, 0.194),
            control1: point(0.405, 0.15),
            control2: point(0.345, 0.158)
        )
        torso.addCurve(
            to: point(0.345, 0.292),
            control1: point(0.304, 0.225),
            control2: point(0.32, 0.263)
        )
        torso.addCurve(
            to: point(0.382, 0.415),
            control1: point(0.352, 0.333),
            control2: point(0.36, 0.385)
        )
        torso.addCurve(
            to: point(0.345, 0.505),
            control1: point(0.385, 0.453),
            control2: point(0.365, 0.48)
        )
        torso.addCurve(
            to: point(0.405, 0.56),
            control1: point(0.35, 0.535),
            control2: point(0.375, 0.555)
        )
        torso.addLine(to: point(0.595, 0.56))
        torso.addCurve(
            to: point(0.655, 0.505),
            control1: point(0.625, 0.555),
            control2: point(0.65, 0.535)
        )
        torso.addCurve(
            to: point(0.618, 0.415),
            control1: point(0.635, 0.48),
            control2: point(0.615, 0.453)
        )
        torso.addCurve(
            to: point(0.655, 0.292),
            control1: point(0.64, 0.385),
            control2: point(0.648, 0.333)
        )
        torso.addCurve(
            to: point(0.685, 0.194),
            control1: point(0.68, 0.263),
            control2: point(0.696, 0.225)
        )
        torso.addCurve(
            to: point(0.555, 0.145),
            control1: point(0.655, 0.158),
            control2: point(0.595, 0.15)
        )
        torso.addLine(to: point(0.555, 0.108))
        torso.closeSubpath()
        path.addPath(torso)

        var leftArm = Path()
        leftArm.move(to: point(0.32, 0.186))
        leftArm.addCurve(
            to: point(0.235, 0.226),
            control1: point(0.285, 0.19),
            control2: point(0.25, 0.205)
        )
        leftArm.addCurve(
            to: point(0.207, 0.36),
            control1: point(0.22, 0.27),
            control2: point(0.218, 0.318)
        )
        leftArm.addCurve(
            to: point(0.19, 0.515),
            control1: point(0.197, 0.41),
            control2: point(0.188, 0.47)
        )
        leftArm.addCurve(
            to: point(0.235, 0.522),
            control1: point(0.198, 0.535),
            control2: point(0.225, 0.537)
        )
        leftArm.addCurve(
            to: point(0.263, 0.385),
            control1: point(0.244, 0.474),
            control2: point(0.252, 0.428)
        )
        leftArm.addCurve(
            to: point(0.35, 0.226),
            control1: point(0.282, 0.32),
            control2: point(0.325, 0.265)
        )
        leftArm.closeSubpath()
        path.addPath(leftArm)
        path.addPath(mirrored(leftArm, in: rect))

        var leftLeg = Path()
        leftLeg.move(to: point(0.347, 0.52))
        leftLeg.addCurve(
            to: point(0.325, 0.71),
            control1: point(0.333, 0.585),
            control2: point(0.332, 0.65)
        )
        leftLeg.addCurve(
            to: point(0.305, 0.958),
            control1: point(0.316, 0.79),
            control2: point(0.31, 0.89)
        )
        leftLeg.addCurve(
            to: point(0.382, 0.978),
            control1: point(0.32, 0.98),
            control2: point(0.355, 0.985)
        )
        leftLeg.addCurve(
            to: point(0.412, 0.815),
            control1: point(0.393, 0.93),
            control2: point(0.4, 0.865)
        )
        leftLeg.addCurve(
            to: point(0.485, 0.552),
            control1: point(0.43, 0.72),
            control2: point(0.468, 0.625)
        )
        leftLeg.closeSubpath()
        path.addPath(leftLeg)
        path.addPath(mirrored(leftLeg, in: rect))

        return path
    }

    private func mirrored(_ path: Path, in rect: CGRect) -> Path {
        var transform = CGAffineTransform(translationX: rect.midX, y: 0)
        transform = transform.scaledBy(x: -1, y: 1)
        transform = transform.translatedBy(x: -rect.midX, y: 0)
        return path.applying(transform)
    }
}

private struct RecoveryAnatomyDetails: Shape {
    let side: RecoveryBodySide

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }

        switch side {
        case .front:
            path.move(to: point(0.5, 0.2))
            path.addCurve(
                to: point(0.37, 0.22),
                control1: point(0.46, 0.205),
                control2: point(0.415, 0.208)
            )
            path.move(to: point(0.5, 0.2))
            path.addCurve(
                to: point(0.63, 0.22),
                control1: point(0.54, 0.205),
                control2: point(0.585, 0.208)
            )
            path.move(to: point(0.5, 0.225))
            path.addCurve(
                to: point(0.5, 0.48),
                control1: point(0.49, 0.31),
                control2: point(0.49, 0.405)
            )
            path.move(to: point(0.395, 0.505))
            path.addCurve(
                to: point(0.605, 0.505),
                control1: point(0.46, 0.53),
                control2: point(0.54, 0.53)
            )
        case .back:
            path.move(to: point(0.5, 0.16))
            path.addCurve(
                to: point(0.5, 0.505),
                control1: point(0.49, 0.265),
                control2: point(0.49, 0.405)
            )
            path.move(to: point(0.48, 0.22))
            path.addCurve(
                to: point(0.35, 0.3),
                control1: point(0.43, 0.22),
                control2: point(0.375, 0.25)
            )
            path.move(to: point(0.52, 0.22))
            path.addCurve(
                to: point(0.65, 0.3),
                control1: point(0.57, 0.22),
                control2: point(0.625, 0.25)
            )
            path.move(to: point(0.397, 0.505))
            path.addCurve(
                to: point(0.5, 0.54),
                control1: point(0.43, 0.53),
                control2: point(0.465, 0.54)
            )
            path.addCurve(
                to: point(0.603, 0.505),
                control1: point(0.535, 0.54),
                control2: point(0.57, 0.53)
            )
        }

        path.move(to: point(0.34, 0.73))
        path.addCurve(
            to: point(0.41, 0.735),
            control1: point(0.36, 0.72),
            control2: point(0.39, 0.72)
        )
        path.move(to: point(0.59, 0.735))
        path.addCurve(
            to: point(0.66, 0.73),
            control1: point(0.61, 0.72),
            control2: point(0.64, 0.72)
        )

        return path
    }
}

private struct RecoveryZoneButton: View {
    let estimate: MuscleRecoveryEstimate
    let side: RecoveryBodySide
    let isSelected: Bool
    let anatomyRect: CGRect
    let action: () -> Void

    private var role: AppSignalRole {
        estimate.status.signalRole
    }

    var body: some View {
        let zoneRect = layout.frame(in: anatomyRect)

        Button(action: action) {
            zoneGlyph
                .fill(role.color.opacity(fillOpacity))
                .overlay {
                    if isSelected {
                        zoneGlyph
                            .stroke(AppPalette.canvas, lineWidth: 3.5)

                        zoneGlyph
                            .stroke(role.color, lineWidth: 1.4)
                    }
                }
                .scaleEffect(isSelected ? 1.035 : 1)
                .contentShape(zoneGlyph)
                .frame(width: zoneRect.width, height: zoneRect.height)
                .position(x: zoneRect.midX, y: zoneRect.midY)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(estimate.group.displayName), \(estimate.status.displayName)")
        .accessibilityValue(
            estimate.status == .noRecentSignal
                ? "No recent training signal"
                : estimate.status.displayName
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("muscle_recovery_zone_\(side.rawValue.lowercased())_\(estimate.group.rawValue)")
    }

    private var fillOpacity: Double {
        if estimate.status == .noRecentSignal { return isSelected ? 0.42 : 0.24 }
        return isSelected ? 0.96 : 0.78
    }

    private var zoneGlyph: RecoveryZoneShape {
        RecoveryZoneShape(group: estimate.group, side: side)
    }

    private var layout: RecoveryZoneLayout {
        RecoveryZoneLayout(group: estimate.group, side: side)
    }
}

private struct RecoveryZoneLayout {
    let group: RecoveryMuscleGroup
    let side: RecoveryBodySide

    func frame(in anatomyRect: CGRect) -> CGRect {
        let normalized: CGRect
        switch (side, group) {
        case (_, .shoulders): normalized = CGRect(x: 0.235, y: 0.16, width: 0.53, height: 0.115)
        case (.front, .chest): normalized = CGRect(x: 0.335, y: 0.215, width: 0.33, height: 0.13)
        case (_, .arms): normalized = CGRect(x: 0.14, y: 0.205, width: 0.72, height: 0.325)
        case (.front, .core): normalized = CGRect(x: 0.39, y: 0.33, width: 0.22, height: 0.19)
        case (_, .legs): normalized = CGRect(x: 0.285, y: 0.545, width: 0.43, height: 0.435)
        case (.back, .back): normalized = CGRect(x: 0.305, y: 0.19, width: 0.39, height: 0.33)
        default: normalized = .zero
        }

        return CGRect(
            x: anatomyRect.minX + anatomyRect.width * normalized.minX,
            y: anatomyRect.minY + anatomyRect.height * normalized.minY,
            width: anatomyRect.width * normalized.width,
            height: anatomyRect.height * normalized.height
        )
    }
}

private struct RecoveryZoneShape: Shape {
    let group: RecoveryMuscleGroup
    let side: RecoveryBodySide

    func path(in rect: CGRect) -> Path {
        switch group {
        case .shoulders:
            shoulderCaps(in: rect, rear: side == .back)
        case .chest:
            chestPanels(in: rect)
        case .arms:
            armPanels(in: rect, rear: side == .back)
        case .core:
            coreSegments(in: rect)
        case .legs:
            legPanels(in: rect, rear: side == .back)
        case .back:
            backPanels(in: rect)
        }
    }

    private func shoulderCaps(in rect: CGRect, rear: Bool) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }
        var left = Path()
        left.move(to: point(0.46, rear ? 0.48 : 0.42))
        left.addCurve(
            to: point(0.08, rear ? 0.22 : 0.12),
            control1: point(0.34, 0.14),
            control2: point(0.19, 0.05)
        )
        left.addCurve(
            to: point(0.12, 0.86),
            control1: point(0.01, 0.43),
            control2: point(0.03, 0.72)
        )
        left.addCurve(
            to: point(0.42, 0.72),
            control1: point(0.22, 0.9),
            control2: point(0.34, 0.82)
        )
        left.closeSubpath()
        return paired(left, in: rect)
    }

    private func chestPanels(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }
        var left = Path()
        left.move(to: point(0.485, 0.08))
        left.addCurve(
            to: point(0.04, 0.24),
            control1: point(0.34, 0.04),
            control2: point(0.16, 0.08)
        )
        left.addCurve(
            to: point(0.12, 0.82),
            control1: point(0.02, 0.5),
            control2: point(0.04, 0.72)
        )
        left.addCurve(
            to: point(0.485, 0.7),
            control1: point(0.25, 0.9),
            control2: point(0.4, 0.84)
        )
        left.closeSubpath()
        return paired(left, in: rect)
    }

    private func armPanels(in rect: CGRect, rear: Bool) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }
        var upperArm = Path()
        upperArm.move(to: point(0.24, 0.04))
        upperArm.addCurve(
            to: point(0.08, 0.18),
            control1: point(0.18, rear ? 0.03 : 0.07),
            control2: point(0.11, 0.1)
        )
        upperArm.addCurve(
            to: point(0.12, 0.49),
            control1: point(0.05, 0.28),
            control2: point(0.06, 0.4)
        )
        upperArm.addCurve(
            to: point(0.23, 0.43),
            control1: point(0.16, 0.51),
            control2: point(0.21, 0.48)
        )
        upperArm.addCurve(
            to: point(0.31, 0.12),
            control1: point(0.26, 0.33),
            control2: point(0.29, 0.21)
        )
        upperArm.closeSubpath()

        var forearm = Path()
        forearm.move(to: point(0.115, 0.5))
        forearm.addCurve(
            to: point(0.035, 0.94),
            control1: point(0.075, 0.62),
            control2: point(0.045, 0.82)
        )
        forearm.addCurve(
            to: point(0.135, 0.98),
            control1: point(0.065, 1),
            control2: point(0.105, 1)
        )
        forearm.addCurve(
            to: point(0.225, 0.49),
            control1: point(0.17, 0.82),
            control2: point(0.205, 0.62)
        )
        forearm.closeSubpath()

        var path = paired(upperArm, in: rect)
        path.addPath(paired(forearm, in: rect))
        return path
    }

    private func coreSegments(in rect: CGRect) -> Path {
        var path = Path()
        let horizontalGap = rect.width * 0.08
        let verticalGap = rect.height * 0.065
        let segmentWidth = (rect.width - horizontalGap) / 2
        let segmentHeight = (rect.height - verticalGap * 2) / 3

        for row in 0..<3 {
            let y = CGFloat(row) * (segmentHeight + verticalGap)
            let corner = CGSize(width: segmentWidth * 0.34, height: segmentHeight * 0.34)
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY + y, width: segmentWidth, height: segmentHeight),
                cornerSize: corner
            )
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX + segmentWidth + horizontalGap,
                    y: rect.minY + y,
                    width: segmentWidth,
                    height: segmentHeight
                ),
                cornerSize: corner
            )
        }
        return path
    }

    private func legPanels(in rect: CGRect, rear: Bool) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }
        var thigh = Path()
        thigh.move(to: point(0.43, 0.02))
        thigh.addCurve(
            to: point(0.08, 0.08),
            control1: point(0.31, rear ? 0.08 : 0.01),
            control2: point(0.16, 0.02)
        )
        thigh.addCurve(
            to: point(0.14, 0.48),
            control1: point(0.04, 0.2),
            control2: point(0.06, 0.38)
        )
        thigh.addCurve(
            to: point(0.38, 0.5),
            control1: point(0.2, 0.54),
            control2: point(0.31, 0.55)
        )
        thigh.addCurve(
            to: point(0.43, 0.02),
            control1: point(0.42, 0.35),
            control2: point(0.44, 0.17)
        )
        thigh.closeSubpath()

        var calf = Path()
        calf.move(to: point(0.14, 0.54))
        calf.addCurve(
            to: point(0.065, 0.75),
            control1: point(0.08, 0.59),
            control2: point(0.045, 0.68)
        )
        calf.addCurve(
            to: point(0.13, 0.98),
            control1: point(0.075, 0.84),
            control2: point(0.09, 0.94)
        )
        calf.addCurve(
            to: point(0.31, 0.71),
            control1: point(0.19, 0.94),
            control2: point(0.27, 0.82)
        )
        calf.addCurve(
            to: point(0.35, 0.54),
            control1: point(0.33, 0.65),
            control2: point(0.35, 0.59)
        )
        calf.closeSubpath()

        var path = paired(thigh, in: rect)
        path.addPath(paired(calf, in: rect))
        return path
    }

    private func backPanels(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = {
            CGPoint(x: rect.minX + rect.width * $0, y: rect.minY + rect.height * $1)
        }
        var trapezius = Path()
        trapezius.move(to: point(0.5, 0.02))
        trapezius.addLine(to: point(0.18, 0.17))
        trapezius.addCurve(
            to: point(0.46, 0.42),
            control1: point(0.25, 0.24),
            control2: point(0.36, 0.34)
        )
        trapezius.addLine(to: point(0.5, 0.52))
        trapezius.addLine(to: point(0.54, 0.42))
        trapezius.addCurve(
            to: point(0.82, 0.17),
            control1: point(0.64, 0.34),
            control2: point(0.75, 0.24)
        )
        trapezius.closeSubpath()

        var leftLat = Path()
        leftLat.move(to: point(0.45, 0.32))
        leftLat.addCurve(
            to: point(0.08, 0.24),
            control1: point(0.33, 0.23),
            control2: point(0.18, 0.2)
        )
        leftLat.addCurve(
            to: point(0.18, 0.73),
            control1: point(0.06, 0.4),
            control2: point(0.1, 0.62)
        )
        leftLat.addCurve(
            to: point(0.43, 0.96),
            control1: point(0.27, 0.84),
            control2: point(0.36, 0.91)
        )
        leftLat.addCurve(
            to: point(0.45, 0.32),
            control1: point(0.45, 0.73),
            control2: point(0.46, 0.5)
        )
        leftLat.closeSubpath()

        var path = trapezius
        path.addPath(paired(leftLat, in: rect))
        return path
    }

    private func paired(_ leftPath: Path, in rect: CGRect) -> Path {
        var path = leftPath
        var transform = CGAffineTransform(translationX: rect.midX, y: 0)
        transform = transform.scaledBy(x: -1, y: 1)
        transform = transform.translatedBy(x: -rect.midX, y: 0)
        path.addPath(leftPath.applying(transform))
        return path
    }
}

private struct RecoveryEvidencePanel: View {
    let evidence: RecoveryRegionEvidence
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(evidence.group.displayName).appTextRole(.sectionTitle)
            Label(evidence.state.title, systemImage: evidence.state == .stopAndChange ? "exclamationmark.triangle" : "list.bullet.clipboard")
                .appTextRole(.control).foregroundStyle(evidence.state == .stopAndChange ? AppPalette.caution : AppPalette.brandText)
            Text(evidence.explanation).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Updated \(evidence.asOf.formatted(date: .abbreviated, time: .shortened)) · \(evidence.modelVersion)")
                .appTextRole(.caption).foregroundStyle(.secondary)
            RecoveryEvidenceRow(icon: "list.number", title: "Measured strength exposure", value: "\(evidence.sevenDayWorkingSets) working sets in 7 days. Warm-ups and diary summaries excluded.")
            if evidence.training.isEmpty {
                Text("No eligible strength session found in the available last 14 days.").appTextRole(.secondary).foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Training evidence · \(evidence.training.count) sessions") {
                    ForEach(evidence.training) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.workingSets) working sets · \(item.date.formatted(date: .abbreviated, time: .shortened))").appTextRole(.control)
                            Text(item.exerciseNames.joined(separator: ", ")).appTextRole(.secondary).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, AppSpacing.compact)
                    }
                }
            }
            if evidence.group == .legs {
                RecoveryEvidenceRow(icon: "figure.run", title: "Running context", value: evidence.runs.isEmpty ? "No eligible run of at least 10 minutes and 100 m in available history. Other running exposure is unknown." : "\(evidence.runs.count) recorded runs in 7 days; separate duration context, never converted into strength sets.")
                ForEach(evidence.runs) { run in
                    Text("\(run.movingMinutes.formatted(.number.precision(.fractionLength(0...1)))) min · \(run.date.formatted(date: .abbreviated, time: .shortened)) · \(run.source)")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            RecoveryEvidenceRow(icon: "bed.double.fill", title: "Sleep evidence", value: sleepText)
            RecoveryEvidenceRow(icon: "person.text.rectangle", title: "Subjective check-in", value: checkInText)
        }
        .appSurface(.quiet).accessibilityElement(children: .contain)
        .accessibilityLabel("Selected muscle recovery evidence").accessibilityIdentifier("muscle_recovery_evidence")
    }
    private var sleepText: String {
        let date = evidence.sleepDate?.formatted(date: .abbreviated, time: .shortened) ?? "date unknown"
        switch evidence.sleepFreshness {
        case .current: return "Recent sleep score \(evidence.sleepScore.map(String.init) ?? "Unknown") · \(date). Not a direct measurement of muscle readiness."
        case .stale: return "Stale sleep · \(date). Excluded from the current planning signal."
        case .unknown: return "Unknown. A recent dated sleep score is unavailable."
        }
    }
    private var checkInText: String {
        guard let value = evidence.checkIn else { return "Unknown. Add an optional dated soreness or fatigue check-in." }
        return "\(value.observedAt.formatted(date: .abbreviated, time: .shortened)) · Soreness \(value.soreness?.title ?? "Unknown"), fatigue \(value.fatigue?.title ?? "Unknown")" + (evidence.checkInIsFresh ? "." : ". Stale; not treated as a current observation.")
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
        case .noRecentSignal: "Unknown"
        case .fatigued: "Review training"
        case .recovering: "Accumulated exposure"
        case .nearlyReady: "Recent training"
        case .ready: "Lower recent load"
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
        estimate.lastTrained == nil ? "No eligible recent training evidence. Readiness is unknown."
            : "Training exposure is a planning signal, not measured tissue readiness."
    }
}
