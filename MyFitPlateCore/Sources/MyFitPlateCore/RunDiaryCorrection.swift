import Foundation

public struct RunDiaryCorrectionLink: Codable, Equatable {
    public let healthID: String
    public let day: DiaryDayContext
    public let before: LoggedExercise
    public let after: LoggedExercise
    public let estimateWeightLbs: Double
    public let ownedPriorReceiptID: String?
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.healthID == rhs.healthID && lhs.day == rhs.day && lhs.estimateWeightLbs == rhs.estimateWeightLbs
            && lhs.ownedPriorReceiptID == rhs.ownedPriorReceiptID
            && ActivityEditPrecondition.sameSnapshot(lhs.before, rhs.before)
            && ActivityEditPrecondition.sameSnapshot(lhs.after, rhs.after)
    }
}

public struct RunDiaryCorrectionOperation: Codable, Equatable {
    public enum Phase: String, Codable { case prepared, diaryAccepted }
    public let review: RunReviewStore.Review
    public var phase: Phase
}

/// Two resources cannot share one local/remote transaction. Keep the exact proposal
/// durable, accept its diary CAS first, then accept the local overlay. Any partial
/// success stays explicitly pending and retries the same operation and identities.
@MainActor
public final class RunDiaryCorrectionCoordinator {
    private let service: DailyLogService
    private let store: RunReviewStore
    private let drafts: EditorDraftStore
    private let jobs: RunHealthExportJobStore
    public init(service: DailyLogService, drafts: EditorDraftStore = EditorDraftStore(), jobs: RunHealthExportJobStore = RunHealthExportJobStore()) {
        self.service = service; self.drafts = drafts; self.jobs = jobs
        store = RunReviewStore(drafts: drafts)
    }

    public func pending(run: Run, userID: String) throws -> RunDiaryCorrectionOperation? {
        guard let saved = try drafts.load(RunDiaryCorrectionOperation.self, userID: userID, scope: Self.scope(RunReviewStore.identity(run)))?.value else { return nil }
        if try store.acceptedReceipt(operationID: saved.review.operationID, userID: userID) != nil { return nil }
        return saved
    }

    public func prepare(run: Run, distanceMeters: Double, movingSeconds: Double, reason: String,
                        userID: String, operationID: String) async throws -> RunReviewStore.Review {
        try await prepare(run: run, mutation: .correctManual(distanceMeters: distanceMeters, movingSeconds: movingSeconds, reason: reason),
            distanceMeters: distanceMeters, movingSeconds: movingSeconds, userID: userID, operationID: operationID)
    }

    public func preparePauses(run: Run, timeline: RunPauseTimeline, reason: String,
                              userID: String, operationID: String) async throws -> RunReviewStore.Review {
        let original = try store.originalEvidence(for: run, userID: userID)
        guard let correction = RunPauseCorrectionRules.review(original: original, timeline: timeline) else {
            throw failure("The pause correction is invalid. Your original recording is unchanged.")
        }
        return try await prepare(run: run, mutation: .correctPauses(timeline: timeline, reason: reason),
            distanceMeters: original.distanceMeters, movingSeconds: correction.activeSeconds, userID: userID, operationID: operationID)
    }

    private func prepare(run: Run, mutation: RunReviewStore.Mutation, distanceMeters: Double, movingSeconds: Double,
                         userID: String, operationID: String) async throws -> RunReviewStore.Review {
        try account(userID)
        if try pending(run: run, userID: userID) != nil { throw failure("A linked correction is already pending. Retry that exact review before starting another.") }
        let review = try store.review(run: run, mutation: mutation,
            userID: userID, operationID: operationID)
        guard let job = try jobs.load(recordingID: run.recordingID ?? run.id, userID: userID),
              let healthID = job.healthID, UUID(uuidString: healthID) != nil,
              job.run.recordingID == run.recordingID, job.weightLbs.isFinite, job.weightLbs > 0,
              let day = DiaryDayContext(userID: userID, date: job.run.startDate) else {
            throw failure("The exact Health and diary link or original estimate weight is unavailable. This correction is not applied. Confirm Health sync and the activity's diary copy first.")
        }
        let log = try await read(userID: userID, day: day)
        try account(userID)
        let matches = (log.exercises ?? []).filter { $0.id == healthID && $0.source == "HealthKit" }
        guard matches.count == 1, let expected = matches.first else {
            throw failure("The linked diary activity is missing or ambiguous. This correction is not applied; refresh that day's Health activities first.")
        }
        let latest = try store.latestReceipts(userID: userID).first { $0.review.identity == review.identity }
        let owned = latest?.review.diaryCorrection.map { ActivityEditPrecondition.sameSnapshot($0.after, expected) } == true ? latest?.id : nil
        guard expected.hasLocalHealthKitEdits != true || owned != nil else {
            throw failure("This activity already has an independent diary correction. It is preserved; review it in the diary before changing run totals.")
        }
        var updated = expected
        updated.durationMinutes = max(1, Int(movingSeconds / 60))
        updated.caloriesBurned = RunEnergy.estimateKcal(distanceMeters: distanceMeters, weightLbs: job.weightLbs)
        updated.hasLocalHealthKitEdits = true
        let link = RunDiaryCorrectionLink(healthID: healthID, day: day, before: expected, after: updated,
            estimateWeightLbs: job.weightLbs, ownedPriorReceiptID: owned)
        return review.withDiaryCorrection(link)
    }

