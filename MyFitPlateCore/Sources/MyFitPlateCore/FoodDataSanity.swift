import Foundation

/// Physical-plausibility checks for food database entries. Complements
/// `NutritionCalorieConsistency` (the Atwater calorie-vs-macro check) with rules that catch
/// the unit-slip and impossible-data bugs we've seen from external databases: mg-vs-g
/// mineral slips, macro grams exceeding the serving's own weight, energy denser than pure
/// fat, and entries with macros but zero calories. A flagged food gets a warning badge and
/// a one-tap route into the correction editor — turning "bad data" from an anecdote into a
/// measurable, fixable event.
public enum FoodDataSanity {

    public enum Severity: String, Equatable {
        /// Almost certainly wrong data — physically impossible or a classic unit slip.
        case warning
        /// Worth a look, but legitimate foods can trip it (e.g. alcohol's 7 kcal/g
        /// makes calories exceed macro-derived calories).
        case info
    }

    public struct Finding: Equatable, Identifiable {
        /// Stable kind key — used for telemetry params and deduping, never shown to users.
        public let id: String
        public let severity: Severity
        /// Short human-readable explanation shown in the review card.
        public let message: String
    }

    /// Serving weights at or below this are treated as unknown placeholders
    /// (`FoodItem.servingWeight` defaults to 1.0), so weight-based rules stay quiet.
    private static let minimumKnownServingWeight = 10.0

    public static func findings(for item: FoodItem) -> [Finding] {
        var findings: [Finding] = []

        let macroGrams = max(0, item.protein) + max(0, item.carbs) + max(0, item.fats)
        let consistency = item.calorieConsistencyStatus

        // Zero calories with real macros: the macros prove energy is present.
        if item.calories <= 1, macroGrams >= 5 {
            findings.append(Finding(
                id: "macros_without_calories",
                severity: .warning,
                message: "Shows \(Int(item.calories)) calories but has \(Int(macroGrams.rounded()))g of macros."
            ))
        } else if consistency.hasMeaningfulMismatch {
            if consistency.delta > 0 {
                // Macros imply MORE energy than the stated calories — an undercount.
                findings.append(Finding(
                    id: "calories_undercount",
                    severity: .warning,
                    message: "Macros suggest about \(Int(consistency.macroDerivedCalories.rounded())) calories, but this entry says \(Int(consistency.loggedCalories.rounded()))."
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
            let macroAndFiberGrams = macroGrams + max(0, item.fiber ?? 0)
            if macroAndFiberGrams > item.servingWeight * 1.05 {
                findings.append(Finding(
                    id: "macros_exceed_serving_weight",
                    severity: .warning,
                    message: "\(Int(macroAndFiberGrams.rounded()))g of macros can't fit in a \(Int(item.servingWeight.rounded()))g serving."
                ))
            }

            // Pure fat is 9 kcal/g — nothing edible is denser.
            if item.calories > item.servingWeight * 9.5 {
                findings.append(Finding(
                    id: "energy_density_impossible",
                    severity: .warning,
                    message: "\(Int(item.calories.rounded())) calories in \(Int(item.servingWeight.rounded()))g is denser than pure fat."
                ))
            }
        }

        if item.servingWeight > 2500 {
            findings.append(Finding(
                id: "serving_weight_implausible",
                severity: .info,
                message: "A \(Int(item.servingWeight.rounded()))g serving looks unusually large."
            ))
        }

        // Classic g-vs-mg slips: the app stores these minerals in mg. 10g of sodium or
        // potassium in one serving is beyond any real food.
        if let sodium = item.sodium, sodium > 10_000 {
            findings.append(Finding(
                id: "sodium_unit_suspect",
                severity: .warning,
                message: "Sodium of \(Int(sodium.rounded()))mg looks about 1000x too high."
            ))
        }
        if let potassium = item.potassium, potassium > 10_000 {
            findings.append(Finding(
                id: "potassium_unit_suspect",
                severity: .warning,
                message: "Potassium of \(Int(potassium.rounded()))mg looks about 1000x too high."
            ))
        }

        return findings
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
