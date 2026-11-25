import Foundation
import Combine

public enum PantryReceiptRowStatus: String, Codable { case ready, pending, accepted, failed }
public struct PantryReceiptRow: Codable, Identifiable {
    public var item: PantryItem
    public var status: PantryReceiptRowStatus
    public var error: String?
    public var id: UUID { item.id }
}
public struct PantryReceiptCheckpoint: Codable {
    public let id: UUID
    public var purchaseDate: Date
    public var rows: [PantryReceiptRow]
    public var isSubmitted: Bool
    /// Older pending imports keep their deployed create-once receipt route.
    public var usesInventoryLedger: Bool? = true
    /// Missing on deployed drafts: those retain their original per-row receipts.
    public var usesWholeReceiptLedger: Bool? = true
    public var sourceDigest: String?
    public var separateImportID: UUID?
    public var ledgerMutation: InventoryMutation?
    public var purchaseDay: DiaryDayContext?
    public var storeName: String?
    public var currency: String?
}

/// W0 preserves each purchase line under its own stable pantry ID. Combining purchases into
/// existing stock needs explicit product/unit mapping and is deliberately left to the stock ledger.
@MainActor
public final class PantryReceiptImportSession: ObservableObject {
    @Published public private(set) var checkpoint: PantryReceiptCheckpoint
    @Published public private(set) var isSaving = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var restoredReview = false
    @Published public private(set) var needsDuplicateDecision = false
    public let userID: String?
    private let store: EditorDraftStore
    private let scope = "pantry-receipt-import"
    private var unreadable = false
    private var expectedFingerprint: String?
    private let historyScope = "pantry-receipt-import-history"
    @Published public private(set) var history: [PantryReceiptHistoryRecord] = []
    @Published public private(set) var historyAvailable = true
    public var items: [PantryItem] { checkpoint.rows.map(\.item) }
    public var isSubmitted: Bool { checkpoint.isSubmitted }
    public var acceptedCount: Int { checkpoint.rows.filter { $0.status == .accepted }.count }
    public var isComplete: Bool { !checkpoint.rows.isEmpty && acceptedCount == checkpoint.rows.count }

