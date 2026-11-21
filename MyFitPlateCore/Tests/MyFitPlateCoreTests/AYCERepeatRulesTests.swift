import XCTest
@testable import MyFitPlateCore

final class AYCERepeatRulesTests: XCTestCase {
    func testRoundsRepeatOnlyNewAdditionsWithExactFractionsAndRecoverAfterRestart() throws {
        let roll = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        var session = AYCESession(cuisine: .sushi, buffetPrice: 35, entries: [AYCESessionEntry(item: roll, count: 0.375)])
        session = try XCTUnwrap(AYCERepeatRules.finishingRound(session))
        session.entries[0].count = 0.625
        XCTAssertNil(AYCERepeatRules.repeatingLastRound(session), "Review the unfinished round first")
        session = try XCTUnwrap(AYCERepeatRules.finishingRound(session))
        XCTAssertEqual(session.lastRound?.first?.count, 0.25)
        let recovered = try JSONDecoder().decode(AYCESession.self, from: JSONEncoder().encode(session))
        let repeated = try XCTUnwrap(AYCERepeatRules.repeatingLastRound(recovered))
        XCTAssertEqual(repeated.entries[0].count, 0.875)
        XCTAssertEqual(repeated.entries[0].id, session.entries[0].id)
        XCTAssertTrue(AYCERepeatRules.currentRound(repeated).isEmpty)
        XCTAssertEqual(AYCERules.totals(for: repeated).calories, roll.calories * 0.875)
    }
    func testRemovedPortionsAreNotNewRoundsAndOversizedOrFrozenRepeatsAreRejected() throws {
        let food = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        var session = try XCTUnwrap(AYCERepeatRules.finishingRound(AYCESession(cuisine: .sushi, buffetPrice: 35,
                                                        entries: [AYCESessionEntry(item: food, count: 60)])))
        XCTAssertNil(AYCERepeatRules.repeatingLastRound(session))
        session.entries[0].count = 50
        XCTAssertTrue(AYCERepeatRules.currentRound(session).isEmpty)
        session.submittedAt = Date()
        XCTAssertNil(AYCERepeatRules.finishingRound(session))
        XCTAssertNil(AYCERepeatRules.repeatingLastRound(session))
    }
    @MainActor func testFavoritesAndRestaurantCutsAreAccountScopedAndKeepWholeRollNutrition() throws {
        let suite = "buffet-preferences-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let roll = try XCTUnwrap(AYCECatalog.item(id: "sushi_rainbow_roll"))
        let prefs = AYCEPreferences(userID: "a", defaults: defaults)
        prefs.toggleFavorite(roll.id)
        prefs.rememberCut(6, for: roll, restaurant: " My Sushi ")
        let reopened = AYCEPreferences(userID: "a", defaults: defaults)
        XCTAssertTrue(reopened.isFavorite(roll.id))
        let adjusted = reopened.resolve(roll, restaurant: "my sushi")
        XCTAssertEqual(adjusted.piecesPerUnit, 6)
        XCTAssertEqual(adjusted.calories, roll.calories)
        XCTAssertEqual(AYCEPortionRules.quantity(pieces: 3, item: adjusted), 0.5)
        XCTAssertEqual(reopened.resolve(roll, restaurant: "Another place").piecesPerUnit, 8)
        let other = AYCEPreferences(userID: "b", defaults: defaults)
        XCTAssertFalse(other.isFavorite(roll.id))
        XCTAssertEqual(other.resolve(roll, restaurant: "my sushi").piecesPerUnit, 8)
        prefs.toggleFavorite(roll.id)
        XCTAssertFalse(reopened.isFavorite(roll.id))
    }
    func testKBBQEqualShareRejectsInvalidInputAndPreservesPersonalAmount() throws {
        let meat = try XCTUnwrap(AYCECatalog.all.first { $0.cuisine == .kbbq && $0.cookedGramsPerUnit != nil })
        let whole = try XCTUnwrap(AYCEPortionRules.quantity(cookedGrams: 300, item: meat))
        let share = try XCTUnwrap(AYCEPortionRules.personalShare(quantity: whole, diners: 3))
        XCTAssertEqual(share * (meat.cookedGramsPerUnit ?? 0), 100, accuracy: 0.00001)
        for count in [0, -1, 21] { XCTAssertNil(AYCEPortionRules.personalShare(quantity: whole, diners: count)) }
        XCTAssertNil(AYCEPortionRules.personalShare(quantity: .nan, diners: 3))
    }
}
