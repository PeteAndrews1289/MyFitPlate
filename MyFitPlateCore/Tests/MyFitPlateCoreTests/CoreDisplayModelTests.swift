import SwiftUI
import XCTest
@testable import MyFitPlateCore

final class CoreDisplayModelTests: XCTestCase {
    func testFoodEmojiMapperUsesExactContainsFirstWordAndFallbackMatches() {
        XCTAssertEqual(FoodEmojiMapper.getEmoji(for: "pizza"), "🍕")
        XCTAssertEqual(FoodEmojiMapper.getEmoji(for: "roasted chicken breast"), "🍗")
        XCTAssertEqual(FoodEmojiMapper.getEmoji(for: "banana smoothie"), "🍌")
        XCTAssertEqual(FoodEmojiMapper.getEmoji(for: "unknown food"), "🍽️")
    }

    func testExerciseEmojiMapperUsesExactContainsAndFallbackMatches() {
        XCTAssertEqual(ExerciseEmojiMapper.getEmoji(for: "running"), "🏃")
        XCTAssertEqual(ExerciseEmojiMapper.getEmoji(for: "evening strength training session"), "🏋️")
        XCTAssertEqual(ExerciseEmojiMapper.getEmoji(for: "pickleball"), "🤸")
    }

    func testJournalAndTimeframeDisplayNamesAreStable() {
        XCTAssertEqual(JournalEmojiMapper.getEmoji(for: "Recovery"), "🧊")
        XCTAssertEqual(JournalEmojiMapper.getEmoji(for: "Mindfulness"), "🧘")
        XCTAssertEqual(JournalEmojiMapper.getEmoji(for: "Other"), "📝")
        XCTAssertEqual(JournalEmojiMapper.getEmoji(for: "Anything Else"), "📝")

        XCTAssertEqual(ReportTimeframe.week.id, "Last 7 Days")
        XCTAssertEqual(ReportTimeframe.month.id, "Last 30 Days")
        XCTAssertEqual(ReportTimeframe.custom.id, "Custom Range")

        XCTAssertEqual(WeightChartTimeframe.week.displayName, "Last 7 Days")
        XCTAssertEqual(WeightChartTimeframe.threeMonths.displayName, "Last 3 Months")
        XCTAssertEqual(WeightChartTimeframe.allTime.displayName, "All Time")
    }

    func testUserInsightDecodingDefaultsUnknownOrMissingOptionalFields() throws {
        let unknownCategory = try JSONDecoder().decode(UserInsight.self, from: Data("""
        {
            "title": "Protein trend",
            "message": "You are averaging more protein this week.",
            "category": "brandNewCategory"
        }
        """.utf8))

        XCTAssertEqual(unknownCategory.title, "Protein trend")
        XCTAssertEqual(unknownCategory.category, .nutritionGeneral)
        XCTAssertEqual(unknownCategory.priority, 0)
        XCTAssertNil(unknownCategory.sourceData)

        let completeInsight = try JSONDecoder().decode(UserInsight.self, from: Data("""
        {
            "title": "Hydration",
            "message": "Water intake is steady.",
            "category": "hydration",
            "priority": 4,
            "sourceData": "dailyLogs"
        }
        """.utf8))

        XCTAssertEqual(completeInsight.category, .hydration)
        XCTAssertEqual(completeInsight.priority, 4)
        XCTAssertEqual(completeInsight.sourceData, "dailyLogs")
    }

    func testReportAndMealValueModelsPreserveIdentityAndMetrics() throws {
        let report = ReportSummary(
            timeframe: "Last 7 Days",
            averageCalories: 2_100,
            averageProtein: 160,
            averageCarbs: 240,
            averageFats: 70,
            daysLogged: 7
        )
        XCTAssertEqual(report.timeframe, "Last 7 Days")
        XCTAssertEqual(report.daysLogged, 7)

        let date = Date(timeIntervalSince1970: 456)
        let point = DateValuePoint(date: date, value: 123)
        XCTAssertEqual(point, point)
        XCTAssertNotEqual(point, DateValuePoint(date: date, value: 123))
        XCTAssertEqual(point.date, date)
        XCTAssertEqual(point.value, 123, accuracy: 0.001)

        let distribution = MealDistributionDataPoint(mealName: "Lunch", totalCalories: 850)
        XCTAssertEqual(distribution.mealName, "Lunch")
        XCTAssertEqual(distribution.totalCalories, 850, accuracy: 0.001)

        let suggestionID = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        let suggestion = MealSuggestion(
            id: suggestionID,
            title: "Turkey Bowl",
            calories: 520,
            mealName: "Lunch",
            protein: 45,
            carbs: 55,
            fats: 14,
            ingredients: ["Turkey", "Rice"],
            instructions: "Assemble and serve."
        )
        let encoded = try JSONEncoder().encode(suggestion)
        let decoded = try JSONDecoder().decode(MealSuggestion.self, from: encoded)

        XCTAssertEqual(decoded.id, suggestionID)
        XCTAssertEqual(decoded.ingredients, ["Turkey", "Rice"])
        XCTAssertEqual(decoded.instructions, "Assemble and serve.")
    }

    func testBannerAndRouteValueSemantics() {
        let defaultBanner = BannerData(title: "Saved", message: "Meal logged.")
        XCTAssertEqual(defaultBanner.title, "Saved")
        XCTAssertEqual(defaultBanner.iconName, "checkmark.circle.fill")

        let customBanner = BannerData(
            title: "Heads up",
            message: "Scanner is temporarily unavailable.",
            iconName: "exclamationmark.triangle.fill",
            iconColor: .orange
        )
        XCTAssertNotEqual(defaultBanner, customBanner)

        let routes: Set<Route> = [.home, .nutrition, .settings, .home]
        XCTAssertEqual(routes.count, 3)
        XCTAssertTrue(routes.contains(.nutrition))
    }
}
