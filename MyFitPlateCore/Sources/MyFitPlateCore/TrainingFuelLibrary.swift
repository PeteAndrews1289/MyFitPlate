import Foundation

/// Stable execution identity. Titles and clock proximity are never proof of completion.
public struct TrainingFuelSessionIdentity: Codable, Equatable, Sendable {
    public var programID: String?
    public var programSlot: Int?
    public var blockID: String?
    public var revisionID: String?
    public var commitmentID: String?
    public var runPlanID: String?
    public init(programID: String? = nil, programSlot: Int? = nil, blockID: String? = nil,
                revisionID: String? = nil, commitmentID: String? = nil, runPlanID: String? = nil) {
        self.programID = programID; self.programSlot = programSlot; self.blockID = blockID
        self.revisionID = revisionID; self.commitmentID = commitmentID; self.runPlanID = runPlanID
    }
}

public struct TrainingFuelCalculationEvidence: Codable, Equatable, Sendable {
    public static let currentRuleset = "bounded-daily-budget-v1"
    public let ruleset: String
    public let calculatedAt: Date
    public let notes: [TrainingFuelPlannerPlan.Note]
    public let assumptions: [TrainingFuelSessionCandidate.Assumption]
    public let provisional: Bool
    public let individualEstimate: TrainingFuelDemandPreview?
    public let calculationTimeZoneIdentifier: String?
    public init(plan: TrainingFuelPlannerPlan, draft: TrainingFuelPlanDraft, at date: Date, calendar: Calendar = .current) {
        individualEstimate = draft.preference.personalInputs.map { TrainingFuelIndividualEstimateRules.preview(session: draft.session, inputs: $0, now: date, calendar: calendar) }
        calculationTimeZoneIdentifier = individualEstimate == nil ? nil : calendar.timeZone.identifier
        ruleset = individualEstimate?.ruleset ?? Self.currentRuleset; calculatedAt = date; notes = plan.notes
        assumptions = draft.assumptions ?? []; provisional = plan.status == .outsideToday
    }
}

/// A destination keeps this exact request through portion edits, cancellation and retry.
public struct TrainingFuelHandoffContext: Codable, Equatable, Sendable {
    public let ownerID: String
    public let planRevisionID: String
    public let session: TrainingFuelSessionIdentity?
    public let day: TrainingCalendarDay
    public let ruleset: String
    public let requestID: String
    public let createdAt: Date
    public let timeZoneIdentifier: String?
    public let foodTolerance: TrainingFuelPersonalInputs.Tolerance?
    public var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        return value
    }
    public init(ownerID: String, planRevisionID: String, session: TrainingFuelSessionIdentity?, day: TrainingCalendarDay,
                ruleset: String, requestID: String = UUID().uuidString, createdAt: Date = Date(), timeZone: TimeZone = .current,
                foodTolerance: TrainingFuelPersonalInputs.Tolerance? = nil) {
        self.ownerID = ownerID; self.planRevisionID = planRevisionID; self.session = session; self.day = day
        self.ruleset = ruleset; self.requestID = requestID; self.createdAt = createdAt; timeZoneIdentifier = timeZone.identifier
        self.foodTolerance = foodTolerance
    }
}

public struct TrainingFuelFoodLink: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let requestID: String
    public let foodID: String
    public let day: TrainingCalendarDay
    public let phase: TrainingFuelAllocation.Phase
    public let name: String
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let linkedAt: Date
    public init(requestID: String, food: FoodItem, day: TrainingCalendarDay, phase: TrainingFuelAllocation.Phase, at: Date) {
        id = requestID + ":" + food.id; self.requestID = requestID; foodID = food.id; self.day = day; self.phase = phase
        name = food.name; calories = food.calories; protein = food.protein; carbs = food.carbs; linkedAt = at
    }
}

public struct TrainingFuelFeedback: Codable, Equatable, Sendable {
    public let energy: Int
    public let comfort: Int
    public let practicality: Int
    public let recordedAt: Date
    public init(energy: Int, comfort: Int, practicality: Int, recordedAt: Date = Date()) {
        self.energy = min(5, max(1, energy)); self.comfort = min(5, max(1, comfort))
        self.practicality = min(5, max(1, practicality)); self.recordedAt = recordedAt
    }
}

