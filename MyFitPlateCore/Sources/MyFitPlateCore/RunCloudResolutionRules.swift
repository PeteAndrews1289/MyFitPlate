import Foundation

/// A merge must be acceptable to every reviewed branch, not merely the device
/// choosing it. Otherwise one device can erase the conflict while stranding the
/// other device's immutable completion or correction evidence.
public enum RunCloudResolutionRules {
    public static func validate(scope: RunCloudScope, conflict: RunCloudConflict, chosen: RunCloudRevision,
                                knownRevisions: [String: RunCloudRevision]) throws {
        guard conflict.versions.contains(chosen), conflict.versions.allSatisfy({
            $0.scope == scope && $0.key == conflict.key && $0.ownerID == chosen.ownerID
        }) else { throw RunCloudError.invalid }
        if conflict.key.hasPrefix("receipt/") || conflict.key.hasPrefix("revision/") || conflict.key.hasPrefix("abandoned/") {
            guard chosen.payload != nil, conflict.versions.allSatisfy({ $0.payload == chosen.payload }) else { throw RunCloudError.protectedEvidence }
            return
        }
        switch scope {
        case .workouts: return // Templates have no accepted session outcomes.
        case .blocks:
            guard conflict.key.hasPrefix("block/") else { return }
            try validateBlock(conflict, chosen: chosen, known: knownRevisions)
        case .reviews:
            guard conflict.key.hasPrefix("head/") else { return }
            try validateReview(conflict, chosen: chosen, known: knownRevisions)
        }
    }

    private static func validateBlock(_ conflict: RunCloudConflict, chosen: RunCloudRevision,
                                      known: [String: RunCloudRevision]) throws {
        guard let payload = chosen.payload else { throw RunCloudError.protectedEvidence }
        let candidate = try RunCloudCodec.decode(RunTrainingBlock.self, payload)
        guard conflict.key == "block/" + candidate.id,
              Set(candidate.slots.map(\.id)).count == candidate.slots.count else { throw RunCloudError.invalid }
        let abandoned = try known.values.filter {
            $0.ownerID == chosen.ownerID && $0.scope == .blocks && $0.key.hasPrefix("abandoned/")
        }.map { revision -> RunBlockOutcome in
            guard let data = revision.payload else { throw RunCloudError.invalid }
            let receipt = try RunCloudCodec.decode(RunBlockOutcome.self, data)
            guard receipt.state == .abandoned, revision.key == "abandoned/" + (try PlanFingerprint.make(receipt)) else { throw RunCloudError.invalid }
            return receipt
        }
        for branch in conflict.versions {
            guard let payload = branch.payload else { continue }
            let previous = try RunCloudCodec.decode(RunTrainingBlock.self, payload)
            guard previous.id == candidate.id else { throw RunCloudError.invalid }
            for slot in previous.slots where slot.outcome != nil {
                guard let original = slot.outcome, let updated = candidate.slots.first(where: { $0.id == slot.id }) else { throw RunCloudError.protectedEvidence }
                var unchangedPrescription = updated; unchangedPrescription.outcome = original
                guard unchangedPrescription == slot else { throw RunCloudError.protectedEvidence }
                if updated.outcome == original { continue }
                if original.state == .started, let completion = updated.outcome,
                   completion.state == .recorded, original.recordingID != nil,
                   completion.recordingID == original.recordingID, completion.prescription == original.prescription {
                    guard completion.runID?.isEmpty == false, let startedAt = completion.actualStart,
                          startedAt.timeIntervalSinceReferenceDate.isFinite,
                          completion.acceptedAt.timeIntervalSinceReferenceDate.isFinite, completion.acceptedAt >= startedAt,
                          completion.movingSeconds.map({ $0.isFinite && $0 >= 0 }) == true,
                          completion.distanceMeters.map({ $0.isFinite && $0 >= 0 }) == true else { throw RunCloudError.invalid }
                    continue
                }
                if updated.outcome == nil, original.state == .started,
                   abandoned.contains(where: { matchesAbandonment($0, started: original) }) { continue }
                throw RunCloudError.protectedEvidence
            }
        }
    }

    public static func matchesAbandonment(_ receipt: RunBlockOutcome, started: RunBlockOutcome) -> Bool {
        started.state == .started && receipt.state == .abandoned
            && started.recordingID?.isEmpty == false && started.prescription != nil
            && receipt.recordingID == started.recordingID && receipt.prescription == started.prescription
            && receipt.acceptedAt.timeIntervalSinceReferenceDate.isFinite && receipt.acceptedAt >= started.acceptedAt
            && receipt.runID == nil && receipt.actualStart == nil && receipt.movingSeconds == nil && receipt.distanceMeters == nil
    }

    private static func validateReview(_ conflict: RunCloudConflict, chosen: RunCloudRevision,
                                       known: [String: RunCloudRevision]) throws {
        guard let selected = chosen.payload else { throw RunCloudError.protectedEvidence }
        let identity = String(conflict.key.dropFirst(5))
        var receipts: [String: RunReviewStore.Receipt] = [:]
        for revision in known.values where revision.ownerID == chosen.ownerID && revision.scope == .reviews && revision.key.hasPrefix("receipt/") {
            guard let bytes = revision.payload else { throw RunCloudError.invalid }
            let receipt = try RunCloudCodec.decode(RunReviewStore.Receipt.self, bytes)
            guard !receipt.id.isEmpty, revision.key == "receipt/" + receipt.id, receipt.review.userID == chosen.ownerID else { throw RunCloudError.invalid }
            if let existing = receipts[receipt.id], existing != receipt { throw RunCloudError.invalid }
            receipts[receipt.id] = receipt
        }
        func chain(_ payload: Data) throws -> [RunReviewStore.Receipt] {
            var id: String? = try RunCloudCodec.decode(String.self, payload)
            var seen = Set<String>(), result: [RunReviewStore.Receipt] = []
            while let current = id {
                guard seen.insert(current).inserted, let receipt = receipts[current], receipt.review.identity == identity else { throw RunCloudError.invalid }
                result.append(receipt); id = receipt.review.expectedReceiptID
            }
            return result
        }
        let candidate = try chain(selected)
        for branch in conflict.versions {
            guard let payload = branch.payload else { continue }
            guard try chain(payload).allSatisfy({ candidate.contains($0) }) else { throw RunCloudError.protectedEvidence }
        }
    }
}
