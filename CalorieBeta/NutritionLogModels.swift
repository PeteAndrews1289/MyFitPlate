import Foundation

enum NutritionCalorieConsistency {
    static let absoluteMismatchThreshold = 75.0
    static let relativeMismatchThreshold = 0.12

    struct Status: Equatable {
        let loggedCalories: Double
        let macroDerivedCalories: Double
        let delta: Double
        let relativeDelta: Double
        let hasMeaningfulMismatch: Bool

        var mismatchAmount: Double {
            abs(delta)
        }

        var directionText: String {
            delta > 0 ? "higher" : "lower"
        }
    }

    static func macroDerivedCalories(protein: Double, carbs: Double, fats: Double) -> Double {
        max(0, protein) * 4 + max(0, carbs) * 4 + max(0, fats) * 9
    }

    static func status(calories: Double, protein: Double, carbs: Double, fats: Double) -> Status {
        let loggedCalories = max(0, calories)
        let macroCalories = macroDerivedCalories(protein: protein, carbs: carbs, fats: fats)
        let delta = macroCalories - loggedCalories
        let denominator = max(max(loggedCalories, macroCalories), 1)
        let relativeDelta = abs(delta) / denominator
        let hasMeaningfulMismatch = abs(delta) >= absoluteMismatchThreshold || relativeDelta >= relativeMismatchThreshold

        return Status(
            loggedCalories: loggedCalories,
            macroDerivedCalories: macroCalories,
            delta: delta,
            relativeDelta: relativeDelta,
            hasMeaningfulMismatch: hasMeaningfulMismatch
        )
    }

    static func normalizedCaloriesForEstimatedSource(calories: Double, protein: Double, carbs: Double, fats: Double, source: String) -> Double {
        guard isEstimatedSource(source) else { return calories }

        let consistency = status(calories: calories, protein: protein, carbs: carbs, fats: fats)
        guard consistency.macroDerivedCalories > 0 else { return max(0, calories) }

        if calories <= 0 {
            return consistency.macroDerivedCalories
        }

        if consistency.hasMeaningfulMismatch && consistency.delta > 0 {
            return consistency.macroDerivedCalories
        }

        return calories
    }

    static func isEstimatedSource(_ source: String) -> Bool {
        let normalizedSource = source.lowercased()
        return normalizedSource.contains("ai") || normalizedSource.contains("manual")
    }
}

#if DEBUG
enum NutritionConsistencySelfCheck {
    static func run() {
        let macroCalories = NutritionCalorieConsistency.macroDerivedCalories(protein: 10, carbs: 20, fats: 5)
        precondition(abs(macroCalories - 165) < 0.001, "Macro calorie formula regressed.")

        let missingEstimateCalories = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: 0,
            protein: 10,
            carbs: 20,
            fats: 5,
            source: "ai_chat"
        )
        precondition(abs(missingEstimateCalories - 165) < 0.001, "Estimated foods with missing calories should use macro-derived calories.")

        let databaseCalories = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: 120,
            protein: 10,
            carbs: 20,
            fats: 5,
            source: "fatsecret"
        )
        precondition(abs(databaseCalories - 120) < 0.001, "Database food calories should remain authoritative.")

        let meaningfulMismatch = NutritionCalorieConsistency.status(calories: 100, protein: 20, carbs: 20, fats: 20)
        precondition(meaningfulMismatch.hasMeaningfulMismatch, "Large calorie and macro mismatches should be flagged.")

        AppLog.data.info("Nutrition consistency self-check passed.")
    }
}
#endif

struct FoodItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fats: Double
    var saturatedFat: Double?
    var polyunsaturatedFat: Double?
    var monounsaturatedFat: Double?
    var fiber: Double?
    var servingSize: String
    var servingWeight: Double
    var timestamp: Date?

    // Micros
    var calcium: Double?
    var iron: Double?
    var potassium: Double?
    var sodium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var vitaminB12: Double?
    var folate: Double?
    var magnesium: Double?
    var phosphorus: Double?
    var zinc: Double?
    var copper: Double?
    var manganese: Double?
    var selenium: Double?
    var vitaminB1: Double?
    var vitaminB2: Double?
    var vitaminB3: Double?
    var vitaminB5: Double?
    var vitaminB6: Double?
    var vitaminE: Double?
    var vitaminK: Double?

    var quantityValue: Double? = nil
    var servingUnit: String? = nil

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool { lhs.id == rhs.id }

    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fats, saturatedFat, polyunsaturatedFat, monounsaturatedFat, fiber, servingSize, servingWeight, timestamp, calcium, iron, potassium, sodium, vitaminA, vitaminC, vitaminD, vitaminB12, folate, magnesium, phosphorus, zinc, copper, manganese, selenium, vitaminB1, vitaminB2, vitaminB3, vitaminB5, vitaminB6, vitaminE, vitaminK
        case quantityValue, servingUnit
    }
}

