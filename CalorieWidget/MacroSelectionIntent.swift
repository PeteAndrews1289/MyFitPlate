
import AppIntents
import SwiftUI

struct MacroSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select a Metric"
    static var description = "Choose which metric to display in the widget."

    @Parameter(title: "Metric", default: .calories)
    var metric: MacroMetric
}

enum MacroMetric: String, AppEnum {
    case calories
    case protein
    case carbs
    case fats

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static var caseDisplayRepresentations: [MacroMetric : DisplayRepresentation] = [
        .calories: "Calories",
        .protein: "Protein",
        .carbs: "Carbs",
        .fats: "Fats"
    ]
}
