import AppIntents
import WidgetKit

struct LogPlannedMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Planned Meal"
    static var description = IntentDescription("Logs the user's scheduled meal (e.g. Breakfast).")
    
    @Parameter(title: "Meal Name")
    var mealName: String
    
    init() {}
    
    init(mealName: String) {
        self.mealName = mealName
    }
    
    func perform() async throws -> some IntentResult {
        // In a real app, you would fetch today's plan from SharedDataManager and insert the meal directly.
        // For now, we will just reload the timeline to simulate interaction.
        print("Logging planned meal: \(mealName)")
        
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}
