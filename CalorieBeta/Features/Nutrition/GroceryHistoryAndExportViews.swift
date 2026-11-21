import MyFitPlateCore
import SwiftUI
import UIKit

struct GroceryChangeHistoryView: View {
    @ObservedObject var checklist: GroceryChecklistSession
    let starting: Date
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewing: GroceryMutationHistoryEntry?
    @State private var reviewingCancelled: GroceryCancelledDraft?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Your last 100 saved shopping changes on this device. Review Undo to restore a change without affecting other purchases.").foregroundStyle(.secondary) }
                if let error = checklist.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                if checklist.history.isEmpty { Text("Your saved shopping changes will appear here.").foregroundStyle(.secondary) }
                if !checklist.cancelledDrafts.isEmpty {
                    Section("Saved cancelled reviews") {
                        ForEach(checklist.cancelledDrafts.reversed()) { draft in
                            VStack(alignment: .leading, spacing: AppSpacing.row) {
                                Text(draft.mutation.title ?? "Cancelled shopping review").appTextRole(.control)
                                if draft.restoredBy != nil { Text("Used in a new accepted review").foregroundStyle(.secondary) } else {
                                    Button("Review against current list") { reviewingCancelled = draft }.frame(minHeight: 44)
                                }
                                Button("Remove only this cancelled draft", role: .destructive) { _ = checklist.discardCancelledDraft(draft) }
                                    .frame(minHeight: 44).disabled(checklist.isSaving)
                            }
                        }
                    }
                }
                ForEach(checklist.history.reversed()) { entry in
                    Section {
                        Text(entry.mutation.title ?? "Shopping change").appTextRole(.control)
                        Text(entry.acceptedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        if let period = entry.mutation.shoppingStartDate { Text("Shopping period: \(period.formatted(date: .abbreviated, time: .omitted))").appTextRole(.caption) }
                        Text("\(entry.mutation.removedIDs.count) removed · \(entry.mutation.upserts.count) added or changed").appTextRole(.secondary)
                        if entry.undoneBy != nil { Text("Undone").foregroundStyle(.secondary) } else {
                            Button("Review Undo") { reviewing = entry }.frame(minHeight: 44)
                                .accessibilityIdentifier("grocery_history_undo_\(entry.id)")
                        }
                    }
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Shopping changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $reviewing) { entry in
                NavigationStack {
                    List {
                        Section("Restore the reviewed rows") {
                            ForEach(entry.mutation.before) { item in Text("\(item.name) · \(item.quantity.formatted()) \(item.unit)") }
                            if entry.mutation.before.isEmpty { Text("Remove only the rows created by this action.") }
                        }
                        Section { Text("Newer changes to these same rows can prevent Undo. Other shopping activity is preserved.").foregroundStyle(.secondary) }
                        if let error = checklist.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                    }.appFormStyle()
                    .buttonStyle(AppListButtonStyle())
                    .navigationTitle("Review shopping Undo").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { reviewing = nil } } }
                    .safeAreaInset(edge: .bottom) {
                        Button(checklist.isSaving ? "Saving Undo…" : "Undo this shopping change") {
                            guard checklist.undo(entry, shoppingStartDate: starting) else { return }
                            Task {
                                await checklist.retry(using: DIContainer.shared.nutritionRepository)
                                onChanged()
                                if checklist.history.first(where: { $0.id == entry.id })?.undoneBy != nil { reviewing = nil }
                            }
                        }.buttonStyle(AppActionButtonStyle(.primary)).disabled(checklist.isSaving)
                            .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                            .accessibilityIdentifier("grocery_history_undo_apply")
                    }
                }
            }
            .sheet(item: $reviewingCancelled) { draft in
                GroceryCancelledReviewView(draft: draft, checklist: checklist, starting: starting, onChanged: onChanged)
            }
        }
    }
}