extension FoodItem {
    var macroDerivedCalories: Double {
        NutritionCalorieConsistency.macroDerivedCalories(protein: protein, carbs: carbs, fats: fats)
    }

    var calorieConsistencyStatus: NutritionCalorieConsistency.Status {
        NutritionCalorieConsistency.status(calories: calories, protein: protein, carbs: carbs, fats: fats)
    }

    var hasMeaningfulCalorieMacroMismatch: Bool {
        calorieConsistencyStatus.hasMeaningfulMismatch
    }

    func normalizedForEstimatedSource(_ source: String) -> FoodItem {
        var item = self
        item.calories = NutritionCalorieConsistency.normalizedCaloriesForEstimatedSource(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            source: source
        )
        return item
    }
}

struct Meal: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var foodItems: [FoodItem]
    static func == (lhs: Meal, rhs: Meal) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.foodItems == rhs.foodItems }
}

struct WaterTracker: Codable, Equatable {
    var totalOunces: Double
    var goalOunces: Double
    var date: Date
    init(totalOunces: Double, goalOunces: Double = 64.0, date: Date) { self.totalOunces = totalOunces; self.goalOunces = goalOunces; self.date = date }
}

struct LoggedExercise: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var durationMinutes: Int?
    var caloriesBurned: Double
    var date: Date
    var source: String = "manual"
    var workoutID: String?
    var sessionID: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LoggedExercise, rhs: LoggedExercise) -> Bool { lhs.id == rhs.id }
}

struct DailyLog: Codable, Identifiable, Equatable {
    var id: String?
    var date: Date
    var meals: [Meal]
    var totalCaloriesOverride: Double?
    var waterTracker: WaterTracker?
    var exercises: [LoggedExercise]?
    var journalEntries: [JournalEntry]?

    init(id: String? = nil, date: Date, meals: [Meal], totalCaloriesOverride: Double? = nil, waterTracker: WaterTracker? = nil, exercises: [LoggedExercise]? = nil, journalEntries: [JournalEntry]? = nil) {
        self.id = id
        self.date = date
        self.meals = meals
        self.totalCaloriesOverride = totalCaloriesOverride
        self.waterTracker = waterTracker
        self.exercises = exercises
        self.journalEntries = journalEntries
    }

    func totalCalories() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.calories } }
    func totalMacros() -> (protein: Double, fats: Double, carbs: Double) { let p = meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.protein }; let f = meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.fats }; let c = meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.carbs }; return (p, f, c) }
    func macroDerivedCalories() -> Double {
        let macros = totalMacros()
        return NutritionCalorieConsistency.macroDerivedCalories(protein: macros.protein, carbs: macros.carbs, fats: macros.fats)
    }
    func calorieConsistencyStatus() -> NutritionCalorieConsistency.Status {
        let macros = totalMacros()
        return NutritionCalorieConsistency.status(calories: totalCalories(), protein: macros.protein, carbs: macros.carbs, fats: macros.fats)
    }
    func foodsWithMeaningfulCalorieMacroMismatch() -> [FoodItem] {
        meals.flatMap(\.foodItems).filter(\.hasMeaningfulCalorieMacroMismatch)
    }
    func totalMicronutrients() -> (
        calcium: Double, iron: Double, potassium: Double, sodium: Double, vitaminA: Double, vitaminC: Double, vitaminD: Double, vitaminB12: Double, folate: Double, fiber: Double, magnesium: Double, phosphorus: Double, zinc: Double, copper: Double, manganese: Double, selenium: Double, vitaminB1: Double, vitaminB2: Double, vitaminB3: Double, vitaminB5: Double, vitaminB6: Double, vitaminE: Double, vitaminK: Double
    ) {
        var ca=0.0, fe=0.0, k=0.0, na=0.0, va=0.0, vc=0.0, vd=0.0, vb12=0.0, fol=0.0, fib=0.0, mg=0.0, p=0.0, zn=0.0, cu=0.0, mn=0.0, se=0.0, vb1=0.0, vb2=0.0, vb3=0.0, vb5=0.0, vb6=0.0, ve=0.0, vk=0.0
        for meal in meals {
            for item in meal.foodItems {
                ca += item.calcium ?? 0; fe += item.iron ?? 0; k += item.potassium ?? 0; na += item.sodium ?? 0
                va += item.vitaminA ?? 0; vc += item.vitaminC ?? 0; vd += item.vitaminD ?? 0; vb12 += item.vitaminB12 ?? 0
                fol += item.folate ?? 0; fib += item.fiber ?? 0; mg += item.magnesium ?? 0; p += item.phosphorus ?? 0
                zn += item.zinc ?? 0; cu += item.copper ?? 0; mn += item.manganese ?? 0; se += item.selenium ?? 0
                vb1 += item.vitaminB1 ?? 0; vb2 += item.vitaminB2 ?? 0; vb3 += item.vitaminB3 ?? 0
                vb5 += item.vitaminB5 ?? 0; vb6 += item.vitaminB6 ?? 0; ve += item.vitaminE ?? 0; vk += item.vitaminK ?? 0
            }
        }
        return (ca, fe, k, na, va, vc, vd, vb12, fol, fib, mg, p, zn, cu, mn, se, vb1, vb2, vb3, vb5, vb6, ve, vk)
    }
    func totalSaturatedFat() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + ($1.saturatedFat ?? 0) } }
    func totalPolyunsaturatedFat() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + ($1.polyunsaturatedFat ?? 0) } }
    func totalMonounsaturatedFat() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + ($1.monounsaturatedFat ?? 0) } }
    func totalCaloriesBurnedFromManualExercises() -> Double { return exercises?.filter { $0.source == "manual" }.reduce(0) { $0 + $1.caloriesBurned } ?? 0.0 }
    func totalCaloriesBurnedFromHealthKitWorkouts() -> Double { return exercises?.filter { $0.source == "HealthKit" }.reduce(0) { $0 + $1.caloriesBurned } ?? 0.0 }
    static func == (lhs: DailyLog, rhs: DailyLog) -> Bool {
            lhs.id == rhs.id &&
            Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) &&
            lhs.meals == rhs.meals &&
            lhs.totalCaloriesOverride == rhs.totalCaloriesOverride &&
            lhs.waterTracker == rhs.waterTracker &&
            lhs.exercises == rhs.exercises &&
            lhs.journalEntries == rhs.journalEntries
        }

    enum CodingKeys: String, CodingKey {
            case id, date, meals, totalCaloriesOverride, waterTracker, exercises, journalEntries
    }
}

