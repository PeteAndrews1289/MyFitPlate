/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The delegate of the watchOS app.
*/

import WatchKit
import WatchConnectivity

class AppDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate ,ObservableObject {
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
    
    lazy var sessionDelegator: SessionDelegator = {
        return SessionDelegator()
    }()

    // Hold the KVO observers to keep observing the change in the extension's lifetime.
    //
    private var activationStateObservation: NSKeyValueObservation?
    private var hasContentPendingObservation: NSKeyValueObservation?

    // An array to keep the background tasks.
    //
    private var wcBackgroundTasks = [WKWatchConnectivityRefreshBackgroundTask]()
    
    override init() {
        super.init()
        assert(WCSession.isSupported(), "This sample requires a platform supporting Watch Connectivity!")
                
        // Apps must complete WKWatchConnectivityRefreshBackgroundTask. Otherwise, tasks keep consuming
        // the background executing time and eventually cause a crash.
        // The timing to complete the tasks is when the current WCSession turns to a state other than .activated
        // or hasContentPending flips false (see completeBackgroundTasks), so use KVO to observe
        // the changes of the two properties.
        //
        activationStateObservation = WCSession.default.observe(\.activationState) { _, _ in
            DispatchQueue.main.async {
                self.completeBackgroundTasks()
            }
        }
        hasContentPendingObservation = WCSession.default.observe(\.hasContentPending) { _, _ in
            DispatchQueue.main.async {
                self.completeBackgroundTasks()
            }
        }

        // Activate the session asynchronously as early as possible.
        // When the system needs to launch the app to run a background task, this saves some background runtime budget.
        //
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("📲 Received message from iPhone: \(message)")
        // TODO: Update your watch UI with new data here
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("✅ Watch session activation completed with state: \(activationState.rawValue)")
    }

    
    // Complete the background tasks, and schedule a snapshot refresh.
    //
    func completeBackgroundTasks() {
        guard !wcBackgroundTasks.isEmpty else { return }

        guard WCSession.default.activationState == .activated,
            WCSession.default.hasContentPending == false else { return }
        
        wcBackgroundTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        
        // Use Logger to log tasks for debugging purposes.
        //
        Logger.shared.append(line: "\(#function):\(wcBackgroundTasks) was completed!")

        // Schedule a snapshot refresh if the UI is updated by background tasks.
        //
        let date = Date(timeIntervalSinceNow: 1)
        WKApplication.shared().scheduleSnapshotRefresh(withPreferredDate: date, userInfo: nil) { error in
            
            if let error = error {
                print("scheduleSnapshotRefresh error: \(error)!")
            }
        }
        wcBackgroundTasks.removeAll()
    }
    
    // Apps must complete WKWatchConnectivityRefreshBackgroundTask after the pending data is received.
    // This sample retains the tasks first, and complete them in the following cases:
    // 1. hasContentPending flips false, meaning no pending data waiting for processing. Pending data means
    //    the data the device receives prior to when the WCSession gets activated.
    //    More data might arrive, but it isn't pending when the session gets activated.
    // 2. The end of the handle method.
    //    This happens when hasContentPending flips to false before the app retains the tasks.
    //
    
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let wcTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                wcBackgroundTasks.append(wcTask)
                Logger.shared.append(line: "\(#function):\(wcTask.description) was appended!")
            } else {
                task.setTaskCompletedWithSnapshot(false)
                Logger.shared.append(line: "\(#function):\(task.description) was completed!")
            }
        }
        completeBackgroundTasks()
    }
    
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
            print("⌚️ Received on watch:")
        
            if let text = message["text"] as? String {
                DispatchQueue.main.async {
                    self.message = text
                }
            }
        
            if let goal = message["goalCal"] as? Double {
                DispatchQueue.main.async {
                    self.goalCal = goal
                }
            }
            
            if let user = message["userCal"] as? Double {
                DispatchQueue.main.async {
                    self.userCal = user
                }
            }
        
            if let userProtein = message["userProt"] as? Double {
                DispatchQueue.main.async {
                    self.userProt = userProtein
                }
            }
        
            if let totalProtein = message["totalProt"] as? Double {
                DispatchQueue.main.async {
                    self.totalProt = totalProtein
                }
            }
            
            if let userCarb = message["userCarb"] as? Double {
                DispatchQueue.main.async {
                    self.userCarb = userCarb
                }
            }
        
            if let totalCarb = message["totalCarb"] as? Double {
                DispatchQueue.main.async {
                    self.totalCarb = totalCarb
                }
            }

        
            if let userFat = message["userFat"] as? Double {
                DispatchQueue.main.async {
                    self.userFat = userFat
                }
            }
            
            if let totalFat = message["totalFat"] as? Double {
                DispatchQueue.main.async {
                    self.totalFat = totalFat
                }
            }
        
            if let goalWeight = message["goalWeight"] as? Double {
                DispatchQueue.main.async {
                    self.goalWeight = goalWeight
                }
            }
        
            if let userWeight = message["userWeight"] as? Double {
                DispatchQueue.main.async {
                    self.userWeight = userWeight
                }
            }
        
            if let currWater = message["currWater"] as? Double {
                DispatchQueue.main.async {
                    self.currWater = currWater
                }
            }
        
            if let goalWater = message["goalWater"] as? Double {
                DispatchQueue.main.async {
                    self.goalWater = goalWater
                }
            }
                    
        replyHandler(["response": "✅ Received on watch userProt \(self.userProt),  Received on watch userCarb \(self.userCarb), Received on watch userFat \(self.userFat), Received on watch totalProt \(self.totalProt), Received on watch totalCarb \(self.totalCarb),Received on watch totalFat \(self.totalFat)"])
        }
    
//    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
//        print("📦 Received application context on watch: \(applicationContext)")
//
//        DispatchQueue.main.async {
//            self.goalCal = applicationContext["goalCal"] as? Double ?? self.goalCal
//            self.userCal = applicationContext["userCal"] as? Double ?? self.userCal
//            self.userProt = applicationContext["userProt"] as? Double ?? self.userProt
//            self.totalProt = applicationContext["totalProt"] as? Double ?? self.totalProt
//            self.userCarb = applicationContext["userCarb"] as? Double ?? self.userCarb
//            self.totalCarb = applicationContext["totalCarb"] as? Double ?? self.totalCarb
//            self.userFat = applicationContext["userFat"] as? Double ?? self.userFat
//            self.totalFat = applicationContext["totalFat"] as? Double ?? self.totalFat
//            self.userWeight = applicationContext["userWeight"] as? Double ?? self.userWeight
//            self.goalWeight = applicationContext["goalWeight"] as? Double ?? self.goalWeight
//            self.currWater = applicationContext["currWater"] as? Double ?? self.currWater
//            self.goalWater = applicationContext["goalWater"] as? Double ?? self.goalWater
//        }
//    }
}
