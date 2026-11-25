import Foundation

public enum WorkoutActivitySessionRules {
    public struct ExistingActivity: Equatable, Sendable {
        public let id: String
        public let sessionID: String?

        public init(id: String, sessionID: String?) {
            self.id = id
            self.sessionID = sessionID
        }
    }

    public struct Reconciliation: Equatable, Sendable {
        public let reusableID: String?
        public let retiredIDs: [String]
    }

    /// Session IDs are random, account-scoped draft identities. A routine name is not
    /// sufficient: another account or a later workout may use exactly the same routine.
    public static func reconcile(sessionID: String?, activities: [ExistingActivity]) -> Reconciliation {
        let identity = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reusable = identity.flatMap { id in
            id.isEmpty ? nil : activities.first(where: { $0.sessionID == id })?.id
        }
        return Reconciliation(reusableID: reusable, retiredIDs: activities.map(\.id).filter { $0 != reusable })
    }
}