    @discardableResult
    public func commit(_ review: RunReviewStore.Review) async throws -> RunReviewStore.Receipt {
        try account(review.userID)
        if let accepted = try store.acceptedReceipt(operationID: review.operationID, userID: review.userID) {
            guard accepted.review == review else { throw failure("This operation belongs to a different reviewed change.") }
            return accepted
        }
        guard let link = review.diaryCorrection else {
            return try store.commit(review, currentUserID: review.userID)
        }
        try validate(link, review: review)
        let scope = Self.scope(review.identity)
        var operation: RunDiaryCorrectionOperation
        if let saved = try drafts.load(RunDiaryCorrectionOperation.self, userID: review.userID, scope: scope)?.value {
            if saved.review == review { operation = saved } else if try store.acceptedReceipt(operationID: saved.review.operationID, userID: review.userID) != nil {
                operation = RunDiaryCorrectionOperation(review: review, phase: .prepared)
                try drafts.save(operation, userID: review.userID, scope: scope)
            } else { throw failure("Another exact correction is pending for this run. Finish that review first.") }
        } else {
            operation = RunDiaryCorrectionOperation(review: review, phase: .prepared)
            try drafts.save(operation, userID: review.userID, scope: scope)
        }
        // Even an earlier diaryAccepted phase verifies the desired canonical copy;
        // it cannot overwrite a later independent diary edit on retry.
        let result = await service.reconcileRunActivity(for: review.userID, day: link.day,
            operationID: "run-review.\(review.operationID)", expected: link.before, updated: link.after,
            allowsOwnedOverride: link.ownedPriorReceiptID != nil)
        try account(review.userID)
        guard result == .updated || result == .alreadyCurrent else {
            throw failure("The linked diary correction has not been confirmed (\(result.rawValue)). Your original run remains displayed and this exact review is kept for retry.")
        }
        operation.phase = .diaryAccepted
        try drafts.save(operation, userID: review.userID, scope: scope)
        let receipt: RunReviewStore.Receipt
        do { receipt = try store.commit(review, currentUserID: review.userID, diaryAccepted: true) } catch {
            throw failure("The diary correction is confirmed, but its run receipt is still pending. Retry this exact review; no new Health workout will be written.")
        }
        _ = try? drafts.removeIfUnchanged(RunDiaryCorrectionOperation.self, userID: review.userID, scope: scope,
                                         fingerprint: PlanFingerprint.make(operation))
        return receipt
    }

    @discardableResult
    public func undo(_ receipt: RunReviewStore.Receipt, userID: String) async throws -> RunReviewStore.Receipt {
        try account(userID)
        if let existing = try store.acceptedReceipt(operationID: "undo.\(receipt.id)", userID: userID) { return existing }
        var review = try store.undoReview(receipt, currentUserID: userID)
        let previous = try receipt.review.expectedReceiptID.flatMap { try store.acceptedReceipt(operationID: $0, userID: userID) }
        if let link = receipt.review.diaryCorrection {
            let desired = previous?.review.diaryCorrection?.after ?? link.before
            review = review.withDiaryCorrection(RunDiaryCorrectionLink(healthID: link.healthID, day: link.day,
                before: link.after, after: desired, estimateWeightLbs: link.estimateWeightLbs, ownedPriorReceiptID: receipt.id))
        } else if let link = previous?.review.diaryCorrection {
            // Undoing a visibility-only hide restores the accepted correction only
            // if its diary copy still agrees; no stale totals overwrite an override.
            review = review.withDiaryCorrection(RunDiaryCorrectionLink(healthID: link.healthID, day: link.day,
                before: link.after, after: link.after, estimateWeightLbs: link.estimateWeightLbs, ownedPriorReceiptID: previous?.id))
        }
        return try await commit(review)
    }

    private func validate(_ link: RunDiaryCorrectionLink, review: RunReviewStore.Review) throws {
        guard link.day.isOwned(by: review.userID), link.healthID == link.before.id, link.healthID == link.after.id,
              link.before.source == "HealthKit", link.after.source == "HealthKit", link.before.date == link.after.date,
              link.estimateWeightLbs.isFinite, link.estimateWeightLbs > 0 else { throw failure("The exact diary link is invalid; original records stay unchanged.") }
        if let priorID = link.ownedPriorReceiptID {
            guard let prior = try store.acceptedReceipt(operationID: priorID, userID: review.userID),
                  prior.review.identity == review.identity, let owned = prior.review.diaryCorrection,
                  ActivityEditPrecondition.sameSnapshot(owned.after, link.before) else {
                throw failure("An existing diary override is not owned by this correction. It is preserved.")
            }
        }
    }

    private func read(userID: String, day: DiaryDayContext) async throws -> DailyLog {
        try await withCheckedThrowingContinuation { continuation in
            service.fetchLogInternal(for: userID, day: day) { continuation.resume(with: $0) }
        }
    }
    private func account(_ userID: String) throws {
        guard DIContainer.shared.authService.currentUserID == userID, service.isActiveAccount(userID) else { throw failure("Your account changed. Reopen the correct run account.") }
    }
    public nonisolated static func scope(_ identity: String) -> String { "run.diary-correction.\(identity)" }
    private func failure(_ text: String) -> NSError { NSError(domain: "RunDiaryCorrection", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