struct ServingSizeOption: Identifiable, Hashable {
    let id = UUID()
    let description: String
    let servingWeightGrams: Double?
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let saturatedFat: Double?
    let polyunsaturatedFat: Double?
    let monounsaturatedFat: Double?
    let fiber: Double?
    let calcium: Double?
    let iron: Double?
    let potassium: Double?
    let sodium: Double?
    let vitaminA: Double?
    let vitaminC: Double?
    let vitaminD: Double?
    let vitaminB12: Double?
    let folate: Double?
    let magnesium: Double?
    let phosphorus: Double?
    let zinc: Double?
    let copper: Double?
    let manganese: Double?
    let selenium: Double?
    let vitaminB1: Double?
    let vitaminB2: Double?
    let vitaminB3: Double?
    let vitaminB5: Double?
    let vitaminB6: Double?
    let vitaminE: Double?
    let vitaminK: Double?

    func hash(into hasher: inout Hasher) { hasher.combine(description); hasher.combine(servingWeightGrams) }
    static func == (lhs: ServingSizeOption, rhs: ServingSizeOption) -> Bool { lhs.description == rhs.description && lhs.servingWeightGrams == rhs.servingWeightGrams }
}

struct AdjustedServingNutrition {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
    let saturatedFat: Double?
    let polyunsaturatedFat: Double?
    let monounsaturatedFat: Double?
    let fiber: Double?
    let calcium: Double?
    let iron: Double?
    let potassium: Double?
    let sodium: Double?
    let vitaminA: Double?
    let vitaminC: Double?
    let vitaminD: Double?
    let vitaminB12: Double?
    let folate: Double?
    let magnesium: Double?
    let phosphorus: Double?
    let zinc: Double?
    let copper: Double?
    let manganese: Double?
    let selenium: Double?
    let vitaminB1: Double?
    let vitaminB2: Double?
    let vitaminB3: Double?
    let vitaminB5: Double?
    let vitaminB6: Double?
    let vitaminE: Double?
    let vitaminK: Double?
    let servingDescription: String
    let servingWeightGrams: Double
    let quantityValue: Double
    let servingUnit: String
}

enum ServingNutritionCalculator {
    static func parseQuantity(from servingDescription: String) -> (quantity: Double, baseDescription: String) {
        let components = servingDescription.components(separatedBy: " x ")
        if components.count == 2, let quantity = Double(components[0]), quantity > 0 {
            return (quantity, components[1])
        }
        return (1.0, servingDescription)
    }

