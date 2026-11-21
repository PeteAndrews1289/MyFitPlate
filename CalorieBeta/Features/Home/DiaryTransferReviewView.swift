import SwiftUI
import MyFitPlateCore

struct DiaryTransferReviewView: View {
    static let didClose = Notification.Name("DiaryTransferReviewDidClose")
    @ObservedObject var session: DiaryTransferSession
    @StateObject private var history: DiaryTransferHistoryStore
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss
    @State private var receiptRecorded = false
    @State private var localError: String?
    @ObservedObject private var healthSync = TransferHealthSyncQueue.shared

    init(session: DiaryTransferSession) {
        self.session = session
        _history = StateObject(wrappedValue: DiaryTransferHistoryStore(userID: session.userID))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                if let draft = session.draft {
                    Section {
                        Text(draft.mode == .copy ? "Copy the saved nutrition and portions. The original entries stay in place." : "Move these exact entries. They stay in their original day until the whole move is accepted.")
                            .appTextRole(.secondary)
                        LabeledContent("From", value: dayLabel(draft.source))
                        Text("\(draft.entries.count) \(draft.entries.count == 1 ? "food available" : "foods available")")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    if let receipt = session.receipt {
                        acceptedSection(receipt).id("diary_transfer_receipt")
                    } else {
                        destinationSection(draft)
                        Section("Foods and portions") {
                            ForEach(draft.entries) { entry in entryRow(entry, mode: draft.mode) }
                        }
                        .disabled(session.isFrozen || session.isSaving)
                        Section {
                            if draft.mode == .move, draft.source.dayKey == draft.destination.dayKey,
                               draft.entries.filter(\.isIncluded).contains(where: { $0.originalMealName.caseInsensitiveCompare($0.destinationMealName) == .orderedSame }) {
                                Text("Choose another meal or day for every food you want to move.")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                            if session.isFrozen {
                                Text("This request is kept exactly as reviewed. Retry uses the same food identities and destination.")
                                    .appTextRole(.secondary)
                            }
                        }
                    }
                }
                if session.isFrozen {
                    Section("Recovery") {
                        Button("Check saved status") { recover(cancel: false) }
                            .disabled(session.isSaving).accessibilityIdentifier("diary_transfer_check_status")
                        if session.receipt == nil {
                            Text("Cancellation checks the server first. A transfer that was already accepted remains saved.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            Button("Cancel pending transfer", role: .destructive) { recover(cancel: true) }
                                .disabled(session.isSaving).accessibilityIdentifier("diary_transfer_cancel_pending")
                        }
                    }
                }
            }.appFormStyle()
            .navigationTitle(session.draft?.mode == .move ? "Move food" : "Copy food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(session.isSaving)
                }
                if !session.isFrozen, session.draft != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Discard", role: .destructive) { if session.discardProposal() { dismiss() } }
                            .disabled(session.isSaving).accessibilityIdentifier("diary_transfer_discard")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .interactiveDismissDisabled(session.isSaving)
            .onDisappear {
                NotificationCenter.default.post(name: Self.didClose, object: nil, userInfo: ["userID": session.userID])
            }
            .task {
                if let receipt = session.receipt {
                    receiptRecorded = history.record(receipt)
                    if receipt.command.mode == .copy {
                        await dailyLogService.retryDiaryTransferHealth(receipt)
                        localError = dailyLogService.diaryTransferErrorMessage
                    }
                }
            }
            .onChange(of: receiptPresentationKey, initial: true) { _, key in
                if key != nil { scroll.scrollTo("diary_transfer_receipt", anchor: .top) }
            }
            }
        }
    }

    private var receiptPresentationKey: String? {
        session.receipt.map { $0.id.uuidString + ($0.undoneAt == nil ? ":accepted" : ":undone") }
    }

