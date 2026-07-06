import XCTest
@testable import MyFitPlateCore

final class MFPImportTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: Food-level export shape

    func testFoodLevelExportBuildsRealDiaryLines() throws {
        let csv = """
        Date,Meal,Food,Calories,Protein (g),Carbohydrates (g),Fat (g),Fiber (g),Sodium (mg)
        2025-11-03,Breakfast,"Oatmeal, rolled oats",300,10,54,5,8,10
        2025-11-03,Breakfast,Black coffee,5,0,1,0,0,5
        2025-11-03,Lunch,"Chicken breast, grilled",280,52,0,6,0,120
        2025-11-04,Dinner,Salmon fillet,410,40,0,26,0,90
        """

        let parsed = try MFPImport.parseDiary(csv: csv, calendar: calendar)

        XCTAssertEqual(parsed.dailyLogs.count, 2)
        XCTAssertEqual(parsed.totalFoodEntries, 4)
        XCTAssertEqual(parsed.skippedRows, 0)

        let day1 = parsed.dailyLogs[0]
        XCTAssertEqual(day1.meals.map(\.name), ["Breakfast", "Lunch"])
        XCTAssertEqual(day1.meals[0].foodItems.map(\.name), ["Oatmeal, rolled oats", "Black coffee"],
                       "Quoted commas in food names survive")
        XCTAssertEqual(day1.totalCalories(), 585, accuracy: 0.001)
        XCTAssertEqual(day1.meals[1].foodItems[0].protein, 52, accuracy: 0.001)
        XCTAssertEqual(day1.meals[1].foodItems[0].sodium ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(day1.meals[0].foodItems[0].sourceMetadata?.sourceName, "MyFitnessPal")
    }

    // MARK: Aggregate export shape (GDPR dump, no food column)

    func testAggregateExportBuildsSyntheticPerMealEntries() throws {
        let csv = """
        Date,Meal,Calories,Protein (g),Carbohydrates (g),Fat (g)
        11/03/2025,Breakfast,450,25,60,12
        11/03/2025,Dinner,900,55,80,35
        """

        let parsed = try MFPImport.parseDiary(csv: csv, calendar: calendar)

        XCTAssertEqual(parsed.dailyLogs.count, 1)
        XCTAssertEqual(parsed.totalFoodEntries, 2)
        let log = parsed.dailyLogs[0]
        XCTAssertEqual(log.meals[0].foodItems[0].name, "MyFitnessPal import — Breakfast")
        XCTAssertEqual(log.totalCalories(), 1350, accuracy: 0.001)
        XCTAssertEqual(log.totalMacros().protein, 80, accuracy: 0.001)
    }

    // MARK: Robustness

    func testMalformedRowsAreSkippedAndCountedNeverFatal() throws {
        let csv = """
        Date,Meal,Food,Calories
        2025-11-03,Lunch,Sandwich,520
        not-a-date,Lunch,Ghost row,100
        2025-11-04,Dinner,No calories row,not-a-number
        2025-11-05,Snacks,Apple,95
        """

        let parsed = try MFPImport.parseDiary(csv: csv, calendar: calendar)
        XCTAssertEqual(parsed.totalFoodEntries, 2)
        XCTAssertEqual(parsed.skippedRows, 2)
    }

    func testMissingRequiredColumnsThrowsAReadableError() {
        XCTAssertThrowsError(try MFPImport.parseDiary(csv: "Meal,Food,Calories\nLunch,Sandwich,520")) { error in
            XCTAssertEqual(error as? MFPImport.ImportError, .missingRequiredColumns("a Date column"))
        }
        XCTAssertThrowsError(try MFPImport.parseDiary(csv: "")) { error in
            XCTAssertEqual(error as? MFPImport.ImportError, .emptyFile)
        }
    }

    func testThousandsSeparatorsAndPlaceholdersParse() throws {
        let csv = """
        Date,Meal,Food,Calories,Protein (g)
        2025-11-03,Dinner,Feast platter,"1,240",--
        """
        let parsed = try MFPImport.parseDiary(csv: csv, calendar: calendar)
        let item = parsed.dailyLogs[0].meals[0].foodItems[0]
        XCTAssertEqual(item.calories, 1240, accuracy: 0.001)
        XCTAssertEqual(item.protein, 0, accuracy: 0.001, "MFP's '--' placeholder reads as zero, not a crash")
    }

    // MARK: Weight measurements

    func testWeightParsingHandlesPoundsKilogramsAndJunk() {
        let lbs = MFPImport.parseMeasurements(csv: """
        Date,Weight (lbs)
        2025-10-01,201.4
        2025-10-08,199.0
        2025-10-08,198.5
        2025-10-15,0
        """, calendar: calendar)
        XCTAssertEqual(lbs.count, 2, "Duplicate days keep the first entry; zero weights are junk")
        XCTAssertEqual(lbs[0].weightLbs, 201.4, accuracy: 0.001)

        let kg = MFPImport.parseMeasurements(csv: """
        Date,Weight (kg)
        2025-10-01,91.2
        """, calendar: calendar)
        XCTAssertEqual(kg[0].weightLbs, 91.2 / 0.45359237, accuracy: 0.01, "Kilograms convert to internal pounds")

        XCTAssertTrue(MFPImport.parseMeasurements(csv: "nothing useful", calendar: calendar).isEmpty)
    }

    // MARK: Merge policy

    func testMergePlanNeverTouchesDaysTheUserAlreadyLogged() throws {
        let csv = """
        Date,Meal,Food,Calories
        2025-11-03,Lunch,Sandwich,520
        2025-11-04,Lunch,Salad,340
        2025-11-05,Lunch,Soup,290
        """
        let parsed = try MFPImport.parseDiary(csv: csv, calendar: calendar)

        let existingDay = calendar.startOfDay(for: MFPImport.parseDate("2025-11-04", calendar: calendar)!)
        let plan = MFPImport.mergePlan(imported: parsed.dailyLogs, existingLoggedDays: [existingDay], calendar: calendar)

        XCTAssertEqual(plan.toImport.count, 2)
        XCTAssertEqual(plan.skippedConflicts, 1)
        XCTAssertFalse(plan.toImport.contains { calendar.isDate($0.date, inSameDayAs: existingDay) },
                       "The user's own logged day always wins over an import")
    }
}
