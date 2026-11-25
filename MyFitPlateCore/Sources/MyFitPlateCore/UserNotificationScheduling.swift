import UserNotifications

/// Seam over UNUserNotificationCenter. The real center can't even be constructed outside an
/// app bundle (bundleProxyForCurrentProcess throws), so anything that talks to it directly is
/// untestable from the package — inject this instead.
public protocol UserNotificationScheduling {
    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?)
    func removePendingRequests(withIdentifiers identifiers: [String])
    func setBadgeCount(_ count: Int)
    func pendingRequests(completion: @escaping ([UNNotificationRequest]) -> Void)
    func deliveredRequestIdentifiers(completion: @escaping ([String]) -> Void)
    func removeDeliveredRequests(withIdentifiers identifiers: [String])
    func setReminderCategories(_ categories: Set<UNNotificationCategory>)
}

public extension UserNotificationScheduling {
    func pendingRequests(completion: @escaping ([UNNotificationRequest]) -> Void) { completion([]) }
    func deliveredRequestIdentifiers(completion: @escaping ([String]) -> Void) { completion([]) }
    func removeDeliveredRequests(withIdentifiers identifiers: [String]) {}
    func setReminderCategories(_ categories: Set<UNNotificationCategory>) {}
}

public struct SystemUserNotificationCenter: UserNotificationScheduling {
    public init() {}

    // Computed so constructing the wrapper (e.g. as a default argument during tests)
    // never touches the real center — only actually scheduling does.
    private var center: UNUserNotificationCenter { .current() }

    public func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    public func requestAuthorization(options: UNAuthorizationOptions, completion: @escaping (Bool, Error?) -> Void) {
        center.requestAuthorization(options: options, completionHandler: completion)
    }

    public func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?) {
        center.add(request, withCompletionHandler: completion)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func pendingRequests(completion: @escaping ([UNNotificationRequest]) -> Void) { center.getPendingNotificationRequests(completionHandler: completion) }
    public func deliveredRequestIdentifiers(completion: @escaping ([String]) -> Void) {
        center.getDeliveredNotifications { completion($0.map { $0.request.identifier }) }
    }
    public func removeDeliveredRequests(withIdentifiers identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    public func setReminderCategories(_ categories: Set<UNNotificationCategory>) {
        center.getNotificationCategories { existing in
            let ids = Set(categories.map(\.identifier))
            self.center.setNotificationCategories(Set(existing.filter { !ids.contains($0.identifier) }).union(categories))
        }
    }

    public func setBadgeCount(_ count: Int) {
        #if os(iOS)
        center.setBadgeCount(count)
        #endif
    }
}
