import Foundation

/// Physical-plausibility checks for food database entries. Complements
/// `NutritionCalorieConsistency` (the Atwater calorie-vs-macro check) with rules that catch
/// the unit-slip and impossible-data bugs we've seen from external databases: mg-vs-g
/// mineral slips, macro grams exceeding the serving's own weight, energy denser than pure
/// fat, and entries with macros but zero calories. A flagged food gets a warning badge and
/// a one-tap route into the correction editor — turning "bad data" from an anecdote into a
/// measurable, fixable event.
public enum FoodDataSanity {

    public enum Severity: String, Equatable, Sendable {
        /// Almost certainly wrong data — physically impossible or a classic unit slip.
        case warning
        /// Worth a look, but legitimate foods can trip it (e.g. alcohol's 7 kcal/g
        /// makes calories exceed macro-derived calories).
        case info
    }

    public struct Finding: Equatable, Identifiable, Sendable {
        /// Stable kind key — used for telemetry params and deduping, never shown to users.
        public let id: String
        public let severity: Severity
        /// Short human-readable explanation shown in the review card.
        public let message: String
    }

    /// Serving weights at or below this are treated as unknown placeholders
    /// (`FoodItem.servingWeight` defaults to 1.0), so weight-based rules stay quiet.
    private static let minimumKnownServingWeight = 10.0
    private static let minimumCalorieVariance = 20.0

    public static func findings(for item: FoodItem) -> [Finding] {
        var findings: [Finding] = []

        let coreValues = [item.calories, item.protein, item.carbs, item.fats, item.servingWeight]
        let optionalValues = [
            item.saturatedFat, item.polyunsaturatedFat, item.monounsaturatedFat, item.fiber,
            item.calcium, item.iron, item.potassium, item.sodium, item.vitaminA, item.vitaminC,
            item.vitaminD, item.vitaminB12, item.folate, item.magnesium, item.phosphorus,
            item.zinc, item.copper, item.manganese, item.selenium, item.vitaminB1,
            item.vitaminB2, item.vitaminB3, item.vitaminB5, item.vitaminB6, item.vitaminE,
            item.vitaminK
        ].compactMap { $0 }

        guard coreValues.allSatisfy(\.isFinite), optionalValues.allSatisfy(\.isFinite) else {
            return [Finding(
                id: "nutrition_value_invalid",
                severity: .warning,
                message: "One or more nutrition values are not valid numbers."
            )]
        }

        if coreValues.contains(where: { $0 < 0 }) || optionalValues.contains(where: { $0 < 0 }) {
            findings.append(Finding(
                id: "nutrition_value_negative",
                severity: .warning,
                message: "Calories, serving weight, and nutrient amounts cannot be negative."
            ))
        }

        let hasUnsupportedMagnitude = item.calories > 1_000_000 ||
            [item.protein, item.carbs, item.fats].contains(where: { $0 > 100_000 }) ||
            item.servingWeight > 100_000_000 ||
            optionalValues.contains(where: { $0 > 1_000_000_000 })
        guard !hasUnsupportedMagnitude else {
            findings.append(Finding(
                id: "nutrition_value_out_of_range",
                severity: .warning,
                message: "One or more nutrition values are outside a usable range."
            ))
            return findings
        }

        let calories = max(0, item.calories)
        let protein = max(0, item.protein)
        let carbs = max(0, item.carbs)
        let fats = max(0, item.fats)
        let fiber = max(0, item.fiber ?? 0)
        let macroGrams = protein + carbs + fats
        let consistency = NutritionCalorieConsistency.status(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            fiber: fiber
        )
        let caloriesFromProteinAndFat = protein * 4 + fats * 9

        // Carbohydrate can include lower-calorie fiber, allulose, and sugar alcohols. Protein
        // and fat provide a safer floor for identifying a true calorie undercount.
        if calories <= 1, caloriesFromProteinAndFat >= minimumCalorieVariance {
            findings.append(Finding(
                id: "macros_without_calories",
                severity: .warning,
                message: "Shows \(wholeNumber(calories)) calories, but protein and fat alone provide about \(wholeNumber(caloriesFromProteinAndFat))."
            ))
        } else if caloriesFromProteinAndFat - calories >= minimumCalorieVariance,
                  calories < caloriesFromProteinAndFat * 0.8 {
            findings.append(Finding(
                id: "calories_undercount",
                severity: .warning,
                message: "Protein and fat alone suggest about \(wholeNumber(caloriesFromProteinAndFat)) calories, but this entry says \(wholeNumber(calories))."
            ))
        } else if consistency.hasMeaningfulMismatch,
                  consistency.mismatchAmount >= minimumCalorieVariance {
            if consistency.delta > 0 {
                // This can be legitimate when carbohydrate includes fiber, allulose, or sugar
                // alcohols, so it deserves review rather than a claim that the label is wrong.
                findings.append(Finding(
                    id: "calories_below_macro_estimate",
                    severity: .info,
                    message: "Standard macro math suggests about \(wholeNumber(consistency.macroDerivedCalories)) calories. Fiber, sugar alcohols, or label rounding may explain the difference."
                ))
            } else if consistency.loggedCalories >= 80,
                      consistency.loggedCalories > consistency.macroDerivedCalories * 2.2 {
                // Calories far above macro-derived can be legitimate (alcohol at 7 kcal/g),
                // so this is informational rather than a defect claim.
                findings.append(Finding(
                    id: "calories_exceed_macros",
                    severity: .info,
                    message: "Calories are much higher than the macros explain — could be alcohol, or incomplete macro data."
                ))
            }
        }

        if item.servingWeight >= minimumKnownServingWeight {
            // Dietary fiber is PART of total carbs, not an extra mass — adding it here
            // double-counted it and falsely flagged high-fiber foods (a 32g-carb / 26g-fiber
            // tortilla read as 74g of macros instead of 48g).
            if macroGrams > item.servingWeight * 1.05 {
                findings.append(Finding(
                    id: "macros_exceed_serving_weight",
                    severity: .warning,
                    message: "\(wholeNumber(macroGrams))g of macros can't fit in a \(wholeNumber(item.servingWeight))g serving."
                ))
            }

            // Pure fat is 9 kcal/g — nothing edible is denser.
            if calories > item.servingWeight * 9.5 {
                findings.append(Finding(
                    id: "energy_density_impossible",
                    severity: .warning,
                    message: "\(wholeNumber(calories)) calories in \(wholeNumber(item.servingWeight))g is denser than pure fat."
                ))
            }
        }

        if let saturatedFat = item.saturatedFat,
           saturatedFat > fats + max(1, fats * 0.10) {
            findings.append(Finding(
                id: "saturated_fat_exceeds_total",
                severity: .warning,
                message: "Saturated fat cannot be greater than total fat."
            ))
        }

        if fiber > carbs + max(1, carbs * 0.10) {
            findings.append(Finding(
                id: "fiber_exceeds_carbs",
                severity: .info,
                message: "Fiber is higher than total carbs. Confirm how this label reports carbohydrate."
            ))
        }

        if item.servingWeight > 2500 {
            findings.append(Finding(
                id: "serving_weight_implausible",
                severity: .info,
                message: "A \(wholeNumber(item.servingWeight))g serving looks unusually large."
            ))
        }

        // Classic g-vs-mg slips. Very large recipes can legitimately exceed 10,000mg, so
        // concentration decides whether the value is a hard warning or a softer review item.
        if let sodiumFinding = mineralFinding(
            value: item.sodium,
            name: "Sodium",
            warningID: "sodium_unit_suspect",
            infoID: "sodium_high_for_entry",
            servingWeight: item.servingWeight
        ) {
            findings.append(sodiumFinding)
        }
        if let potassiumFinding = mineralFinding(
            value: item.potassium,
            name: "Potassium",
            warningID: "potassium_unit_suspect",
            infoID: "potassium_high_for_entry",
            servingWeight: item.servingWeight
        ) {
            findings.append(potassiumFinding)
        }

        return findings
    }