    public init(userID: String?, items: [PantryItem] = [], purchaseDate: Date = Date(), store: EditorDraftStore = EditorDraftStore()) {
        self.userID = userID; self.store = store
        checkpoint = PantryReceiptCheckpoint(id: UUID(), purchaseDate: Calendar.current.startOfDay(for: purchaseDate),
            rows: items.map { PantryReceiptRow(item: $0, status: .ready) }, isSubmitted: false)
        checkpoint.purchaseDay = userID.flatMap { DiaryDayContext(userID: $0, date: purchaseDate) }
        guard let userID else { return }
        do {
            if let saved = try store.load(PantryReceiptCheckpoint.self, userID: userID, scope: scope) {
                checkpoint = saved.value; restoredReview = true; expectedFingerprint = try PlanFingerprint.make(saved.value)
            } else if !items.isEmpty { _ = persist(checkpoint) }
        } catch { unreadable = true; errorMessage = "Your previous receipt could not be opened. It is kept on this device; no items have been added." }
        do { history = try store.load([PantryReceiptHistoryRecord].self, userID: userID, scope: historyScope)?.value ?? [] } catch { historyAvailable = false }
    }
    public var duplicateHistory: [PantryReceiptHistoryRecord] {
        let signature = try? PantryReceiptIdentityRules.contentSignature(items: items, purchaseDate: checkpoint.purchaseDate, purchaseDayKey: checkpoint.purchaseDay?.dayKey)
        return history.filter { record in
            record.id != checkpoint.id && (checkpoint.sourceDigest.map { record.sourceDigest == $0 } == true || signature == record.contentSignature)
        }
    }
    public var hasConfirmedSeparateImport: Bool { checkpoint.separateImportID != nil }
    @discardableResult public func updateContext(storeName: String, currency: String) -> Bool {
        guard !isSubmitted, !isSaving else { return false }
        var next = checkpoint
        let store = String(storeName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        next.storeName = store.isEmpty ? nil : store; next.currency = code.isEmpty ? nil : code
        for index in next.rows.indices {
            var evidence = next.rows[index].item.purchaseEvidence ?? PantryPurchaseEvidence(
                originalReceiptName: next.rows[index].item.name, receiptRowQuantity: next.rows[index].item.quantity, receiptRowUnit: next.rows[index].item.unit)
            evidence.storeName = next.storeName; evidence.currency = next.currency
            next.rows[index].item.purchaseEvidence = evidence
        }
        return persist(next)
    }
    @discardableResult public func replaceSource(items: [PantryItem], purchaseDate: Date, digest: String?) -> Bool {
        guard !isSubmitted, !isSaving else { return false }
        var next = checkpoint; next.rows = items.map { PantryReceiptRow(item: $0, status: .ready) }
        next.usesWholeReceiptLedger = true; next.usesInventoryLedger = true
        next.purchaseDate = Calendar.current.startOfDay(for: purchaseDate); next.sourceDigest = digest
        next.purchaseDay = userID.flatMap { DiaryDayContext(userID: $0, date: purchaseDate) }
        next.separateImportID = nil; next.ledgerMutation = nil
        next.storeName = items.compactMap { $0.purchaseEvidence?.storeName }.first
        next.currency = items.compactMap { $0.purchaseEvidence?.currency }.first
        return persist(next)
    }
    @discardableResult public func confirmSeparateImport() -> Bool {
        guard !isSubmitted, !isSaving else { return false }
        var next = checkpoint; next.separateImportID = UUID(); return persist(next)
    }

    @discardableResult
    public func update(items: [PantryItem], purchaseDate: Date) -> Bool {
        guard !isSubmitted, !isSaving else { return false }
        var next = checkpoint; next.purchaseDate = Calendar.current.startOfDay(for: purchaseDate)
        next.purchaseDay = userID.flatMap { DiaryDayContext(userID: $0, date: purchaseDate, timeZone: checkpoint.purchaseDay?.timeZone ?? .current) }
        if let day = next.purchaseDay { next.purchaseDate = day.startOfDay }
        next.rows = items.map { PantryReceiptRow(item: $0, status: .ready) }
        return persist(next)
    }

    public func save(using repository: NutritionRepositoryProtocol) async {
        guard !isSaving, canUseAccount, let userID else { return }
        if !isSubmitted {
            guard PantryPurchaseEvidence(currency: checkpoint.currency).isValid else {
                errorMessage = "Review the currency code, or clear it when unknown. Your receipt has not been submitted."; return
            }
            guard duplicateHistory.isEmpty || checkpoint.separateImportID != nil else {
                needsDuplicateDecision = true; errorMessage = "A matching receipt or same-date item list was imported before. Review it and explicitly choose a separate import, or discard this copy."; return
            }
            let reviewed = PantryReceiptReviewRules.reviewedItems(from: items)
            guard reviewed.count == items.count, !reviewed.isEmpty else {
                errorMessage = "Review or remove every invalid receipt row before adding to pantry. Nothing has been added."
                return
            }
            var submitted = checkpoint; submitted.isSubmitted = true
            submitted.rows = reviewed.map { original in
                var item = original; item.dateAdded = checkpoint.purchaseDate; item.quantityVerified = true
                var evidence = item.purchaseEvidence ?? PantryPurchaseEvidence(originalReceiptName: original.name,
                    receiptRowQuantity: original.quantity, receiptRowUnit: original.unit)
                if let store = checkpoint.storeName { evidence.storeName = store }
                if let currency = checkpoint.currency { evidence.currency = currency }
                evidence.printedLinePrice = evidence.reviewedPrice
                item.purchaseEvidence = evidence
                return PantryReceiptRow(item: item, status: .pending)
            }
            if checkpoint.usesWholeReceiptLedger == true {
                do {
                    guard reviewed.count <= 80 else { throw InventoryError.invalid }
                    let signature = try PantryReceiptIdentityRules.contentSignature(items: submitted.rows.map(\.item), purchaseDate: submitted.purchaseDate, purchaseDayKey: submitted.purchaseDay?.dayKey)
                    submitted.ledgerMutation = InventoryMutation(id: submitted.id, userID: userID,
                        title: "Receipt purchase · \(reviewed.count) reviewed items", reason: .purchase, before: [], after: submitted.rows.map(\.item),
                        uniqueSourceKey: PantryReceiptIdentityRules.sourceKey(digest: submitted.sourceDigest, signature: signature, separateImportID: submitted.separateImportID), now: submitted.purchaseDate)
                    try submitted.ledgerMutation?.validate()
                } catch { errorMessage = "One atomic receipt supports up to 80 valid reviewed stock rows. Your full draft is kept; review or reduce the rows before saving."; return }
            }
            guard persist(submitted) else { return }
        }
        isSaving = true
        defer { isSaving = false }
        if let mutation = checkpoint.ledgerMutation, checkpoint.usesWholeReceiptLedger == true {
            do {
                try await repository.applyInventoryMutation(userID: userID, mutation: mutation)
                guard canUseAccount else { throw InventoryError.accountChanged }
                var accepted = checkpoint
                for index in accepted.rows.indices { accepted.rows[index].status = .accepted; accepted.rows[index].error = nil }
                if persist(accepted) { needsDuplicateDecision = false }
            } catch {
                let code = (error as NSError).code
                needsDuplicateDecision = error as? InventoryError == .alreadyApplied || (error as NSError).domain == InventoryError.errorDomain && code == InventoryError.alreadyApplied.rawValue
                errorMessage = needsDuplicateDecision
                    ? "This receipt source is already recorded in your account. No additional stock was added. Check its status; a separate import requires an explicit new review."
                    : "This atomic receipt has not been acknowledged. Its exact reviewed rows are kept for retry. " + error.localizedDescription
            }
            return
        }
        // Every purchase row has a create-once receipt. Replaying a timeout cannot
        // overwrite stock that was explicitly edited after the original import.
        for index in checkpoint.rows.indices where checkpoint.rows[index].status != .accepted {
            guard canUseAccount else { errorMessage = "Sign back into the account that opened this receipt."; return }
            var pending = checkpoint; pending.rows[index].status = .pending; pending.rows[index].error = nil
            guard persist(pending) else { return }
            do {
                let item = checkpoint.rows[index].item
                if checkpoint.usesInventoryLedger == true {
                    let operation = InventoryMutation(id: item.id, userID: userID, title: "Receipt purchase · \(item.name)", reason: .purchase,
                        before: [], after: [item], uniqueSourceKey: "receipt-\(checkpoint.id.uuidString)-\(item.id.uuidString)", now: checkpoint.purchaseDate)
                    try await repository.applyInventoryMutation(userID: userID, mutation: operation)
                } else {
                    try await repository.createPantryReceiptItem(userID: userID, receiptID: checkpoint.id, item: item)
                }
                guard canUseAccount else { errorMessage = "Your receipt stays with its original account. Sign back in to finish."; return }
                var accepted = checkpoint; accepted.rows[index].status = .accepted
                guard persist(accepted) else { return }
            } catch {
                var failed = checkpoint; failed.rows[index].status = .failed
                failed.rows[index].error = "Not acknowledged. Retry keeps this row's original purchase ID."
                guard persist(failed) else { return }
            }
        }
        if !isComplete { errorMessage = "Some purchase rows need retry. Accepted rows will not be added again." }
    }

    public func checkStatus(using repository: NutritionRepositoryProtocol) async {
        guard !isSaving, canUseAccount, let userID, let mutation = checkpoint.ledgerMutation else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let status = try await repository.resolveInventoryMutation(userID: userID, mutation: mutation, cancelPending: false)
            guard canUseAccount else { throw InventoryError.accountChanged }
            if status == .accepted {
                var next = checkpoint
                for index in next.rows.indices { next.rows[index].status = .accepted; next.rows[index].error = nil }
                _ = persist(next)
            } else { errorMessage = status == .pending ? "No accepted receipt exists for this exact operation yet." : "This exact receipt operation was cancelled. Its reviewed rows are kept." }
        } catch { errorMessage = "Your exact receipt is kept. " + error.localizedDescription }
    }

