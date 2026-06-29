import XCTest
@testable import MyFitPlateCore

final class CycleTrackingRulesTests: XCTestCase {

    func testDeterminePhase() {
        // Typical cycle: 28 days, period: 5 days
        // Ovulation start: (28/2) - 2 = 12
        // Ovulation end: (28/2) + 2 = 16
        
        let menstrualPhase1 = CycleTrackingRules.determinePhase(cycleDay: 1, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(menstrualPhase1, .menstrual)
        
        let menstrualPhase5 = CycleTrackingRules.determinePhase(cycleDay: 5, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(menstrualPhase5, .menstrual)
        
        let follicularPhase = CycleTrackingRules.determinePhase(cycleDay: 6, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(follicularPhase, .follicular)
        
        let follicularPhase11 = CycleTrackingRules.determinePhase(cycleDay: 11, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(follicularPhase11, .follicular)
        
        let ovulatoryPhase12 = CycleTrackingRules.determinePhase(cycleDay: 12, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(ovulatoryPhase12, .ovulatory)
        
        let ovulatoryPhase16 = CycleTrackingRules.determinePhase(cycleDay: 16, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(ovulatoryPhase16, .ovulatory)
        
        let lutealPhase17 = CycleTrackingRules.determinePhase(cycleDay: 17, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(lutealPhase17, .luteal)
        
        let lutealPhase28 = CycleTrackingRules.determinePhase(cycleDay: 28, typicalPeriodLength: 5, typicalCycleLength: 28)
        XCTAssertEqual(lutealPhase28, .luteal)
    }

    func testCreateAIInsightPromptWithNoLogs() {
        let prompt = CycleTrackingRules.createAIInsightPrompt(cycleDayNumber: 14, phase: .ovulatory, goal: "Lose", recentLogs: [])
        
        XCTAssertTrue(prompt.contains("Day 14 of their cycle"))
        XCTAssertTrue(prompt.contains("ovulatory phase"))
        XCTAssertTrue(prompt.contains("Lose weight"))
        XCTAssertTrue(prompt.contains("No recent activity logged."))
        XCTAssertTrue(prompt.contains("Your response MUST be a valid JSON object"))
    }

    func testCreateAIInsightPromptWithLogs() {
        let meal = Meal(id: UUID(), name: "Lunch", foodItems: [
            FoodItem(id: "1", name: "Apple", calories: 100, protein: 1, carbs: 25, fats: 0, servingSize: "1", servingUnit: "medium")
        ])
        let log = DailyLog(id: "1", date: Date(timeIntervalSince1970: 0), meals: [meal])
        
        let prompt = CycleTrackingRules.createAIInsightPrompt(cycleDayNumber: 5, phase: .menstrual, goal: "Maintain", recentLogs: [log])
        
        XCTAssertTrue(prompt.contains("Day 5 of their cycle"))
        XCTAssertTrue(prompt.contains("menstrual phase"))
        XCTAssertTrue(prompt.contains("Maintain weight"))
        XCTAssertTrue(prompt.contains("Cals: 100, P: 1g, C: 25g, F: 0g"))
    }

    func testParseAIInsightResponseValid() {
        let jsonString = """
        {
            "phaseTitle": "Power Phase",
            "phaseDescription": "You are feeling strong.",
            "trainingFocus": {
                "title": "Heavy Lifting",
                "description": "Lift heavy."
            },
            "hormonalState": "Estrogen rising",
            "energyLevel": "High",
            "nutritionTip": "Eat carbs.",
            "symptomTip": "Rest well."
        }
        """
        
        do {
            let insight = try CycleTrackingRules.parseAIInsightResponse(jsonString)
            XCTAssertEqual(insight.phaseTitle, "Power Phase")
            XCTAssertEqual(insight.energyLevel, "High")
            XCTAssertEqual(insight.trainingFocus.title, "Heavy Lifting")
        } catch {
            XCTFail("Failed to parse valid JSON: \(error)")
        }
    }

    func testParseAIInsightResponseInvalidEncoding() {
        // String that cannot be represented in UTF-8 - though in Swift, a String is always valid. 
        // We can just test invalid JSON.
        let jsonString = """
        {
            "phaseTitle": "Power Phase",
        """
        XCTAssertThrowsError(try CycleTrackingRules.parseAIInsightResponse(jsonString))
    }
}