    private static func mineralFinding(
        value: Double?,
        name: String,
        warningID: String,
        infoID: String,
        servingWeight: Double
    ) -> Finding? {
        guard let value, value > 10_000 else { return nil }
        let hasKnownWeight = servingWeight >= minimumKnownServingWeight
        let concentration = hasKnownWeight ? value / servingWeight : 0

        if hasKnownWeight, concentration > 100 {
            return Finding(
                id: warningID,
                severity: .warning,
                message: "\(name) of \(wholeNumber(value))mg looks like a unit error for this serving."
            )
        }
        return Finding(
            id: infoID,
            severity: .info,
            message: "\(name) of \(wholeNumber(value))mg is unusually high. Confirm the serving and units."
        )
    }

    private static func wholeNumber(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return String(format: "%.2g", value)
        }
        return String(Int(value.rounded()))
    }

    /// True when the entry has at least one `.warning` finding — drives the row badge and
    /// the `food_data_suspicious` telemetry. `.info` findings surface only in the detail card.
    public static func isSuspicious(_ item: FoodItem) -> Bool {
        findings(for: item).contains { $0.severity == .warning }
    }

    /// Comma-joined finding ids for analytics params (e.g. "calories_undercount,sodium_unit_suspect").
    public static func telemetryKinds(for item: FoodItem) -> String {
        findings(for: item).map(\.id).joined(separator: ",")
    }
}
