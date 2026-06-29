import Foundation

public enum MenstrualPhase: String, CaseIterable, Identifiable {
    case menstrual, follicular, ovulatory, luteal
    public var id: Self { self }
}

public struct CycleSettings: Codable {
    public var typicalCycleLength: Int = 28
    public var typicalPeriodLength: Int = 5
    public init(typicalCycleLength: Int = 28, typicalPeriodLength: Int = 5) {
        self.typicalCycleLength = typicalCycleLength
        self.typicalPeriodLength = typicalPeriodLength
    }
}

public struct CycleDay {
    public let date: Date
    public let cycleDayNumber: Int
    public let phase: MenstrualPhase
    public init(date: Date, cycleDayNumber: Int, phase: MenstrualPhase) {
        self.date = date
        self.cycleDayNumber = cycleDayNumber
        self.phase = phase
    }
}

public struct AIInsight: Codable {
    public struct TrainingFocus: Codable {
        public let title: String
        public let description: String
        public init(title: String, description: String) {
            self.title = title
            self.description = description
        }
    }
    public let phaseTitle: String
    public let phaseDescription: String
    public let trainingFocus: TrainingFocus
    public let hormonalState: String
    public let energyLevel: String
    public let nutritionTip: String
    public let symptomTip: String
    public init(phaseTitle: String, phaseDescription: String, trainingFocus: TrainingFocus, hormonalState: String, energyLevel: String, nutritionTip: String, symptomTip: String) {
        self.phaseTitle = phaseTitle
        self.phaseDescription = phaseDescription
        self.trainingFocus = trainingFocus
        self.hormonalState = hormonalState
        self.energyLevel = energyLevel
        self.nutritionTip = nutritionTip
        self.symptomTip = symptomTip
    }
}
