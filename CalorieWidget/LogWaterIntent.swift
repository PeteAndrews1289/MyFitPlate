import AppIntents
import WidgetKit

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Logs 8oz of water.")
    
    func perform() async throws -> some IntentResult {
        // Log 8oz of water
        SharedDataManager.shared.logPendingWater(ounces: 8.0)
        
        // This tells the widget to reload
        // In a more complex app, you could have the widget show +8 pending.
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result()
    }
}
