import MyFitPlateCore
import SwiftUI

struct NutritionBatchReviewView: View {
    @EnvironmentObject private var diary: DailyLogService
    @Environment(\.dismiss) private var dismiss
    @State private var batch: NutritionDayBatchReview
    @State private var latest: [DailyLog] = []
    @State private var confirmed = false
    @State private var saving = false
    @State private var message: String?
    private let store = EditorDraftStore()
    init(initial: NutritionDayBatchReview) { _batch = State(initialValue: initial) }
    private var ownsBatch: Bool { batch.ownerID == DIContainer.shared.authService.currentUserID }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(batch.entries.count - batch.unresolvedCount) of \(batch.entries.count) dates saved")
                        .appTextRole(.sectionTitle).accessibilityIdentifier("review_batch_progress")
                    Text("Open a date to review its food. An empty log means intake is unknown.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Section("Selected dates") {
                    ForEach(batch.entries) { entry in
                        DisclosureGroup {
                            let shown = entry.result == .changed ? latest.first(where: { NutritionDayReviewRules.key($0) == entry.id }) ?? entry.reviewedLog : entry.reviewedLog
                            if shown.meals.flatMap(\.foodItems).isEmpty { Text("No recorded food · intake unknown") }
                            ForEach(shown.meals) { meal in
                                Text(meal.name).font(.headline)
                                ForEach(meal.foodItems) { food in
                                    LabeledContent(food.name, value: "\(food.calories.formatted(.number.precision(.fractionLength(0)))) cal")
                                }
                            }
                            if entry.result == .changed {
                                Text("This day's food or review changed. These are the latest entries; inspect them before including this date again.")
                                Button("Use reviewed entries") {
                                    guard let log = latest.first(where: { NutritionDayReviewRules.key($0) == entry.id }) else { return }
                                    do { try batch.reviewLatest(log, currentOwner: DIContainer.shared.authService.currentUserID ?? ""); confirmed = false; try checkpoint() } catch { message = error.localizedDescription }
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NutritionDayReviewRules.displayDate(entry.reviewedLog).formatted(date: .abbreviated, time: .omitted))
                                Text(label(entry.result)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("review_batch_\(entry.id)")
                    }
                }
                if batch.entries.contains(where: { $0.result == .changed }) {
                    Section {
                        Label("Changed dates need another review before they can be saved.", systemImage: "exclamationmark.circle")
                            .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    }
                }
            }.appFormStyle()
                .safeAreaInset(edge: .bottom, spacing: 0) { reviewActions }
                .navigationTitle("Review selected days").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(saving) } }
                .task { await restore() }
        }.interactiveDismissDisabled(saving).disabled(!ownsBatch)
    }
    private var reviewActions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let message {
                Text(message).appTextRole(.secondary).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if batch.unresolvedCount > 0 {
                Toggle("Everything I ate is included", isOn: $confirmed)
                    .appTextRole(.body)
                    .accessibilityLabel("Everything I ate is included on the selected, unchanged dates")
                    .accessibilityIdentifier("review_batch_confirm")
                Button(saving ? "Saving dates…" : "Save remaining reviews") { Task { await save() } }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!confirmed || saving || !ownsBatch)
                    .accessibilityIdentifier("review_batch_save")
                Text("Saved dates stay saved. Changed dates are excluded until reviewed.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.row)
        .background(AppPalette.canvas)
    }

    private func label(_ result: NutritionDayBatchReview.Result) -> String {
        switch result {
        case .awaitingReview: "Awaiting your review"
        case .saving: "Saving…"
        case .saved: "Saved · complete"
        case .retry: "Not confirmed · retry available"
        case .changed: "Changed · inspect latest entries"
        }
    }
    private func checkpoint() throws {
        guard ownsBatch else { throw NutritionDayReviewError.changed }
        try store.save(batch, userID: batch.ownerID, scope: NutritionDayBatchReview.scope)
    }
    private func fetchLatest() async -> [DailyLog]? {
        guard ownsBatch, let first = batch.entries.map(\.reviewedLog.date).min(), let last = batch.entries.map(\.reviewedLog.date).max() else { return nil }
        do {
            let values = try await DIContainer.shared.nutritionRepository.fetchDailyHistoryForReview(userID: batch.ownerID,
                startDate: first.addingTimeInterval(-172_800), endDate: last.addingTimeInterval(172_800))
            guard ownsBatch else { return nil }
            // Missing documents retain their explicitly inspected empty snapshots.
            return batch.entries.map { entry in values.first { NutritionDayReviewRules.key($0) == entry.id } ?? DailyLog(id: entry.id, date: entry.reviewedLog.date, meals: []) }
        } catch {
            guard ownsBatch else { return nil }
            message = "Saved days couldn't be checked. Your review is kept; retry when connected."; return nil
        }
    }
    private func restore() async {
        guard ownsBatch else { return }
        do {
            if let values = await fetchLatest() { latest = values; try batch.reconcile(with: values, currentOwner: batch.ownerID) }
            try checkpoint()
        } catch { message = error.localizedDescription }
    }
    private func save() async {
        guard ownsBatch, confirmed, !saving else { return }
        saving = true; defer { saving = false; confirmed = false }
        do {
            guard let values = await fetchLatest() else { return }
            latest = values; try batch.reconcile(with: values, currentOwner: batch.ownerID); try checkpoint()
            for entry in batch.entries where entry.result == .retry || entry.result == .awaitingReview {
                guard ownsBatch else { return }
                batch.mark(entry.id, result: .saving); try checkpoint()
                let success = await withCheckedContinuation { continuation in
                    diary.setNutritionDayStatus(batch.status, for: batch.ownerID, date: entry.reviewedLog.date, reviewedLog: entry.reviewedLog) { continuation.resume(returning: $0) }
                }
                guard ownsBatch else { return }
                batch.mark(entry.id, result: success ? .saved : .retry); try checkpoint()
            }
            if let values = await fetchLatest() { latest = values; try batch.reconcile(with: values, currentOwner: batch.ownerID); try checkpoint() }
            message = batch.unresolvedCount == 0 ? "All selected reviews are saved." : "Saved dates are kept. Review changed dates or retry the remaining dates."
        } catch { message = error.localizedDescription }
    }
}
