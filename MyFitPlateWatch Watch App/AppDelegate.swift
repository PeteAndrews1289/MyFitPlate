import WatchKit
import WatchConnectivity

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
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            print("✅ Watch session activated.")
            if let receivedContext = session.receivedApplicationContext as [String: Any]? {
                print("📦 Processing received context on activation.")
                update(with: receivedContext)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("📦 Received application context on watch.")
        update(with: applicationContext)
    }

    private func update(with context: [String: Any]) {
        DispatchQueue.main.async {
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
        }
    }
}
