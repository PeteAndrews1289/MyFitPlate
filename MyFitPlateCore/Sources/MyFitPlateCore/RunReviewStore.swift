import Foundation

public struct RunReviewAnnotation: Codable, Equatable {
    public let receiptID: String
    public let changedAt: Date
    public let reason: String
    public let originalDistanceMeters: Double
    public let originalMovingSeconds: Double
    public var note: String?
    public var originalPauseTimeline: RunPauseTimeline?
}

/// Reversible MyFitPlate corrections are overlays. Original local/Health evidence,
/// step receipts, route files and program completion are never rewritten here.
public final class RunReviewStore {
    public enum Mutation: Codable, Equatable {
        case correctManual(distanceMeters: Double, movingSeconds: Double, reason: String)
        case annotate(note: String)
        case correctPauses(timeline: RunPauseTimeline, reason: String)
        case excludeImportPermanently
        case hide
        case restoreOriginal
    }
    public struct Review: Codable, Equatable {
        public let operationID: String
        public let userID: String
        public let identity: String
        public let original: Run
        public let expectedReceiptID: String?
        public let mutation: Mutation
        public let diaryCorrection: RunDiaryCorrectionLink?
        public func withDiaryCorrection(_ link: RunDiaryCorrectionLink) -> Review {
            Review(operationID: operationID, userID: userID, identity: identity, original: original,
                   expectedReceiptID: expectedReceiptID, mutation: mutation, diaryCorrection: link)
        }
    }
    public struct Receipt: Codable, Equatable, Identifiable {
        public var id: String { review.operationID }
        public let review: Review
        public let acceptedAt: Date
    }
    private struct Snapshot: Codable {
        var receipts: [Receipt] = []
        var latestByIdentity: [String: String] = [:]
    }

    private static let lock = NSRecursiveLock()
    private let drafts: EditorDraftStore
    private let scope = "run.review-overlays.v1"
    public init(drafts: EditorDraftStore = EditorDraftStore()) { self.drafts = drafts }

    public static func canCorrectManual(_ run: Run) -> Bool {
        run.source == .recorded && run.isIndoor && run.pauseTimeline == nil
            && run.workoutResult == nil && !run.hasRoute && (run.routeSegmentStarts?.isEmpty ?? true)
    }

    public static func identity(_ run: Run) -> String {
        run.source == .recorded ? "recording:\(run.recordingID ?? run.id)" : "health:\(run.id)"
    }

    public func review(run: Run, mutation: Mutation, userID: String, operationID: String = UUID().uuidString) throws -> Review {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let snapshot = try load(userID: userID)
        let identity = Self.identity(run)
        if let pending = try drafts.load(RunDiaryCorrectionOperation.self, userID: userID,
            scope: RunDiaryCorrectionCoordinator.scope(identity))?.value,
           !snapshot.receipts.contains(where: { $0.id == pending.review.operationID }) {
            throw failure("A linked diary correction is pending for this run. Retry that exact review first.")
        }
        let latest = latestReceipt(identity: identity, snapshot: snapshot)
        guard latest?.review.mutation != .excludeImportPermanently else { throw failure("This imported run was permanently removed from MyFitPlate history. Its source record remains in Apple Health.") }
        let original = latest?.review.original ?? run
        guard original.reviewAnnotation == nil,
              run.reviewAnnotation == nil || run.reviewAnnotation?.receiptID == latest?.id else { throw failure("This run review changed. Reopen the current receipt.") }
        try validate(mutation, original: original)
        return Review(operationID: operationID, userID: userID, identity: identity, original: original,
            expectedReceiptID: latest?.id, mutation: mutation, diaryCorrection: nil)
    }

