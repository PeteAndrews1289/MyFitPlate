#if canImport(ActivityKit)
import AppIntents
import ActivityKit
import Foundation
import MyFitPlateShared

public struct EndFastIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "End Fast"
    
    public init() {}

    @Parameter(title: "Fast identifier") public var sessionID: String?
    @Parameter(title: "Account scope") public var ownerScope: String?
    @Parameter(title: "Expected revision") public var revision: Int?

    public init(sessionID: UUID?, ownerScope: String?, revision: Int?) {
        self.sessionID = sessionID?.uuidString
        self.ownerScope = ownerScope
        self.revision = revision
    }
    
    public func perform() async throws -> some IntentResult {
        guard let sessionID, let identity = UUID(uuidString: sessionID), let ownerScope, let revision else {
            throw NSError(domain: "MyFitPlate.Fasting", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Open MyFitPlate to recover this older timer before ending it."])
        }
        // Durable End must be accepted before the projection disappears.
        _ = try FastingSessionStore().end(ownerScope: ownerScope, sessionID: identity, expectedRevision: revision)
        for activity in Activity<FastingActivityAttributes>.activities
        where activity.attributes.sessionID == identity && activity.attributes.ownerScope == ownerScope {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        
        return .result()
    }
}
#endif
