import AppIntents
import WidgetKit
import MyFitPlateShared

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Queues 8 oz of water for MyFitPlate to save.")
    
    func perform() async throws -> some IntentResult {
        // Log 8oz of water
        try SharedDataManager.shared.logPendingWater(ounces: 8.0)
        
        // This tells the widget to reload
        // In a more complex app, you could have the widget show +8 pending.
        WidgetCenter.shared.reloadAllTimelines()
        
        return .result(dialog: "Queued 8 oz. MyFitPlate will finish saving it when the app opens.")
    }
}
