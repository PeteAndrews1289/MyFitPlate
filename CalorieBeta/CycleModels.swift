import Foundation

enum MenstrualPhase: String, CaseIterable, Identifiable {
    case menstrual, follicular, ovulatory, luteal
    var id: Self { self }
}

struct CycleSettings: Codable {
    var typicalCycleLength: Int = 28
    var typicalPeriodLength: Int = 5
}

struct CycleDay {
    let date: Date
    let cycleDayNumber: Int
    let phase: MenstrualPhase
}

struct AIInsight: Codable {
    struct TrainingFocus: Codable {
        let title: String
        let description: String
    }
    let phaseTitle: String
    let phaseDescription: String
    let trainingFocus: TrainingFocus
    let hormonalState: String
    let energyLevel: String
    let nutritionTip: String
    let symptomTip: String
}