    public func beginSeparateImport(using repository: NutritionRepositoryProtocol) async {
        guard !isSaving, canUseAccount, let userID, let mutation = checkpoint.ledgerMutation, !isComplete else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let status = try await repository.resolveInventoryMutation(userID: userID, mutation: mutation, cancelPending: true)
            guard canUseAccount else { throw InventoryError.accountChanged }
            guard status == .cancelled else {
                if status == .accepted {
                    var accepted = checkpoint
                    for index in accepted.rows.indices { accepted.rows[index].status = .accepted; accepted.rows[index].error = nil }
                    _ = persist(accepted)
                }
                errorMessage = status == .accepted ? "This operation was accepted. Finish this receipt; start any later purchase separately." : "The prior operation has not been fenced yet. Its review is kept."
                return
            }
            let rows = checkpoint.rows.map { row -> PantryReceiptRow in
                var item = row.item; item.id = UUID(); item.revisionID = nil
                return PantryReceiptRow(item: item, status: .ready)
            }
            var next = PantryReceiptCheckpoint(id: UUID(), purchaseDate: checkpoint.purchaseDate, rows: rows, isSubmitted: false)
            next.sourceDigest = checkpoint.sourceDigest; next.separateImportID = UUID()
            next.purchaseDay = checkpoint.purchaseDay
            next.storeName = checkpoint.storeName; next.currency = checkpoint.currency
            if persist(next) { needsDuplicateDecision = false; restoredReview = true }
        } catch { errorMessage = "The previous receipt remains frozen. A separate import could not be prepared. " + error.localizedDescription }
    }

    @discardableResult
    public func finish() -> Bool {
        guard isComplete, !isSaving, canUseAccount, let userID else { return false }
        do {
            let signature = try PantryReceiptIdentityRules.contentSignature(items: items, purchaseDate: checkpoint.purchaseDate, purchaseDayKey: checkpoint.purchaseDay?.dayKey)
            let existingRecords: [PantryReceiptHistoryRecord]?
            do { existingRecords = try store.load([PantryReceiptHistoryRecord].self, userID: userID, scope: historyScope)?.value ?? [] } catch {
                historyAvailable = false; existingRecords = nil // Account ledger/source locks remain authoritative; keep unreadable advisory file intact.
            }
            if var records = existingRecords, !records.contains(where: { $0.id == checkpoint.id }) {
                records.append(PantryReceiptHistoryRecord(id: checkpoint.id, sourceDigest: checkpoint.sourceDigest,
                    contentSignature: signature, purchaseDate: checkpoint.purchaseDate, items: items,
                    separateImportID: checkpoint.separateImportID, recordedAt: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 * 1_000).rounded() / 1_000),
                    purchaseDayKey: checkpoint.purchaseDay?.dayKey))
                records = Array(records.suffix(200))
                try store.save(records, userID: userID, scope: historyScope); history = records
            }
            guard let expectedFingerprint,
                  try store.removeIfUnchanged(PantryReceiptCheckpoint.self, userID: userID, scope: scope, fingerprint: expectedFingerprint) else { throw InventoryError.changed }
            return true
        } catch {
            errorMessage = "The purchases are accepted. Try Done again to clear this receipt."
            return false
        }
    }

    @discardableResult
    public func discard() -> Bool {
        guard !isSubmitted, !isSaving, canUseAccount, let userID else { return false }
        do {
            if let expectedFingerprint {
                guard try store.removeIfUnchanged(PantryReceiptCheckpoint.self, userID: userID, scope: scope, fingerprint: expectedFingerprint) else { throw InventoryError.changed }
            }
            return true
        } catch {
            errorMessage = "Could not discard this receipt. It is still kept on this device."; return false
        }
    }

    private var canUseAccount: Bool { !unreadable && userID != nil && DIContainer.shared.authService.currentUserID == userID }
    private func persist(_ next: PantryReceiptCheckpoint) -> Bool {
        guard canUseAccount, let userID else { return false }
        do {
            let previous = try store.load(PantryReceiptCheckpoint.self, userID: userID, scope: scope)?.value
            guard try previous.map(PlanFingerprint.make) == expectedFingerprint else { throw InventoryError.changed }
            try store.save(next, userID: userID, scope: scope); checkpoint = next
            expectedFingerprint = try PlanFingerprint.make(next); errorMessage = nil; return true
        } catch {
            errorMessage = "Could not keep this receipt on the device. Keep it open and retry."; return false
        }
    }
}