    static func baseServing(from item: FoodItem) -> ServingSizeOption {
        let parsed = parseQuantity(from: item.servingSize)
        let quantity = safeQuantity(item.quantityValue ?? parsed.quantity)
        let unit = item.servingUnit ?? normalizedServingDescription(parsed.baseDescription)

        return ServingSizeOption(
            description: unit,
            servingWeightGrams: item.servingWeight / quantity,
            calories: item.calories / quantity,
            protein: item.protein / quantity,
            carbs: item.carbs / quantity,
            fats: item.fats / quantity,
            saturatedFat: item.saturatedFat.map { $0 / quantity },
            polyunsaturatedFat: item.polyunsaturatedFat.map { $0 / quantity },
            monounsaturatedFat: item.monounsaturatedFat.map { $0 / quantity },
            fiber: item.fiber.map { $0 / quantity },
            calcium: item.calcium.map { $0 / quantity },
            iron: item.iron.map { $0 / quantity },
            potassium: item.potassium.map { $0 / quantity },
            sodium: item.sodium.map { $0 / quantity },
            vitaminA: item.vitaminA.map { $0 / quantity },
            vitaminC: item.vitaminC.map { $0 / quantity },
            vitaminD: item.vitaminD.map { $0 / quantity },
            vitaminB12: item.vitaminB12.map { $0 / quantity },
            folate: item.folate.map { $0 / quantity },
            magnesium: item.magnesium.map { $0 / quantity },
            phosphorus: item.phosphorus.map { $0 / quantity },
            zinc: item.zinc.map { $0 / quantity },
            copper: item.copper.map { $0 / quantity },
            manganese: item.manganese.map { $0 / quantity },
            selenium: item.selenium.map { $0 / quantity },
            vitaminB1: item.vitaminB1.map { $0 / quantity },
            vitaminB2: item.vitaminB2.map { $0 / quantity },
            vitaminB3: item.vitaminB3.map { $0 / quantity },
            vitaminB5: item.vitaminB5.map { $0 / quantity },
            vitaminB6: item.vitaminB6.map { $0 / quantity },
            vitaminE: item.vitaminE.map { $0 / quantity },
            vitaminK: item.vitaminK.map { $0 / quantity }
        )
    }

    static func adjustedNutrition(base: ServingSizeOption, quantityText: String) -> AdjustedServingNutrition {
        let quantity = safeQuantity(Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)))
        return adjustedNutrition(base: base, quantityValue: quantity)
    }

    static func adjustedNutrition(base: ServingSizeOption, quantityValue: Double) -> AdjustedServingNutrition {
        let quantity = safeQuantity(quantityValue)
        let unit = normalizedServingDescription(base.description)
        let servingDescription = quantity == 1 ? unit : "\(String(format: "%g", quantity)) x \(unit)"
        let servingWeight = (base.servingWeightGrams ?? 0) * quantity

        return AdjustedServingNutrition(
            calories: base.calories * quantity,
            protein: base.protein * quantity,
            carbs: base.carbs * quantity,
            fats: base.fats * quantity,
            saturatedFat: base.saturatedFat.map { $0 * quantity },
            polyunsaturatedFat: base.polyunsaturatedFat.map { $0 * quantity },
            monounsaturatedFat: base.monounsaturatedFat.map { $0 * quantity },
            fiber: base.fiber.map { $0 * quantity },
            calcium: base.calcium.map { $0 * quantity },
            iron: base.iron.map { $0 * quantity },
            potassium: base.potassium.map { $0 * quantity },
            sodium: base.sodium.map { $0 * quantity },
            vitaminA: base.vitaminA.map { $0 * quantity },
            vitaminC: base.vitaminC.map { $0 * quantity },
            vitaminD: base.vitaminD.map { $0 * quantity },
            vitaminB12: base.vitaminB12.map { $0 * quantity },
            folate: base.folate.map { $0 * quantity },
            magnesium: base.magnesium.map { $0 * quantity },
            phosphorus: base.phosphorus.map { $0 * quantity },
            zinc: base.zinc.map { $0 * quantity },
            copper: base.copper.map { $0 * quantity },
            manganese: base.manganese.map { $0 * quantity },
            selenium: base.selenium.map { $0 * quantity },
            vitaminB1: base.vitaminB1.map { $0 * quantity },
            vitaminB2: base.vitaminB2.map { $0 * quantity },
            vitaminB3: base.vitaminB3.map { $0 * quantity },
            vitaminB5: base.vitaminB5.map { $0 * quantity },
            vitaminB6: base.vitaminB6.map { $0 * quantity },
            vitaminE: base.vitaminE.map { $0 * quantity },
            vitaminK: base.vitaminK.map { $0 * quantity },
            servingDescription: servingDescription,
            servingWeightGrams: servingWeight,
            quantityValue: quantity,
            servingUnit: unit
        )
    }

    private static func safeQuantity(_ value: Double?) -> Double {
        guard let value, value > 0 else { return 1.0 }
        return value
    }

    private static func normalizedServingDescription(_ description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "1 serving" : trimmed
    }
}

struct BarcodeQueryResult: Identifiable {
    let id = UUID()
    let barcode: String
}