    @discardableResult
    public func commit(_ review: Review, currentUserID: String, diaryAccepted: Bool = false, now: Date = Date()) throws -> Receipt {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard review.userID == currentUserID, !currentUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !review.operationID.isEmpty, now.timeIntervalSinceReferenceDate.isFinite else { throw failure("Your account changed. Reopen this review in the correct account.") }
        var snapshot = try load(userID: review.userID)
        if let accepted = snapshot.receipts.first(where: { $0.id == review.operationID }) {
            guard accepted.review == review else { throw failure("This review identity is already used by a different change.") }
            return accepted
        }
        if let pending = try drafts.load(RunDiaryCorrectionOperation.self, userID: review.userID,
            scope: RunDiaryCorrectionCoordinator.scope(review.identity))?.value,
           pending.review != review, !snapshot.receipts.contains(where: { $0.id == pending.review.operationID }) {
            throw failure("A linked diary correction is pending. Finish that exact review before changing this run.")
        }
        guard latestReceipt(identity: review.identity, snapshot: snapshot)?.review.mutation != .excludeImportPermanently else { throw failure("This imported run was permanently removed from MyFitPlate history.") }
        guard snapshot.latestByIdentity[review.identity] == review.expectedReceiptID,
              Self.identity(review.original) == review.identity, review.original.reviewAnnotation == nil else {
            throw failure("This run changed after review. Your original record is kept; review the latest version.")
        }
        try validate(review.mutation, original: review.original)
        let correctionNeedsDiary: Bool
        switch review.mutation {
        case .correctManual, .correctPauses: correctionNeedsDiary = true
        case .restoreOriginal: correctionNeedsDiary = snapshot.receipts.contains { $0.review.identity == review.identity && $0.review.diaryCorrection != nil }
        case .hide, .annotate, .excludeImportPermanently: correctionNeedsDiary = false
        }
        guard !correctionNeedsDiary || (review.diaryCorrection != nil && diaryAccepted),
              review.diaryCorrection == nil || diaryAccepted else {
            throw failure("The linked diary correction is unresolved. This run change has not been accepted.")
        }
        let receipt = Receipt(review: review, acceptedAt: now)
        snapshot.receipts.append(receipt)
        snapshot.latestByIdentity[review.identity] = receipt.id
        try drafts.save(snapshot, userID: review.userID, scope: scope, now: now)
        NotificationCenter.default.post(name: .runLibrariesChanged, object: review.userID)
        return receipt
    }

