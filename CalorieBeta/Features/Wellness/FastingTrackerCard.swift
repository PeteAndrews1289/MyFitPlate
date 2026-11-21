import MyFitPlateCore
import SwiftUI

struct FastingTrackerCard: View {
    @ObservedObject private var fastingManager: FastingManager
    @State private var selectedFastDuration = 16
    private let fastOptions = [12, 14, 16, 18, 20]

    init(manager: FastingManager = .shared) { _fastingManager = ObservedObject(wrappedValue: manager) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(
                eyebrow: "Optional timer",
                title: fastingManager.isFasting ? "Fast in progress" : "Fasting timer",
                subtitle: "Saved to this account. The Lock Screen display is optional."
            )
            if let error = fastingManager.errorMessage {
                Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fasting_save_error")
            }
            if !fastingManager.legacyTimers.isEmpty { legacyRecovery }
            if let session = fastingManager.session {
                activeFastView(session)
            } else {
                readyView
                if let last = fastingManager.lastEndedSession, let end = last.endedAt {
                    Label("Last fast saved · \(format(end.timeIntervalSince(last.startTime)))", systemImage: "checkmark.circle")
                        .appTextRole(.secondary)
                        .accessibilityIdentifier("fasting_completion_receipt")
                }
            }
            if let projection = fastingManager.projectionMessage, fastingManager.isFasting {
                Text(projection).appTextRole(.secondary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fasting_projection_status")
            }
            Text("Fasting is optional and is not appropriate for everyone. Stop if you feel unwell and seek guidance from a qualified clinician when needed.")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { fastingManager.activateAccount(DIContainer.shared.authService.currentUserID) }
    }

    private func activeFastView(_ session: SavedFastSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startTime))
            let remaining = max(0, session.targetEndTime.timeIntervalSince(context.date))
            let progress = min(1, elapsed / max(1, session.targetEndTime.timeIntervalSince(session.startTime)))
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(spacing: AppSpacing.group) {
                    ZStack {
                        Circle().stroke(AppPalette.separator, lineWidth: 12)
                        Circle().trim(from: 0, to: progress)
                            .stroke(AppPalette.brand, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: AppSpacing.compact) {
                            Text(remaining > 0 ? "Remaining" : "Target reached")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            Text(format(remaining)).appFont(size: 30, weight: .bold).monospacedDigit()
                                .accessibilityIdentifier("fasting_remaining")
                            Text("\(format(elapsed)) elapsed").appTextRole(.caption).monospacedDigit()
                        }
                    }
                    .frame(width: 190, height: 190)
                    .accessibilityElement(children: .combine)
                    AppMetricStrip(items: [
                        AppMetricItem(label: "Started", value: session.startTime.formatted(date: .abbreviated, time: .shortened), accent: AppPalette.effort),
                        AppMetricItem(label: "Target", value: session.targetEndTime.formatted(date: .abbreviated, time: .shortened), accent: AppPalette.recovery)
                    ])
                    if remaining == 0 {
                        Text("Your fast continues until you choose End fast.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .appSurface(.emphasized)
                .accessibilityIdentifier("fasting_active_session")
                Button("End fast", role: .destructive) { fastingManager.endFast() }
                    .buttonStyle(AppActionButtonStyle(.secondary))
                    .accessibilityIdentifier("end_fast_button")
            }
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Duration", subtitle: "Choose a target. You can end your timer at any point.")
            Picker("Fasting duration", selection: $selectedFastDuration) {
                ForEach(fastOptions, id: \.self) { hours in Text("\(hours)h").tag(hours) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("fasting_schedule_picker")
            Button("Start fast") { fastingManager.startFast(hours: selectedFastDuration) }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!fastingManager.legacyTimers.isEmpty)
                .accessibilityIdentifier("start_fast_button")
        }
    }

    private var legacyRecovery: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(title: "Recover an older timer",
                subtitle: "This timer predates account-based saving. Restore it only if it belongs to you. Its original start and target will be kept.")
            ForEach(fastingManager.legacyTimers) { timer in
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text("Started \(timer.startTime.formatted(date: .abbreviated, time: .shortened))")
                        .appTextRole(.body)
                    Button("Restore timer") { fastingManager.recoverLegacyTimer(timer) }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                        .disabled(fastingManager.isFasting)
                        .accessibilityIdentifier("fasting_recover_legacy")
                }
            }
        }
        .appSurface(.quiet)
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}

#Preview {
    ScrollView { FastingTrackerCard().padding(AppSpacing.screenHorizontal) }.background(AppPalette.canvas)
}