struct GroceryPendingReviewView: View {
    @ObservedObject var checklist: GroceryChecklistSession
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingCancellation = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Text("Your shopping changes are kept here until saving is confirmed.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    if checklist.isCancelling { Text("Cancellation is still pending. Continue to confirm its result.").foregroundStyle(AppPalette.caution) }
                    ForEach(checklist.checkpoint.operations, id: \.id) { operation in
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(operation.title ?? "Shopping change").appTextRole(.control)
                            if let date = operation.shoppingStartDate { Text("Period: \(date.formatted(date: .abbreviated, time: .omitted))").appTextRole(.secondary) }
                            Text("\(operation.upserts.count) new or changed rows · \(operation.removedIDs.count) removals").appTextRole(.secondary)
                            Text(operation.upserts.map { "\($0.name): \($0.quantity.formatted()) \($0.unit)" }.joined(separator: "\n")).appTextRole(.secondary)
                        }.appSurface(.quiet)
                    }
                    if checklist.pendingCount == 0 { Text("All changes are resolved. Find saved and cancelled reviews in Shopping changes.") }
                    Button("Cancel all pending changes…", role: .destructive) { confirmingCancellation = true }
                        .frame(minHeight: 44).disabled(checklist.isSaving || checklist.pendingCount == 0)
                        .accessibilityIdentifier("grocery_pending_cancel_all")
                }.padding(AppSpacing.screenHorizontal)
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("grocery_pending_review_screen")
            .background(AppPalette.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: AppSpacing.compact) {
                    if let error = checklist.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                    Button(checklist.isSaving ? "Resolving…" : checklist.isCancelling ? "Continue saved cancellation" : "Retry grocery changes") {
                        perform { await checklist.retry(using: $0) }
                    }.buttonStyle(AppActionButtonStyle(.primary)).disabled(checklist.isSaving || checklist.pendingCount == 0 && !checklist.isCancelling)
                        .accessibilityIdentifier("grocery_pending_retry")
                    Button("Check saved status") { perform { await checklist.checkSavedStatus(using: $0) } }
                        .frame(minHeight: 44).disabled(checklist.isSaving || checklist.pendingCount == 0)
                        .accessibilityIdentifier("grocery_pending_status")
                }.padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.row).background(AppPalette.canvas)
            }
            .navigationTitle("Saved shopping changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Resolve ALL pending shopping changes?", isPresented: $confirmingCancellation, titleVisibility: .visible) {
                Button("Cancel all unaccepted changes", role: .destructive) { perform { _ = await checklist.cancelAllPending(using: $0) } }
                Button("Keep pending reviews", role: .cancel) {}
            } message: {
                Text("This covers all \(checklist.pendingCount) pending commands on this device for this account, across shopping periods. Accepted writes remain accepted. Each unaccepted command is permanently fenced; every cancelled desired change is kept for a separate new review. Later dependent changes are kept too.")
            }
        }
    }
    private func perform(_ work: @escaping (NutritionRepositoryProtocol) async -> Void) {
        Task { @MainActor in await work(DIContainer.shared.nutritionRepository); onChanged() }
    }
}

private struct GroceryCancelledReviewView: View {
    let draft: GroceryCancelledDraft
    @ObservedObject var checklist: GroceryChecklistSession
    let starting: Date
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var submitted = false
    @State private var proposal: GroceryListMutation
    init(draft: GroceryCancelledDraft, checklist: GroceryChecklistSession, starting: Date, onChanged: @escaping () -> Void) {
        self.draft = draft; self.checklist = checklist; self.starting = starting; self.onChanged = onChanged
        let ids = draft.mutation.itemIDs
        _proposal = State(initialValue: GroceryListMutation(before: checklist.items.filter { ids.contains($0.id) },
            upserts: draft.mutation.upserts, removedIDs: draft.mutation.removedIDs,
            title: "New review of cancelled shopping values", shoppingStartDate: draft.mutation.shoppingStartDate))
    }
    private var matchingPeriod: Bool { draft.mutation.shoppingStartDate.map { Calendar.current.isDate($0, inSameDayAs: starting) } ?? true }
    var body: some View {
        NavigationStack {
            List {
                Section("Current affected rows") {
                    ForEach(proposal.before) { Text("\($0.name) · \($0.quantity.formatted()) \($0.unit)") }
                    if proposal.before.isEmpty { Text("None of these rows currently exists.").foregroundStyle(.secondary) }
                }
                Section("Desired values from the cancelled review") {
                    ForEach(proposal.upserts) { Text("\($0.name) · \($0.quantity.formatted()) \($0.unit)") }
                    Text("\(proposal.removedIDs.count) selected rows would be removed.").foregroundStyle(.secondary)
                }
                Section {
                    Text("Review these values against the current list before saving a new change. Other rows stay intact.").foregroundStyle(.secondary)
                    if !matchingPeriod { Text("Open the original shopping period before using these saved values.").foregroundStyle(AppPalette.caution) }
                    Toggle("I reviewed the current rows and want these desired values", isOn: $confirmed)
                }
                if let error = checklist.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                if submitted {
                    Section("Frozen review is kept") {
                        Button("Retry this reviewed change") {
                            Task { await checklist.retry(using: DIContainer.shared.nutritionRepository); onChanged()
                                if checklist.history.contains(where: { $0.id == proposal.id }) { dismiss() }
                            }
                        }.frame(minHeight: 44).disabled(checklist.isSaving)
                        Button("Check saved status") {
                            Task { await checklist.checkSavedStatus(using: DIContainer.shared.nutritionRepository); onChanged()
                                if checklist.history.contains(where: { $0.id == proposal.id }) { dismiss() }
                            }
                        }.frame(minHeight: 44).disabled(checklist.isSaving)
                    }
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("New shopping review").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Save new reviewed change") {
                    guard !submitted, checklist.stageReviewedCancelledDraft(draft, proposal: proposal) else { return }
                    submitted = true
                    Task {
                        await checklist.retry(using: DIContainer.shared.nutritionRepository); onChanged()
                        if checklist.history.contains(where: { $0.id == proposal.id }) { dismiss() }
                    }
                }.buttonStyle(AppActionButtonStyle(.primary)).disabled(!confirmed || !matchingPeriod || submitted || checklist.isSaving)
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
            }
        }
    }
}