    public func acceptedReceipt(operationID: String, userID: String) throws -> Receipt? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try load(userID: userID).receipts.first { $0.id == operationID }
    }

    public func undoReview(_ receipt: Receipt, currentUserID: String) throws -> Review {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard receipt.review.mutation != .excludeImportPermanently else { throw failure("Permanent removal cannot be undone. Its source record remains in Apple Health.") }
        guard receipt.review.userID == currentUserID else { throw failure("Your account changed. Reopen this receipt.") }
        let snapshot = try load(userID: currentUserID)
        guard snapshot.latestByIdentity[receipt.review.identity] == receipt.id,
              snapshot.receipts.contains(receipt) else { throw failure("A newer review exists. Undo cannot replace it.") }
        let previous = receipt.review.expectedReceiptID.flatMap { id in snapshot.receipts.first { $0.id == id } }
        return Review(operationID: "undo.\(receipt.id)", userID: currentUserID, identity: receipt.review.identity,
            original: receipt.review.original, expectedReceiptID: receipt.id, mutation: previous?.review.mutation ?? .restoreOriginal,
            diaryCorrection: nil)
    }

    /// Visibility-only undo is synchronous; linked totals must use the coordinator.
    @discardableResult
    public func undo(_ receipt: Receipt, currentUserID: String) throws -> Receipt {
        if let accepted = try acceptedReceipt(operationID: "undo.\(receipt.id)", userID: currentUserID) { return accepted }
        return try commit(undoReview(receipt, currentUserID: currentUserID), currentUserID: currentUserID)
    }

    public func projecting(_ runs: [Run], userID: String, includeHidden: Bool = false) throws -> [Run] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let snapshot = try load(userID: userID)
        return runs.compactMap { run in
            guard let receipt = latestReceipt(identity: Self.identity(run), snapshot: snapshot) else { return run }
            switch receipt.review.mutation {
            case .excludeImportPermanently: return nil
            case .hide: return includeHidden ? originalAlias(receipt.review.original, current: run) : nil
            case .restoreOriginal:
                return run.reviewAnnotation == nil ? run : originalAlias(receipt.review.original, current: run)
            case .annotate(let note):
                var projected = originalAlias(receipt.review.original, current: run)
                projected.reviewAnnotation = RunReviewAnnotation(receiptID: receipt.id, changedAt: receipt.acceptedAt,
                    reason: "Personal note", originalDistanceMeters: projected.distanceMeters,
                    originalMovingSeconds: projected.movingSeconds, note: note)
                return projected
            case .correctPauses(let timeline, let reason):
                guard let correction = RunPauseCorrectionRules.review(original: receipt.review.original, timeline: timeline) else { return run }
                var projected = originalAlias(receipt.review.original, current: run)
                projected.movingSeconds = correction.activeSeconds
                projected.pauseTimeline = timeline
                // Measured split/interval receipts remain original evidence. Their clocks
                // must not be presented as recalculated from a manually edited timeline.
                projected.reviewAnnotation = RunReviewAnnotation(receiptID: receipt.id, changedAt: receipt.acceptedAt,
                    reason: reason, originalDistanceMeters: receipt.review.original.distanceMeters,
                    originalMovingSeconds: receipt.review.original.movingSeconds,
                    originalPauseTimeline: receipt.review.original.pauseTimeline)
                return projected
            case .correctManual(let distance, let seconds, let reason):
                var projected = originalAlias(receipt.review.original, current: run)
                projected.distanceMeters = distance
                projected.movingSeconds = seconds
                projected.endDate = projected.startDate.addingTimeInterval(seconds)
                // These remain manual estimates; preserve original unit boundaries.
                let metric = receipt.review.original.splits.first.map { abs($0.distanceMeters - 1000) < 1 } ?? true
                projected.splits = ManualRunEntryRules.splits(distanceMeters: distance, movingSeconds: seconds, metric: metric)
                projected.activeCalories = receipt.review.diaryCorrection?.after.caloriesBurned
                projected.reviewAnnotation = RunReviewAnnotation(receiptID: receipt.id, changedAt: receipt.acceptedAt,
                    reason: reason, originalDistanceMeters: receipt.review.original.distanceMeters,
                    originalMovingSeconds: receipt.review.original.movingSeconds)
                return projected
            }
        }
    }

    public func originalEvidence(for run: Run, userID: String) throws -> Run {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let snapshot = try load(userID: userID)
        guard let receipt = latestReceipt(identity: Self.identity(run), snapshot: snapshot) else { return run }
        return originalAlias(receipt.review.original, current: run)
    }

    public func latestReceipts(userID: String) throws -> [Receipt] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let snapshot = try load(userID: userID)
        return snapshot.latestByIdentity.values.compactMap { id in snapshot.receipts.first { $0.id == id } }
            .sorted { $0.acceptedAt > $1.acceptedAt }
    }

    public func cloudSnapshot(userID: String) throws -> [String: Data] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let value = try load(userID: userID)
        var records: [String: Data] = [:]
        for receipt in value.receipts { records["receipt/" + receipt.id] = try RunCloudCodec.encode(receipt) }
        for (identity, head) in value.latestByIdentity { records["head/" + identity] = try RunCloudCodec.encode(head) }
        return records
    }
    @MainActor public func applyCloudSnapshot(_ values: [String: Data], expectedFingerprint: String, userID: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard DIContainer.shared.authService.currentUserID == userID else { throw RunCloudError.accountChanged }
        let old = try cloudSnapshot(userID: userID)
        guard try PlanFingerprint.make(old) == expectedFingerprint else { throw RunCloudError.changed }
        try RunCloudCodec.preserveImmutable(old: old, new: values)
        if old == values { return }
        let previous = try load(userID: userID)
        var receipts: [String: Receipt] = [:], heads: [String: String] = [:]
        for (key, data) in values {
            if key.hasPrefix("receipt/") {
                let receipt = try RunCloudCodec.decode(Receipt.self, data)
                guard !receipt.id.isEmpty, key == "receipt/" + receipt.id, receipt.review.userID == userID,
                      Self.identity(receipt.review.original) == receipt.review.identity,
                      receipt.review.original.reviewAnnotation == nil,
                      receipt.acceptedAt.timeIntervalSinceReferenceDate.isFinite else { throw RunCloudError.invalid }
                try validate(receipt.review.mutation, original: receipt.review.original)
                try validateCloudLink(receipt.review, userID: userID)
                receipts[receipt.id] = receipt
            } else if key.hasPrefix("head/") {
                heads[String(key.dropFirst(5))] = try RunCloudCodec.decode(String.self, data)
            } else { throw RunCloudError.invalid }
        }
        var next = Snapshot()
        for (identity, head) in heads.sorted(by: { $0.key < $1.key }) {
            var chain: [Receipt] = [], cursor: String? = head, seen = Set<String>()
            while let id = cursor {
                guard seen.insert(id).inserted, let receipt = receipts[id], receipt.review.identity == identity else { throw RunCloudError.invalid }
                chain.append(receipt); cursor = receipt.review.expectedReceiptID
            }
            chain.reverse()
            guard chain.allSatisfy({ $0.review.original == chain.first?.review.original }),
                  previous.receipts.filter({ $0.review.identity == identity }).allSatisfy({ chain.contains($0) }) else { throw RunCloudError.protectedEvidence }
            for (offset, receipt) in chain.enumerated() {
                if let link = receipt.review.diaryCorrection, let priorID = link.ownedPriorReceiptID {
                    guard let prior = chain.prefix(offset).first(where: { $0.id == priorID }),
                          let owned = prior.review.diaryCorrection,
                          owned.healthID == link.healthID, owned.day == link.day,
                          ActivityEditPrecondition.sameSnapshot(owned.after, link.before) else { throw RunCloudError.invalid }
                }
            }
            if let pending = try drafts.load(RunDiaryCorrectionOperation.self, userID: userID,
                scope: RunDiaryCorrectionCoordinator.scope(identity))?.value,
               !chain.contains(where: { $0.id == pending.review.operationID }), previous.latestByIdentity[identity] != head {
                throw RunCloudError.protectedEvidence
            }
            // Permanent exclusions cannot be followed by a restore from another device.
            if let index = chain.firstIndex(where: { $0.review.mutation == .excludeImportPermanently }), index != chain.count - 1 {
                throw RunCloudError.protectedEvidence
            }
            next.receipts += chain; next.latestByIdentity[identity] = head
        }
        guard previous.receipts.allSatisfy({ next.receipts.contains($0) }) else { throw RunCloudError.protectedEvidence }
        // Unselected branches remain in the immutable cloud checkpoint, not the
        // active local overlay chain. They must not cause an unchanged projection
        // to publish another save notification and schedule endless sync retries.
        let previousReceipts = Dictionary(uniqueKeysWithValues: previous.receipts.map { ($0.id, $0) })
        let nextReceipts = Dictionary(uniqueKeysWithValues: next.receipts.map { ($0.id, $0) })
        guard next.latestByIdentity != previous.latestByIdentity || nextReceipts != previousReceipts else { return }
        // Linked diary receipts are never replayed here.
        try drafts.save(next, userID: userID, scope: scope)
        NotificationCenter.default.post(name: .runLibrariesChanged, object: userID)
    }

    private func validateCloudLink(_ review: Review, userID: String) throws {
        let correctsTotals: Bool
        switch review.mutation {
        case .correctManual, .correctPauses: correctsTotals = true
        default: correctsTotals = false
        }
        guard let link = review.diaryCorrection else {
            if correctsTotals { throw RunCloudError.invalid }
            return
        }
        guard UUID(uuidString: link.healthID) != nil, link.day.isOwned(by: userID),
              link.day.originalDate.timeIntervalSinceReferenceDate.isFinite,
              TimeZone(identifier: link.day.timeZoneIdentifier) != nil,
              DiaryDayContext(userID: userID, date: link.day.originalDate, timeZone: link.day.timeZone, dayKey: link.day.dayKey) == link.day,
              link.before.id == link.healthID, link.after.id == link.healthID,
              link.before.source == "HealthKit", link.after.source == "HealthKit",
              link.before.date.timeIntervalSinceReferenceDate.isFinite, link.before.date == link.after.date,
              link.before.workoutID == link.after.workoutID, link.before.sessionID == link.after.sessionID,
              link.estimateWeightLbs.isFinite, link.estimateWeightLbs > 0,
              link.before.caloriesBurned.isFinite, link.before.caloriesBurned >= 0,
              link.after.caloriesBurned.isFinite, link.after.caloriesBurned >= 0,
              link.before.durationMinutes.map({ $0 >= 0 }) ?? true,
              link.after.durationMinutes.map({ $0 >= 0 }) ?? true,
              link.ownedPriorReceiptID.map({ !$0.isEmpty }) ?? true else { throw RunCloudError.invalid }
        if correctsTotals {
            guard link.after.hasLocalHealthKitEdits == true else { throw RunCloudError.invalid }
            let seconds: Double
            switch review.mutation {
            case .correctManual(_, let moving, _): seconds = moving
            case .correctPauses(let timeline, _):
                guard let correction = RunPauseCorrectionRules.review(original: review.original, timeline: timeline) else { throw RunCloudError.invalid }
                seconds = correction.activeSeconds
            default: throw RunCloudError.invalid
            }
            guard seconds <= Double(Int.max), link.after.durationMinutes == max(1, Int(seconds / 60)) else { throw RunCloudError.invalid }
        }
    }

    private func originalAlias(_ original: Run, current: Run) -> Run {
        var copy = original.reidentified(as: current.id)
        copy.shoeID = current.shoeID
        return copy
    }

    private func validate(_ mutation: Mutation, original: Run) throws {
        guard RunFallbackStore.isValid(original) else { throw failure("The original run cannot be safely reviewed.") }
        if mutation == .excludeImportPermanently, original.source == .recorded { throw failure("Only imported runs can be permanently excluded here. Recorded runs retain their save and Health recovery evidence.") }
        if case .annotate(let note) = mutation {
            guard original.source != .recorded, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.count <= 1000 else {
                throw failure("Add a note of up to 1,000 characters. The imported workout stays unchanged.")
            }
        }
        if case .correctPauses(let timeline, let reason) = mutation {
            guard RunPauseCorrectionRules.review(original: original, timeline: timeline) != nil,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 500 else {
                throw failure("Review valid pause times and a short reason. Recovery gaps and original sensor evidence are preserved.")
            }
        }
        if case .correctManual(let distance, let seconds, let reason) = mutation {
            guard Self.canCorrectManual(original),
                  ManualRunEntryRules.buildIndoorRun(startDate: original.startDate, distanceMeters: distance,
                    movingSeconds: seconds, metric: true, confirmShortRecording: true) != nil,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 500 else {
                throw failure("Enter valid treadmill distance and active time, plus a short reason. Measured runs keep their original sensor evidence.")
            }
        }
    }

    private func load(userID: String) throws -> Snapshot {
        let snapshot = try drafts.load(Snapshot.self, userID: userID, scope: scope)?.value ?? Snapshot()
        guard Set(snapshot.receipts.map(\.id)).count == snapshot.receipts.count,
              snapshot.receipts.allSatisfy({ $0.review.userID == userID && Self.identity($0.review.original) == $0.review.identity }),
              snapshot.latestByIdentity.allSatisfy({ identity, id in
                  snapshot.receipts.contains { $0.id == id && $0.review.identity == identity }
              }) else { throw CocoaError(.coderReadCorrupt) }
        var previousByIdentity: [String: String] = [:]
        var originals: [String: Run] = [:]
        var excludedIdentities = Set<String>()
        for receipt in snapshot.receipts {
            guard !excludedIdentities.contains(receipt.review.identity),
                  receipt.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
                  receipt.review.original.reviewAnnotation == nil,
                  receipt.review.expectedReceiptID == previousByIdentity[receipt.review.identity],
                  originals[receipt.review.identity].map({ $0 == receipt.review.original }) ?? true else { throw CocoaError(.coderReadCorrupt) }
            try validate(receipt.review.mutation, original: receipt.review.original)
            originals[receipt.review.identity] = receipt.review.original
            previousByIdentity[receipt.review.identity] = receipt.id
            if receipt.review.mutation == .excludeImportPermanently { excludedIdentities.insert(receipt.review.identity) }
        }
        guard previousByIdentity == snapshot.latestByIdentity else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }

    private func latestReceipt(identity: String, snapshot: Snapshot) -> Receipt? {
        guard let id = snapshot.latestByIdentity[identity] else { return nil }
        return snapshot.receipts.first { $0.id == id }
    }

    private func failure(_ text: String) -> NSError { NSError(domain: "RunReview", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
