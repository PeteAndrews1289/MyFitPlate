import WatchKit
import WatchConnectivity
import OSLog
import MyFitPlateCore

private let watchConnectivityLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MyFitPlateWatch",
    category: "WatchConnectivity"
)

class AppDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate, ObservableObject {
    @Published var message: String = "no message"
    
    @Published var goalCal: Double = 0.0
    @Published var userCal: Double = 0.0
    
    @Published var userProt: Double = 0.0
    @Published var totalProt: Double = 0.0
    
    @Published var userCarb: Double = 0.0
    @Published var totalCarb: Double = 0.0
    
    @Published var userFat: Double = 0.0
    @Published var totalFat: Double = 0.0
    
    @Published var userWeight: Double = 0.0
    @Published var goalWeight: Double = 0.0
    
    @Published var currWater: Double = 0.0
    @Published var goalWater: Double = 0.0
    @Published var sleepScore: Int = 0
    @Published var sleepHours: Double = 0.0
    @Published var usesMetric: Bool = false
    @Published var nextAction: DailyNextAction?
    @Published var recentMeal: WatchMealSnapshot?
    @Published var repeatMealStatus: String?
    @Published var repeatMealQueued = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var isSyncRequestPending = false

    private var accountScope: String?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isPhoneReachable = activationState == .activated && session.isReachable
        }
        if activationState == .activated {
            watchConnectivityLog.debug("Watch session activated.")
            let receivedContext = session.receivedApplicationContext
            if !receivedContext.isEmpty {
                watchConnectivityLog.debug("Processing received context on activation.")
                update(with: receivedContext)
            }
            requestSyncIfPossible(session)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
        if session.isReachable {
            requestSyncIfPossible(session)
        }
    }

    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        if session.isCompanionAppInstalled {
            requestSyncIfPossible(session)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        watchConnectivityLog.debug("Received application context on watch.")
        update(with: applicationContext)
    }

    private func update(with context: [String: Any]) {
        DispatchQueue.main.async {
            if context[WatchQuickActionPayload.clearAccount] as? Bool == true {
                self.clearAccountData()
                return
            }
            self.goalCal = context["goalCal"] as? Double ?? self.goalCal
            self.userCal = context["userCal"] as? Double ?? self.userCal
            self.userProt = context["userProt"] as? Double ?? self.userProt
            self.totalProt = context["totalProt"] as? Double ?? self.totalProt
            self.userCarb = context["userCarb"] as? Double ?? self.userCarb
            self.totalCarb = context["totalCarb"] as? Double ?? self.totalCarb
            self.userFat = context["userFat"] as? Double ?? self.userFat
            self.totalFat = context["totalFat"] as? Double ?? self.totalFat
            self.userWeight = context["userWeight"] as? Double ?? self.userWeight
            self.goalWeight = context["goalWeight"] as? Double ?? self.goalWeight
            self.currWater = context["currWater"] as? Double ?? self.currWater
            self.goalWater = context["goalWater"] as? Double ?? self.goalWater
            self.sleepScore = context["sleepScore"] as? Int ?? self.sleepScore
            self.sleepHours = context["sleepHours"] as? Double ?? self.sleepHours
            self.usesMetric = context["usesMetric"] as? Bool ?? self.usesMetric
            self.accountScope = context[WatchQuickActionPayload.accountScope] as? String
            if let timestamp = context[WatchQuickActionPayload.generatedAt] as? TimeInterval {
                self.lastSyncDate = Date(timeIntervalSince1970: timestamp)
            }
            self.nextAction = Self.decode(
                DailyNextAction.self,
                from: context[WatchQuickActionPayload.nextAction]
            )
            self.recentMeal = Self.decode(
                WatchMealSnapshot.self,
                from: context[WatchQuickActionPayload.recentMeal]
            )
            self.repeatMealStatus = nil
            self.repeatMealQueued = false
            self.isSyncRequestPending = false
        }
    }

    func requestSync() {
        requestSyncIfPossible()
    }

    private func requestSyncIfPossible(_ session: WCSession = .default) {
        let canReachPhone = session.activationState == .activated && session.isReachable
        DispatchQueue.main.async {
            self.isPhoneReachable = canReachPhone
        }
        guard canReachPhone else {
            DispatchQueue.main.async {
                self.isSyncRequestPending = false
            }
            return
        }

        let requestDate = Date()
        DispatchQueue.main.async {
            self.isSyncRequestPending = true
        }
        session.sendMessage(
            [WatchQuickActionPayload.syncRequest: true],
            replyHandler: nil,
            errorHandler: { error in
                DispatchQueue.main.async {
                    self.isSyncRequestPending = false
                    self.isPhoneReachable = session.isReachable
                }
                watchConnectivityLog.error(
                    "Watch sync request failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if let lastSyncDate = self.lastSyncDate, lastSyncDate >= requestDate { return }
            self.isSyncRequestPending = false
        }
    }

    /// Logs water optimistically on the watch and queues it for the phone. transferUserInfo
    /// survives unreachability — the phone drains it next time it runs, then pushes fresh
    /// context back, replacing our optimistic value with the real total.
    func logWater(ounces: Double) {
        guard ounces > 0, let accountScope else { return }
        guard WCSession.default.activationState == .activated else {
            watchConnectivityLog.error("Cannot queue water log: session not activated.")
            return
        }
        currWater += ounces
        WCSession.default.transferUserInfo([
            "logWaterOunces": ounces,
            WatchQuickActionPayload.accountScope: accountScope
        ])
    }

    func repeatRecentMeal() {
        guard let recentMeal, let accountScope else { return }
        guard WCSession.default.activationState == .activated else {
            repeatMealStatus = "Open MyFitPlate on your phone, then try again."
            repeatMealQueued = false
            return
        }
        let request = WatchMealRepeatRequest(accountScope: accountScope, snapshot: recentMeal)
        guard let data = try? JSONEncoder().encode(request) else {
            repeatMealStatus = "This meal could not be queued."
            repeatMealQueued = false
            return
        }
        WCSession.default.transferUserInfo([
            WatchQuickActionPayload.repeatMealRequest: data
        ])
        repeatMealStatus = "Queued for your phone"
        repeatMealQueued = true
    }

    private func clearAccountData() {
        goalCal = 0
        userCal = 0
        userProt = 0
        totalProt = 0
        userCarb = 0
        totalCarb = 0
        userFat = 0
        totalFat = 0
        userWeight = 0
        goalWeight = 0
        currWater = 0
        goalWater = 0
        nextAction = nil
        recentMeal = nil
        repeatMealStatus = nil
        repeatMealQueued = false
        accountScope = nil
        lastSyncDate = nil
        isSyncRequestPending = false
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from value: Any?) -> Value? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
