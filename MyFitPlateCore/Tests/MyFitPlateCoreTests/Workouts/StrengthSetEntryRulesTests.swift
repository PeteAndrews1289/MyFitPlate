import XCTest
@testable import MyFitPlateCore

final class StrengthSetEntryRulesTests: XCTestCase {
    func testBodyweightAndDecimalWeightsAreValidWithoutGuessingMalformedValues() {
        XCTAssertEqual(StrengthSetEntryRules.weight(from: "0"), 0)
        XCTAssertEqual(StrengthSetEntryRules.weight(from: "12,5", locale: Locale(identifier: "fr_FR")), 12.5)
        XCTAssertEqual(StrengthSetEntryRules.weight(from: " 135.5 ", locale: Locale(identifier: "en_US")), 135.5)
        for invalid in ["", "-5", "NaN", "inf", "12..5", "12kg", "1,000"] {
            XCTAssertNil(StrengthSetEntryRules.weight(from: invalid, locale: Locale(identifier: "en_US")))
        }
        XCTAssertEqual(StrengthSetEntryRules.reps(from: "12"), 12)
        for invalid in ["", "0", "-3", "8.5", "8 reps"] { XCTAssertNil(StrengthSetEntryRules.reps(from: invalid)) }
    }

    func testAnExplicitClearCannotCompleteWithTheLastKnownLoadOrRepCount() throws {
        // A person erased the weight while the draft still contains 135 lb × 8.
        // The editor must omit its fallback for that edited field.
        XCTAssertThrowsError(try StrengthSetEntryRules.review(weightInput: "", repsInput: "8")) {
            XCTAssertEqual($0 as? StrengthSetEntryRules.EntryError, .weight)
        }
        XCTAssertThrowsError(try StrengthSetEntryRules.review(weightInput: "135", repsInput: "  ")) {
            XCTAssertEqual($0 as? StrengthSetEntryRules.EntryError, .reps)
        }
        // An explicit zero is different from a cleared field and remains valid.
        let bodyweight = try StrengthSetEntryRules.review(weightInput: "0", repsInput: "8")
        XCTAssertEqual(bodyweight.displayedWeight, 0)
        XCTAssertEqual(bodyweight.reps, 8)
    }

    func testUntouchedUnseededRowsCanUseVisibleHistoryAndTargetDefaults() throws {
        let previous = try StrengthSetEntryRules.review(weightInput: "", repsInput: "",
                                                      fallbackWeight: "135", fallbackReps: 8)
        XCTAssertEqual(previous.displayedWeight, 135)
        XCTAssertEqual(previous.reps, 8)
        let bodyweight = try StrengthSetEntryRules.review(weightInput: "", repsInput: "",
                                                        fallbackWeight: "0", fallbackReps: 12)
        XCTAssertEqual(bodyweight.displayedWeight, 0)
        XCTAssertEqual(bodyweight.reps, 12)
    }

    func testInvalidTypedValuesAreNotReplacedByFallbacksAndReportTheRightField() {
        for invalidWeight in [".", "12..5", "-2", "NaN"] {
            XCTAssertThrowsError(try StrengthSetEntryRules.review(weightInput: invalidWeight, repsInput: "8",
                fallbackWeight: "135", fallbackReps: 8)) {
                XCTAssertEqual($0 as? StrengthSetEntryRules.EntryError, .weight)
            }
        }
        for invalidReps in ["0", "2.5", "-1"] {
            XCTAssertThrowsError(try StrengthSetEntryRules.review(weightInput: "135", repsInput: invalidReps,
                fallbackWeight: "135", fallbackReps: 8)) {
                XCTAssertEqual($0 as? StrengthSetEntryRules.EntryError, .reps)
            }
        }
    }

    func testReviewPreservesMetricDisplayTextForExactStoredQuantityComparison() throws {
        let entry = try StrengthSetEntryRules.review(weightInput: "61,235", repsInput: "9",
                                                    locale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(entry.weightText, "61,235")
        XCTAssertEqual(entry.displayedWeight, 61.235, accuracy: 0.000001)
        XCTAssertEqual(entry.reps, 9)
    }

    func testLateHistoryCannotRepopulateAnExplicitlyClearedOrFocusedField() {
        XCTAssertFalse(StrengthSetEntryRules.canSeedFromHistory(input: "", wasEdited: true, isFocused: true))
        XCTAssertFalse(StrengthSetEntryRules.canSeedFromHistory(input: "", wasEdited: true, isFocused: false),
                       "Leaving the field must not give late history permission to erase the person's clear")
        XCTAssertFalse(StrengthSetEntryRules.canSeedFromHistory(input: "", wasEdited: false, isFocused: true),
                       "History must not insert digits underneath an active keyboard")
        XCTAssertFalse(StrengthSetEntryRules.canSeedFromHistory(input: "0", wasEdited: false, isFocused: false),
                       "An explicit bodyweight value is already populated")
        XCTAssertFalse(StrengthSetEntryRules.canSeedFromHistory(input: ".", wasEdited: true, isFocused: false))
        XCTAssertTrue(StrengthSetEntryRules.canSeedFromHistory(input: "", wasEdited: false, isFocused: false))
    }
}
