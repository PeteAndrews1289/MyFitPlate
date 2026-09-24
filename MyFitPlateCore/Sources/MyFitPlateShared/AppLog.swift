import OSLog

public enum AppLog {
    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let ai = Logger(subsystem: subsystem, category: "AI")
    public static let data = Logger(subsystem: subsystem, category: "Data")
    public static let health = Logger(subsystem: subsystem, category: "Health")
    public static let liveActivity = Logger(subsystem: subsystem, category: "LiveActivity")
    public static let mealPlanner = Logger(subsystem: subsystem, category: "MealPlanner")
    public static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    public static let recipes = Logger(subsystem: subsystem, category: "Recipes")
    public static let social = Logger(subsystem: subsystem, category: "Social")
    public static let watch = Logger(subsystem: subsystem, category: "WatchConnectivity")
    public static let workouts = Logger(subsystem: subsystem, category: "Workouts")

    private static let subsystem = Bundle.main.bundleIdentifier ?? "MyFitPlate"
}