/// Immutable revisions form a graph. Concurrent edits remain separate reviewable heads;
/// their timestamps do not grant permission to erase another device's accepted work.
public struct TrainingFuelRevision: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let parents: [String]
    public let plan: TrainingFuelConfirmedPlan
    public let archivedAt: Date?
    public let createdAt: Date
    public let reason: String
    public init(id: String = UUID().uuidString, parents: [String], plan: TrainingFuelConfirmedPlan,
                archivedAt: Date? = nil, createdAt: Date = Date(), reason: String) {
        self.id = id; self.parents = parents.sorted(); self.plan = plan; self.archivedAt = archivedAt
        self.createdAt = createdAt; self.reason = reason
    }
}

public struct TrainingFuelCloudState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revisions: [String: TrainingFuelRevision] = [:]
    public init() {}
    public var planIDs: [String] { Array(Set(revisions.values.map { $0.plan.id })).sorted() }
    public func heads(planID: String) -> [TrainingFuelRevision] {
        let values = revisions.values.filter { $0.plan.id == planID }
        let superseded = Set(values.flatMap(\.parents))
        return values.filter { !superseded.contains($0.id) }.sorted { $0.id < $1.id }
    }
    public var current: [TrainingFuelRevision] {
        planIDs.compactMap { id in let heads = heads(planID: id); return heads.count == 1 ? heads.first : nil }
            .sorted { $0.plan.draft.scheduledAt == $1.plan.draft.scheduledAt ? $0.id < $1.id : $0.plan.draft.scheduledAt > $1.plan.draft.scheduledAt }
    }
    public var conflicts: [String] { planIDs.filter { heads(planID: $0).count > 1 } }
    public func merging(_ other: Self) throws -> Self {
        guard (1...2).contains(schemaVersion), (1...2).contains(other.schemaVersion) else { throw TrainingFuelLibraryError.unreadable }
        var next = self
        next.schemaVersion = max(schemaVersion, other.schemaVersion)
        for (id, revision) in other.revisions {
            if let existing = next.revisions[id], existing != revision { throw TrainingFuelLibraryError.unreadable }
            guard id == revision.id else { throw TrainingFuelLibraryError.unreadable }
            next.revisions[id] = revision
        }
        for revision in next.revisions.values {
            guard revision.parents.allSatisfy({ next.revisions[$0]?.plan.id == revision.plan.id }),
                  !revision.parents.contains(revision.id) else { throw TrainingFuelLibraryError.unreadable }
        }
        var resolved = Set<String>()
        while true {
            let eligible = next.revisions.values.filter { !resolved.contains($0.id) && Set($0.parents).isSubset(of: resolved) }
            if eligible.isEmpty { break }
            resolved.formUnion(eligible.map(\.id))
        }
        guard resolved.count == next.revisions.count else { throw TrainingFuelLibraryError.unreadable }
        if next.revisions.values.contains(where: { $0.plan.draft.preference.personalInputs != nil }) { next.schemaVersion = 2 }
        return next
    }
}

public protocol TrainingFuelRepository: AnyObject {
    /// Return the server-accepted union; offline/uncertain writes throw and remain pending locally.
    @MainActor func merge(_ state: TrainingFuelCloudState, userID: String) async throws -> TrainingFuelCloudState
}

public enum TrainingFuelLibraryError: LocalizedError {
    case accountChanged, unreadable, changed, budgetChanged, wrongDay, unverifiedFood
    public var errorDescription: String? {
        switch self {
        case .accountChanged: "Reopen Training Fuel in the account that created this plan."
        case .unreadable: "The saved fuel library could not be verified. Its original data is kept on this device."
        case .changed: "This plan changed or has conflicting edits. Review the latest version before continuing."
        case .budgetChanged: "Your remaining fuel target changed. Review it again before logging; your food draft is kept."
        case .wrongDay: "This fuel target belongs to another day. Reopen the plan for the intended day."
        case .unverifiedFood: "The food save is accepted, but its fuel link needs retry. Your food will not be added again."
        }
    }
}

struct TrainingFuelLibraryCheckpoint: Codable {
    var schemaVersion = 1
    var state = TrainingFuelCloudState()
    var selectedID: String?
    var editingNew: Bool?
    var draft: TrainingFuelPlanDraft?
    var pending = false
    var pendingLinks: [String: TrainingFuelPendingLink]?
}