struct GroceryExportPreviewView: View {
    let items: [GroceryListItem]
    let stock: [PantryItem]
    let starting: Date
    let pendingChanges: Bool
    let stockCoverageAvailable: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var includeChecked = false
    @State private var includeCodes = false
    @State private var notes = ""
    @State private var exportFiles: [URL] = []
    @State private var pdfURL: URL?
    @State private var jsonURL: URL?
    @State private var error: String?
    private var document: GroceryExportDocument {
        GroceryExportRules.document(items: items, stock: stock, starting: starting, includeChecked: includeChecked,
            includeProductCodes: includeCodes, pendingChanges: pendingChanges, stockCoverageAvailable: stockCoverageAvailable, notes: notes)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Snapshot options") {
                    Toggle("Include checked and skipped items", isOn: $includeChecked)
                    Toggle("Include product barcodes", isOn: $includeCodes)
                    TextField("Optional shopping notes", text: $notes, axis: .vertical).lineLimit(2...5)
                    Text("Sharing exports this snapshot. It does not grant access to your account or synchronize a household.").appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Section("Preview") { Text(document.plainText).textSelection(.enabled).appTextRole(.body) }
                Section("Share or print") {
                    ShareLink(item: document.plainText) { Label("Share text checklist", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                    Button("Prepare PDF and structured JSON", action: prepareFiles).frame(minHeight: 44)
                        .accessibilityIdentifier("grocery_prepare_exports")
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Share printable PDF", systemImage: "doc") }.frame(minHeight: 44)
                        Button("Print checklist") {
                            let printer = UIPrintInteractionController.shared
                            printer.printingItem = pdfURL; printer.present(animated: true, completionHandler: nil)
                        }.frame(minHeight: 44)
                    }
                    if let jsonURL { ShareLink(item: jsonURL) { Label("Share structured JSON", systemImage: "curlybraces") }.frame(minHeight: 44) }
                    if let error { Text(error).foregroundStyle(AppPalette.caution) }
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("grocery_share_preview")
            .navigationTitle("Shopping snapshot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: includeChecked) { _, _ in clearFiles() }
            .onChange(of: includeCodes) { _, _ in clearFiles() }
            .onChange(of: notes) { _, _ in clearFiles() }
            .onDisappear(perform: clearFiles)
        }
    }
    private func prepareFiles() {
        clearFiles()
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("myfitplate-grocery-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            exportFiles.append(directory)
            let snapshot = document
            let json = directory.appendingPathComponent("Shopping-list.json")
            try snapshot.jsonData().write(to: json, options: .atomic)
            let pdf = directory.appendingPathComponent("Shopping-list.pdf")
            try Self.pdf(snapshot.plainText).write(to: pdf, options: .atomic)
            jsonURL = json; pdfURL = pdf
        } catch { self.error = "The preview is still available. Export files could not be prepared. " + error.localizedDescription }
    }
    private func clearFiles() {
        for url in exportFiles { try? FileManager.default.removeItem(at: url) }
        exportFiles = []; pdfURL = nil; jsonURL = nil
    }
    private static func pdf(_ text: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 36
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black]
            for line in text.components(separatedBy: .newlines) {
                var remaining = line.isEmpty ? " " : line
                while !remaining.isEmpty {
                    let printable = String(remaining.prefix(600)); remaining.removeFirst(printable.count)
                    let attributed = NSAttributedString(string: printable, attributes: attributes)
                    let height = max(16, attributed.boundingRect(with: CGSize(width: 540, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height + 5)
                    if y + height > 756 { context.beginPage(); y = 36 }
                    attributed.draw(with: CGRect(x: 36, y: y, width: 540, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    y += height
                }
            }
        }
    }
}
