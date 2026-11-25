import XCTest
@testable import MyFitPlateCore

@MainActor
final class FoodServingPreferencesTests: XCTestCase {
    func testRememberedServingIsHydratedScopedAndResettable() throws {
        let suite = "servings-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FoodServingPreferences(defaults: defaults)
        let base = FoodItem(id: "provider", name: "Rice", calories: 200, servingSize: "1 cup", servingWeight: 100)
            .withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "rice")
        var portion = base
        portion.calories = 300
        portion.servingWeight = 150
        portion.servingSize = "1.5 cups"
        preferences.remember(portion, userID: "a")
        let recalled = FoodServingPreferences(defaults: defaults).preferred(base, userID: "a")
        XCTAssertEqual(recalled.calories, 300)
        XCTAssertEqual(recalled.servingSize, "1.5 cups")
        XCTAssertTrue(recalled.id.hasPrefix("preferred_"))
        XCTAssertEqual(preferences.preferred(base, userID: "b").calories, 200)
        var invalid = portion; invalid.calories = .nan
        preferences.remember(invalid, userID: "a")
        XCTAssertEqual(preferences.preferred(base, userID: "a").calories, 300)
        preferences.clear(userID: "a")
        XCTAssertEqual(preferences.preferred(base, userID: "a").calories, 200)
    }
    func testProviderIdentitiesDoNotBorrowOneAnothersServings() throws {
        let suite = "servings-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FoodServingPreferences(defaults: defaults)
        let first = FoodItem(name: "Rice", calories: 400).withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "a")
        let second = FoodItem(name: "Rice", calories: 200).withDatabaseSource(.fatSecret, sourceName: "FatSecret", sourceID: "b")
        preferences.remember(first, userID: "a")
        XCTAssertEqual(preferences.preferred(second, userID: "a").calories, 200)
    }

    func testChangedVersionScoopWeightDensityAndSourceCannotReuseOldPortion() throws {
        let suite = "servings-version-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FoodServingPreferences(defaults: defaults)
        var base = FoodItem(id: "provider", name: "Protein powder", calories: 120, protein: 24, carbs: 3, fats: 1,
            servingSize: "1 scoop", servingWeight: 30)
            .withDatabaseSource(.openFoodFacts, sourceName: "OFF", sourceID: "product")
        base.sourceMetadata?.barcode = "012345678905"
        base.sourceMetadata?.sourceUpdatedAt = Date(timeIntervalSince1970: 100)
        var portion = base.scalingNutritionAndServing(by: 2)
        portion.servingSize = "2 scoops"; portion.quantityValue = 2; portion.servingUnit = "scoop"
        preferences.remember(portion, userID: "a")
        XCTAssertEqual(preferences.preferred(base, userID: "a").calories, 240)
        var changed = base; changed.sourceMetadata?.sourceUpdatedAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(preferences.preferred(changed, userID: "a"), changed)
        changed = base; changed.servingWeight = 35
        XCTAssertEqual(preferences.preferred(changed, userID: "a"), changed)
        changed = base; changed.calories = 150; changed.protein = 20
        XCTAssertEqual(preferences.preferred(changed, userID: "a"), changed)
        changed = base; changed.sourceMetadata?.sourceID = "different-record"
        XCTAssertEqual(preferences.preferred(changed, userID: "a"), changed)
        changed = base; changed.servingSize = "1 cup"
        XCTAssertEqual(preferences.preferred(changed, userID: "a"), changed)
        XCTAssertEqual(preferences.preferred(base, userID: "a").calories, 240, "Rejecting an incompatible current record must retain the original preference")
    }

    func testNaturalFractionalAndExplicitMultiplierMeasuresRemainCompatible() throws {
        let suite = "servings-fractions-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FoodServingPreferences(defaults: defaults)
        let base = FoodItem(id: "powder", name: "Protein powder", calories: 120, servingSize: "1 scoop", servingWeight: 30)
            .withDatabaseSource(.openFoodFacts, sourceName: "OFF", sourceID: "powder")
        for (label, scale) in [("1 1/2 scoops", 1.5), ("2 x scoop", 2.0), ("1/2 scoop", 0.5)] {
            var portion = base.scalingNutritionAndServing(by: scale)
            portion.servingSize = label
            preferences.remember(portion, userID: "a")
            XCTAssertEqual(preferences.preferred(base, userID: "a").calories, 120 * scale, label)
        }
        var malformed = base; malformed.servingSize = "1/0 scoop"
        XCTAssertEqual(preferences.preferred(malformed, userID: "a").servingSize, malformed.servingSize)
    }
}
