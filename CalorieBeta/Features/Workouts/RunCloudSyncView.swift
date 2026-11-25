import SwiftUI
import MyFitPlateCore

/// App-level owner boundary and debounced save/foreground integration. Only saved
/// runner libraries are synchronized; active recording, Health and PHUL stay owned
/// by their existing services.
@MainActor final class RunCloudSyncCoordinator {
    static let shared = RunCloudSyncCoordinator()
    let workouts: RunCloudSyncEngine
    let blocks: RunCloudSyncEngine
    let reviews: RunCloudSyncEngine
    private var debounce: Task<Void, Never>?
    private var ownerID: String?
    private init() {
        let repository = FirestoreRunCloudRepository()
        let plans = RunWorkoutPlanStore()
        let blockStore = RunTrainingBlockStore()
        let reviewStore = RunReviewStore()
        let owner = { DIContainer.shared.authService.currentUserID }
        workouts = RunCloudSyncEngine(scope: .workouts, repository: repository, currentOwner: owner,
            snapshot: { try plans.cloudSnapshot(userID: $0) },
            apply: { try plans.applyCloudSnapshot($0, expectedFingerprint: $1, userID: $2) })
        blocks = RunCloudSyncEngine(scope: .blocks, repository: repository, currentOwner: owner,
            snapshot: { try blockStore.cloudSnapshot(userID: $0) },
            apply: { try blockStore.applyCloudSnapshot($0, expectedFingerprint: $1, userID: $2) })
        reviews = RunCloudSyncEngine(scope: .reviews, repository: repository, currentOwner: owner,
            snapshot: { try reviewStore.cloudSnapshot(userID: $0) },
            apply: { try reviewStore.applyCloudSnapshot($0, expectedFingerprint: $1, userID: $2) })
    }
    var engines: [RunCloudSyncEngine] { [workouts, blocks, reviews] }
    func activate(_ owner: String?) {
        if ownerID != owner { debounce?.cancel(); debounce = nil; ownerID = owner }
        for engine in engines { engine.activate(owner) }
    }
    func requestSync(owner: String?) {
        activate(owner)
        guard owner != nil, !ScreenshotDemoMode.isEnabled else { return }
        debounce?.cancel()
        debounce = Task {
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation() } catch { return }
            guard self.ownerID == owner else { return }
            await self.sync()
        }
    }
    func sync() async {
        guard !ScreenshotDemoMode.isEnabled else { return }
        guard let owner = DIContainer.shared.authService.currentUserID else { activate(nil); return }
        activate(owner)
        for engine in engines {
            guard self.ownerID == owner, DIContainer.shared.authService.currentUserID == owner else { return }
            await engine.sync()
        }
    }
}

@MainActor struct RunCloudSyncView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    private let coordinator = RunCloudSyncCoordinator.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.group) {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Label("Saved across your devices", systemImage: "icloud")
                            .appTextRole(.control)
                        Text("Workouts, training plans and reviewed changes.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if ScreenshotDemoMode.isEnabled {
                        Text("Cloud sync is paused in simulator demo mode.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("run_cloud_demo_notice")
                    }
                    RunCloudSection(engine: coordinator.workouts)
                    RunCloudSection(engine: coordinator.blocks)
                    RunCloudSection(engine: coordinator.reviews)
                    DisclosureGroup("What syncs") {
                        Text("Local drafts and active recordings stay on this device. Sync never replaces raw Health workouts, route evidence, diary records or strength-program progress. Conflicting versions are retained until you review them.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                            .padding(.top, AppSpacing.compact)
                    }
                    .appTextRole(.secondary)
                    .tint(AppPalette.text)
                }.padding(AppSpacing.screenHorizontal)
            }
            .background(AppPalette.canvas)
            .navigationTitle("Running sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Sync now") { Task { await coordinator.sync() } }
                        .disabled(ScreenshotDemoMode.isEnabled)
                        .accessibilityIdentifier("run_cloud_sync_now")
                }
            }
        }
        .accessibilityIdentifier("run_cloud_sync_screen")
        .task {
            guard ownerID != nil, ownerID == DIContainer.shared.authService.currentUserID else { dismiss(); return }
            coordinator.activate(ownerID)
            if !ScreenshotDemoMode.isEnabled { await coordinator.sync() }
        }
        .onReceive(appState.$isUserLoggedIn) { _ in
            if ownerID != DIContainer.shared.authService.currentUserID { dismiss() }
        }
    }
}

