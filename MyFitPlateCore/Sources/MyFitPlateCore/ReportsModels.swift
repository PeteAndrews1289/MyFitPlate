import Foundation
import SwiftUI

public struct MealScore {
    public let grade: String
    public let summary: String
    public let color: Color
    public let calorieScore: Int
    public let macroScore: Int
    public let qualityScore: Int
    public let overallScore: Int
    public let personalizedAISummary: String
    public let improvementTips: [ImprovementTip]
    public let actualCalories: Double
    public let goalCalories: Double
    public let actualProtein: Double
    public let goalProtein: Double
    public let actualCarbs: Double
    public let goalCarbs: Double
    public let actualFats: Double
    public let goalFats: Double
    public let actualFiber: Double
    public let goalFiber: Double
    public let actualSaturatedFat: Double
    public let goalSaturatedFat: Double
    public let actualSodium: Double
    public let goalSodium: Double

    public init(grade: String, summary: String, color: Color, calorieScore: Int, macroScore: Int, qualityScore: Int, overallScore: Int, personalizedAISummary: String, improvementTips: [ImprovementTip], actualCalories: Double, goalCalories: Double, actualProtein: Double, goalProtein: Double, actualCarbs: Double, goalCarbs: Double, actualFats: Double, goalFats: Double, actualFiber: Double, goalFiber: Double, actualSaturatedFat: Double, goalSaturatedFat: Double, actualSodium: Double, goalSodium: Double) {
        self.grade = grade
        self.summary = summary
        self.color = color
        self.calorieScore = calorieScore
        self.macroScore = macroScore
        self.qualityScore = qualityScore
        self.overallScore = overallScore
        self.personalizedAISummary = personalizedAISummary
        self.improvementTips = improvementTips
        self.actualCalories = actualCalories
        self.goalCalories = goalCalories
        self.actualProtein = actualProtein
        self.goalProtein = goalProtein
        self.actualCarbs = actualCarbs
        self.goalCarbs = goalCarbs
        self.actualFats = actualFats
        self.goalFats = goalFats
        self.actualFiber = actualFiber
        self.goalFiber = goalFiber
        self.actualSaturatedFat = actualSaturatedFat
        self.goalSaturatedFat = goalSaturatedFat
        self.actualSodium = actualSodium
        self.goalSodium = goalSodium
    }

    public static let noScore = MealScore(grade: "N/A", summary: "Log a full day of meals to get your score.", color: .gray, calorieScore: 0, macroScore: 0, qualityScore: 0, overallScore: 0, personalizedAISummary: "No data available.", improvementTips: [], actualCalories: 0, goalCalories: 2000, actualProtein: 0, goalProtein: 150, actualCarbs: 0, goalCarbs: 250, actualFats: 0, goalFats: 70, actualFiber: 0, goalFiber: 25, actualSaturatedFat: 0, goalSaturatedFat: 20, actualSodium: 0, goalSodium: 2300)
}

public struct ImprovementTip: Identifiable {
    public let id = UUID()
    public let category: String
    public let advice: String
    public let icon: String
    public let color: Color
    
    public init(category: String, advice: String, icon: String, color: Color) {
        self.category = category
        self.advice = advice
        self.icon = icon
        self.color = color
    }
}

public struct ReportSummary: Identifiable {
    public let id = UUID()
    public let timeframe: String
    public let averageCalories: Double
    public let averageProtein: Double
    public let averageCarbs: Double
    public let averageFats: Double
    public let daysLogged: Int
    
    public init(timeframe: String, averageCalories: Double, averageProtein: Double, averageCarbs: Double, averageFats: Double, daysLogged: Int) {
        self.timeframe = timeframe
        self.averageCalories = averageCalories
        self.averageProtein = averageProtein
        self.averageCarbs = averageCarbs
        self.averageFats = averageFats
        self.daysLogged = daysLogged
    }
}

public struct DateValuePoint: Identifiable, Equatable {
    public let id = UUID()
    public let date: Date
    public let value: Double
    
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct MicroAverageDataPoint: Identifiable {
    public let id = UUID()
    public let name: String
    public let unit: String
    public let averageValue: Double
    public let goalValue: Double
    public var percentageMet: Double { guard goalValue > 0 else { return 0 }; return (averageValue / goalValue) * 100 }
    public var progressViewValue: Double { guard goalValue > 0 else { return 0.0 }; return max(0.0, min(1.0, averageValue / goalValue)) }
    
    public init(name: String, unit: String, averageValue: Double, goalValue: Double) {
        self.name = name
        self.unit = unit
        self.averageValue = averageValue
        self.goalValue = goalValue
    }
}

public struct MealDistributionDataPoint: Identifiable {
    public let id = UUID()
    public let mealName: String
    public let totalCalories: Double
    
    public init(mealName: String, totalCalories: Double) {
        self.mealName = mealName
        self.totalCalories = totalCalories
    }
}

public struct EnhancedSleepReport: Identifiable {
    public let id = UUID()
    public let dateRange: String
    public let averageSleepScore: Int
    public let averageTimeInBed: TimeInterval
    public let averageTimeAsleep: TimeInterval
    public let averageTimeInCore: TimeInterval
    public let averageTimeInDeep: TimeInterval
    public let averageTimeInREM: TimeInterval
    public let averageTimeAwake: TimeInterval
    public let sleepConsistencyScore: Int
    public let sleepConsistencyMessage: String
    public let dailySleepData: [DailySleepStageData]
    
    public init(dateRange: String, averageSleepScore: Int, averageTimeInBed: TimeInterval, averageTimeAsleep: TimeInterval, averageTimeInCore: TimeInterval, averageTimeInDeep: TimeInterval, averageTimeInREM: TimeInterval, averageTimeAwake: TimeInterval, sleepConsistencyScore: Int, sleepConsistencyMessage: String, dailySleepData: [DailySleepStageData]) {
        self.dateRange = dateRange
        self.averageSleepScore = averageSleepScore
        self.averageTimeInBed = averageTimeInBed
        self.averageTimeAsleep = averageTimeAsleep
        self.averageTimeInCore = averageTimeInCore
        self.averageTimeInDeep = averageTimeInDeep
        self.averageTimeInREM = averageTimeInREM
        self.averageTimeAwake = averageTimeAwake
        self.sleepConsistencyScore = sleepConsistencyScore
        self.sleepConsistencyMessage = sleepConsistencyMessage
        self.dailySleepData = dailySleepData
    }

    public struct DailySleepStageData: Identifiable {
        public let id = UUID()
        public let date: Date
        public let timeInBed: TimeInterval
        public let timeAsleep: TimeInterval
        public let timeCore: TimeInterval
        public let timeDeep: TimeInterval
        public let timeREM: TimeInterval
        public let timeAwake: TimeInterval
        public var weekday: String {
            let formatter = DateFormatter(); formatter.dateFormat = "EEE"
            let calendar = Calendar.current
            let displayDate = calendar.date(byAdding: .hour, value: 12, to: date) ?? date
            return formatter.string(from: displayDate)
        }
        
        public init(date: Date, timeInBed: TimeInterval, timeAsleep: TimeInterval, timeCore: TimeInterval, timeDeep: TimeInterval, timeREM: TimeInterval, timeAwake: TimeInterval) {
            self.date = date
            self.timeInBed = timeInBed
            self.timeAsleep = timeAsleep
            self.timeCore = timeCore
            self.timeDeep = timeDeep
            self.timeREM = timeREM
            self.timeAwake = timeAwake
        }
    }
}