    private func destinationSection(_ draft: DiaryTransferDraft) -> some View {
        Section("To") {
            HStack(spacing: AppSpacing.row) {
                Button { selectDestination(offset: 0, from: draft.destination) } label: {
                    Text("Today").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("diary_transfer_today")
                Button { selectDestination(offset: -1, from: draft.destination) } label: {
                    Text("Yesterday").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("diary_transfer_yesterday")
            }.buttonStyle(.bordered)
            DatePicker("Diary day", selection: Binding(get: { draft.destination.displayDate }, set: { date in
                guard let destination = DiaryDayContext(userID: session.userID, date: date, timeZone: draft.destination.timeZone) else { return }
                _ = session.updateDraft { $0.destination = destination }
            }), in: ...lastAllowedDate(draft.destination), displayedComponents: .date)
                .environment(\.calendar, draft.destination.calendar)
                .environment(\.timeZone, draft.destination.timeZone)
                .accessibilityIdentifier("diary_transfer_date")
            Text(dayLabel(draft.destination)).appTextRole(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("diary_transfer_destination_day")
            if draft.entries.count > 1 {
                Menu("Set every food's meal") {
                    ForEach(["Breakfast", "Lunch", "Dinner", "Snacks"], id: \.self) { meal in
                        Button(meal) { _ = session.updateDraft { value in
                            for index in value.entries.indices { value.entries[index].destinationMealName = meal }
                        } }
                    }
                }
            }
        }.disabled(session.isFrozen || session.isSaving)
    }

    private func entryRow(_ entry: DiaryTransferDraft.Entry, mode: DiaryTransferMode) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Button {
                update(entry.id) { $0.isIncluded.toggle() }
            } label: {
                HStack(alignment: .top) {
                    Image(systemName: entry.isIncluded ? "checkmark.circle.fill" : "circle").appFont(size: 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.originalFood.name).appTextRole(.body).fontWeight(.semibold)
                        Text("\(entry.originalMealName) · \(entry.originalFood.servingSize)")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }.foregroundStyle(AppPalette.text).frame(minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
                .accessibilityValue(entry.isIncluded ? "Selected" : "Excluded")
                .accessibilityIdentifier("diary_transfer_select_\(entry.id)")
            if entry.isIncluded {
                Picker("Destination meal", selection: Binding(get: { entry.destinationMealName }, set: { meal in
                    update(entry.id) { $0.destinationMealName = meal }
                })) {
                    ForEach(Array(Set(["Breakfast", "Lunch", "Dinner", "Snacks", entry.originalMealName, entry.destinationMealName])).sorted(), id: \.self) { meal in Text(meal).tag(meal) }
                }.appFont(size: 17).frame(minHeight: 44)
                    .accessibilityIdentifier("diary_transfer_meal_\(entry.id)")
                if mode == .copy {
                    Stepper(value: Binding(get: { entry.multiplier }, set: { amount in update(entry.id) { $0.multiplier = amount } }), in: 0.25...10, step: 0.25) {
                        Text("\(entry.multiplier.formatted(.number.precision(.fractionLength(0...2)))) × saved portion")
                            .appFont(size: 17).fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("diary_transfer_portion_\(entry.id)")
                }
                Text("\(Int((entry.originalFood.calories * entry.multiplier).rounded()).formatted()) cal")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }

    private func acceptedSection(_ receipt: DiaryTransferReceipt) -> some View {
        Section {
            Label(receipt.undoneAt != nil ? "Change undone" : receipt.command.mode == .copy ? "Foods copied" : "Foods moved", systemImage: "checkmark.circle")
                .foregroundStyle(AppPalette.brandText).accessibilityIdentifier("diary_transfer_accepted")
                .accessibilityValue(receipt.undoneAt != nil ? "Undone" : "Accepted")
            Text("\(receipt.placements.count) \(receipt.placements.count == 1 ? "food" : "foods") · \(dayLabel(receipt.command.destination))")
                .fixedSize(horizontal: false, vertical: true)
            Text("Undo checks these exact entries and keeps newer, unrelated changes.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if receipt.command.mode == .move {
                Text("Apple Health keeps the original consumption date when you move a diary entry.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            } else if healthSync.status.pendingCount > 0 || healthSync.status.message != nil {
                Text("Health sync for this account: \(healthSync.status.message ?? "changes pending")")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                Button("Retry Health sync") {
                    Task {
                        await dailyLogService.retryDiaryTransferHealth(receipt)
                        localError = dailyLogService.diaryTransferErrorMessage
                    }
                }
                    .disabled(healthSync.status.isWorking)
            }
            if receipt.undoneAt == nil {
                Button(session.isSaving ? "Undoing…" : "Undo this change") { perform(undo: true) }
                    .disabled(session.isSaving).accessibilityIdentifier("diary_transfer_undo")
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: AppSpacing.compact) {
            if let message = session.errorMessage ?? localError ?? history.errorMessage {
                Text(message).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("diary_transfer_error")
            }
            if session.receipt == nil, let draft = session.draft {
                Text(summary(draft)).appFont(size: 17, weight: .semibold)
                    .accessibilityIdentifier("diary_transfer_total")
                let count = draft.entries.filter(\.isIncluded).count
                if count == 0 { Text("Select at least one food to continue.").appTextRole(.caption).foregroundStyle(.secondary) }
                if count > 100 { Text("Select up to 100 foods per change.").appTextRole(.caption).foregroundStyle(.secondary) }
            }
            if session.receipt != nil, session.checkpoint?.undoSubmitted == true {
                Button("Check status to finish") { recover(cancel: false) }
                    .buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isSaving)
                    .accessibilityIdentifier("diary_transfer_check_to_finish")
            } else if session.receipt != nil {
                Button(receiptRecorded ? "Done" : "Keep receipt and finish") {
                    guard let receipt = session.receipt else { return }
                    receiptRecorded = history.record(receipt)
                    if receiptRecorded, session.finish() { dismiss() }
                }.buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isSaving)
                    .accessibilityIdentifier("diary_transfer_done")
            } else if session.draft != nil {
                Button(session.isSaving ? "Saving…" : session.isFrozen ? "Retry transfer" : session.draft?.mode == .move ? "Move selected food" : "Copy selected food") { perform(undo: false) }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(session.isSaving || !canSubmit)
                    .accessibilityIdentifier("diary_transfer_submit")
            }
        }.padding(AppSpacing.row).background(.bar)
    }

    private var canSubmit: Bool {
        guard let draft = session.draft else { return false }
        return session.isFrozen || (try? draft.freeze()) != nil
    }

    private func perform(undo: Bool) {
        localError = nil
        Task { @MainActor in
            guard let result = await dailyLogService.performDiaryTransfer(session, undo: undo) else {
                localError = dailyLogService.diaryTransferErrorMessage; return
            }
            receiptRecorded = history.record(result.receipt)
            if !receiptRecorded { localError = history.errorMessage }
        }
    }

    private func recover(cancel: Bool) {
        localError = nil
        Task { @MainActor in
            if await dailyLogService.resolveDiaryTransferStatus(session, cancelPending: cancel) { dismiss(); return }
            if let receipt = session.receipt { receiptRecorded = history.record(receipt) }
            localError = dailyLogService.diaryTransferErrorMessage ?? history.errorMessage
        }
    }

    private func selectDestination(offset: Int, from day: DiaryDayContext) {
        guard let today = DiaryDayContext(userID: session.userID, date: day.calendar.startOfDay(for: Date()), timeZone: day.timeZone),
              let selected = today.adding(days: offset) else { return }
        _ = session.updateDraft { $0.destination = selected }
    }

    private func update(_ id: String, edit: (inout DiaryTransferDraft.Entry) -> Void) {
        _ = session.updateDraft { draft in
            guard let index = draft.entries.firstIndex(where: { $0.id == id }) else { return }
            edit(&draft.entries[index])
        }
    }

    private func summary(_ draft: DiaryTransferDraft) -> String {
        let selected = draft.entries.filter(\.isIncluded)
        let calories = selected.reduce(0) { $0 + $1.originalFood.calories * $1.multiplier }
        return "\(selected.count) \(selected.count == 1 ? "food" : "foods") · \(Int(calories.rounded()).formatted()) cal"
    }

    private func dayLabel(_ day: DiaryDayContext) -> String {
        let formatter = DateFormatter(); formatter.calendar = day.calendar; formatter.timeZone = day.timeZone
        formatter.dateStyle = .medium
        return formatter.string(from: day.displayDate)
    }

    private func lastAllowedDate(_ day: DiaryDayContext) -> Date {
        let start = day.calendar.startOfDay(for: Date())
        return (day.calendar.date(byAdding: .day, value: 1, to: start) ?? Date()).addingTimeInterval(-1)
    }
}

struct DiaryTransferHistoryView: View {
    let userID: String
    @StateObject private var history: DiaryTransferHistoryStore
    @State private var review: Review?
    @State private var message: String?
    private struct Review: Identifiable { let id = UUID(); let session: DiaryTransferSession }

    init(userID: String) { self.userID = userID; _history = StateObject(wrappedValue: DiaryTransferHistoryStore(userID: userID)) }

    var body: some View {
        NavigationStack {
            List {
                Section { Text("Your last 20 accepted copy and move changes. Undo checks the original entries before changing either day.").appTextRole(.secondary) }
                if let message = message ?? history.errorMessage { Text(message).foregroundStyle(AppPalette.caution) }
                if history.receipts.isEmpty { Text("Copied and moved foods will appear here.").foregroundStyle(.secondary) }
                ForEach(history.receipts) { receipt in
                    Button {
                        let session = DiaryTransferSession(userID: userID)
                        if session.prepareUndo(of: receipt) { review = Review(session: session) } else { message = session.errorMessage ?? "Finish your current food transfer before opening another change." }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.undoneAt != nil ? "Undone" : receipt.command.mode == .copy ? "Copied foods" : "Moved foods")
                            Text("\(receipt.placements.count) \(receipt.placements.count == 1 ? "food" : "foods") · \(receipt.acceptedAt.formatted(date: .abbreviated, time: .shortened))")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("diary_transfer_history_\(receipt.id.uuidString)")
                }
            }.appFormStyle().navigationTitle("Food changes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $review, onDismiss: { history.reload() }) { value in DiaryTransferReviewView(session: value.session) }
        }
    }

    @Environment(\.dismiss) private var dismiss
}