@MainActor private struct RunCloudSection: View {
    @ObservedObject var engine: RunCloudSyncEngine
    @State private var selectedConflict: RunCloudConflict?
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack {
                Text(engine.scope.title).appTextRole(.control)
                Spacer()
                if engine.isSyncing { ProgressView() }
            }
            Text(engine.message).appTextRole(.secondary).foregroundStyle(.secondary)
            if let date = engine.lastSyncedAt {
                Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            ForEach(engine.conflicts) { conflict in
                Button { selectedConflict = conflict } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflictTitle(conflict)).appTextRole(.control)
                            Text("\(conflict.versions.count) saved versions · Review changes").appTextRole(.caption)
                        }
                        Spacer(); Image(systemName: "chevron.right")
                    }
                }.buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
            }
        }.appSurface(.quiet)
        .sheet(item: $selectedConflict) { conflict in RunCloudConflictView(engine: engine, conflict: conflict) }
    }
    private func conflictTitle(_ value: RunCloudConflict) -> String {
        if value.key.hasPrefix("plan/"), let data = value.versions.compactMap(\.payload).first,
           let record = try? RunCloudCodec.decode(RunCloudWorkoutRecord.self, data) { return record.plan.name }
        if value.key.hasPrefix("block/") { return "Training block" }
        if value.key.hasPrefix("head/") { return "Run review" }
        return "Saved evidence"
    }
}

@MainActor private struct RunCloudConflictView: View {
    @ObservedObject var engine: RunCloudSyncEngine
    let conflict: RunCloudConflict
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMetricBodyUnits") private var useMetric = Locale.current.measurementSystem != .us
    @State private var choice: RunCloudRevision?
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose the version to use. Previous versions stay saved. A version that would replace accepted run outcomes or corrections cannot be applied.")
                        .font(.subheadline)
                }
                ForEach(Array(conflict.versions.enumerated()), id: \.element.id) { index, version in
                    Section("Saved option \(index + 1)") {
                        Text(summary(version)).textSelection(.enabled)
                        let issue = engine.resolutionIssue(conflict, choosing: version)
                        if let issue { Text(issue).font(.caption).foregroundStyle(AppPalette.caution) }
                        Button { choice = version } label: {
                            Label(choice?.id == version.id ? "Selected" : "Select version",
                                  systemImage: choice?.id == version.id ? "checkmark.circle.fill" : "circle")
                        }
                        .disabled(saving || issue != nil)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(AppPalette.caution) } }
            }
            .appFormStyle()
            .navigationTitle("Review saved versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply version") {
                        guard let choice else { return }
                        saving = true
                        Task {
                            do { try await engine.resolve(conflict, choosing: choice); dismiss() } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(choice == nil || saving || choice.map { engine.resolutionIssue(conflict, choosing: $0) != nil } == true)
                }
            }
        }
    }
    private func summary(_ revision: RunCloudRevision) -> String {
        guard let data = revision.payload else { return "Removed from the active library. Earlier saved versions remain in history." }
        if conflict.key.hasPrefix("plan/"), let record = try? RunCloudCodec.decode(RunCloudWorkoutRecord.self, data) {
            return "\(record.plan.name)\n\(record.plan.subtitle)\n" + record.plan.steps.map { step in [step.title, step.goalText(metric: useMetric), step.targetText(metric: useMetric)].compactMap { $0 }.joined(separator: " · ") }.joined(separator: "\n") + "\n\(record.plan.steps.count) steps · \(record.isFavorite ? "Favorite" : "Not a favorite")"
        }
        if conflict.key.hasPrefix("block/"), let block = try? RunCloudCodec.decode(RunTrainingBlock.self, data) {
            let completed = block.slots.filter { $0.outcome?.state == .recorded }.count
            return "Created \(block.createdAt.formatted(date: .abbreviated, time: .omitted))\n\(block.slots.count) sessions · \(completed) recorded\n\(block.archived ? "Archived" : "Active")\n" + block.slots.map { "\($0.day.date()?.formatted(date: .abbreviated, time: .omitted) ?? "Date unavailable"): \($0.plan.name)" }.joined(separator: "\n")
        }
        if conflict.key.hasPrefix("head/"), let id = try? RunCloudCodec.decode(String.self, data),
           let receiptData = engine.knownPayload(for: "receipt/" + id),
           let receipt = try? RunCloudCodec.decode(RunReviewStore.Receipt.self, receiptData) {
            let date = receipt.acceptedAt.formatted(date: .abbreviated, time: .shortened)
            switch receipt.review.mutation {
            case .annotate(let note): return "Note saved \(date)\n" + note
            case .hide: return "Hidden from MyFitPlate history · \(date)"
            case .restoreOriginal: return "Original run restored · \(date)"
            case .excludeImportPermanently: return "Permanently excluded from MyFitPlate imports · \(date)"
            case .correctManual(let distance, let seconds, let reason): return "Manual correction · \(date)\n\(RunFormat.distanceText(meters: distance, metric: useMetric)) · \(RunFormat.durationText(seconds: seconds)) active\n" + reason
            case .correctPauses(_, let reason): return "Pause correction · \(date)\n" + reason
            }
        }
        return "Accepted history has conflicting changes. Both versions are kept; this evidence cannot be replaced automatically."
    }
}
