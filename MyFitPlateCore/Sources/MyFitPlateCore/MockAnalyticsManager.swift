#if DEBUG
import Foundation

public final class MockAnalyticsManager: AnalyticsManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLoggedEvents: [(name: String, parameters: [String: Any]?)] = []
    private var storedUserProperties: [String: String] = [:]
    private var storedUserIDs: [String?] = []
    private var storedTypedEvents: [(event: AppEvent, parameters: [String: Any])] = []

    public init() {}

    public var loggedEvents: [(name: String, parameters: [String: Any]?)] {
        lock.withLock { storedLoggedEvents }
    }

    public var userProperties: [String: String] {
        lock.withLock { storedUserProperties }
    }

    public var userIDs: [String?] {
        lock.withLock { storedUserIDs }
    }

    public var typedEvents: [(event: AppEvent, parameters: [String: Any])] {
        lock.withLock { storedTypedEvents }
    }

    public func logEvent(_ name: String, parameters: [String: Any]?) {
        lock.withLock {
            storedLoggedEvents.append((name, parameters))
        }
    }

    public func setUserProperty(_ value: String, forName name: String) {
        lock.withLock {
            storedUserProperties[name] = value
        }
    }

    public func setUserID(_ id: String?) {
        lock.withLock {
            storedUserIDs.append(id)
        }
    }

    public func log(_ event: AppEvent, _ parameters: [String: Any]) {
        lock.withLock {
            storedTypedEvents.append((event, parameters))
        }
    }
}
#endif
