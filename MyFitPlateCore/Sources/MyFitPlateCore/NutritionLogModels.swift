import Foundation

public enum NutritionCalorieConsistency {
    static let absoluteMismatchThreshold = 75.0
    static let relativeMismatchThreshold = 0.12

    public struct Status: Equatable {
        public let loggedCalories: Double
        public let macroDerivedCalories: Double
        public let delta: Double
        public let relativeDelta: Double
        public let hasMeaningfulMismatch: Bool

        public var mismatchAmount: Double {
            abs(delta)
        }

        public var directionText: String {
            delta > 0 ? "higher" : "lower"
        }
    }

    public static func macroDerivedCalories(protein: Double, carbs: Double, fats: Double) -> Double {
        max(0, protein) * 4 + max(0, carbs) * 4 + max(0, fats) * 9
    }

    public static func status(calories: Double, protein: Double, carbs: Double, fats: Double) -> Status {
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

    public static func normalizedCaloriesForEstimatedSource(calories: Double, protein: Double, carbs: Double, fats: Double, source: String) -> Double {
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

    public static func isEstimatedSource(_ source: String) -> Bool {
        let normalizedSource = source.lowercased()
        return normalizedSource.contains("ai") || normalizedSource.contains("manual")
    }
}

#if DEBUG
public enum NutritionConsistencySelfCheck {
    public static func run() {
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

public struct FoodItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fats: Double
    public var saturatedFat: Double?
    public var polyunsaturatedFat: Double?
    public var monounsaturatedFat: Double?
    public var fiber: Double?
    public var servingSize: String
    public var servingWeight: Double
    public var timestamp: Date?

    public init(id: String = UUID().uuidString, name: String, calories: Double = 0, protein: Double = 0, carbs: Double = 0, fats: Double = 0, saturatedFat: Double? = nil, polyunsaturatedFat: Double? = nil, monounsaturatedFat: Double? = nil, fiber: Double? = nil, servingSize: String = "1 serving", servingWeight: Double = 1.0, timestamp: Date? = nil, calcium: Double? = nil, iron: Double? = nil, potassium: Double? = nil, sodium: Double? = nil, vitaminA: Double? = nil, vitaminC: Double? = nil, vitaminD: Double? = nil, vitaminB12: Double? = nil, folate: Double? = nil, magnesium: Double? = nil, phosphorus: Double? = nil, zinc: Double? = nil, copper: Double? = nil, manganese: Double? = nil, selenium: Double? = nil, vitaminB1: Double? = nil, vitaminB2: Double? = nil, vitaminB3: Double? = nil, vitaminB5: Double? = nil, vitaminB6: Double? = nil, vitaminE: Double? = nil, vitaminK: Double? = nil) {
        self.id = id; self.name = name; self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
        self.saturatedFat = saturatedFat; self.polyunsaturatedFat = polyunsaturatedFat; self.monounsaturatedFat = monounsaturatedFat; self.fiber = fiber
        self.servingSize = servingSize; self.servingWeight = servingWeight; self.timestamp = timestamp
        self.calcium = calcium; self.iron = iron; self.potassium = potassium; self.sodium = sodium
        self.vitaminA = vitaminA; self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminB12 = vitaminB12; self.folate = folate
        self.magnesium = magnesium; self.phosphorus = phosphorus; self.zinc = zinc; self.copper = copper; self.manganese = manganese; self.selenium = selenium
        self.vitaminB1 = vitaminB1; self.vitaminB2 = vitaminB2; self.vitaminB3 = vitaminB3; self.vitaminB5 = vitaminB5; self.vitaminB6 = vitaminB6
        self.vitaminE = vitaminE; self.vitaminK = vitaminK
    }

    // Micros
    public var calcium: Double?
    public var iron: Double?
    public var potassium: Double?
    public var sodium: Double?
    public var vitaminA: Double?
    public var vitaminC: Double?
    public var vitaminD: Double?
    public var vitaminB12: Double?
    public var folate: Double?
    public var magnesium: Double?
    public var phosphorus: Double?
    public var zinc: Double?
    public var copper: Double?
    public var manganese: Double?
    public var selenium: Double?
    public var vitaminB1: Double?
    public var vitaminB2: Double?
    public var vitaminB3: Double?
    public var vitaminB5: Double?
    public var vitaminB6: Double?
    public var vitaminE: Double?
    public var vitaminK: Double?

    public var quantityValue: Double? = nil
    public var servingUnit: String? = nil

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: FoodItem, rhs: FoodItem) -> Bool { lhs.id == rhs.id }

    public enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fats, saturatedFat, polyunsaturatedFat, monounsaturatedFat, fiber, servingSize, servingWeight, timestamp, calcium, iron, potassium, sodium, vitaminA, vitaminC, vitaminD, vitaminB12, folate, magnesium, phosphorus, zinc, copper, manganese, selenium, vitaminB1, vitaminB2, vitaminB3, vitaminB5, vitaminB6, vitaminE, vitaminK
        case quantityValue, servingUnit
    }
}

public extension FoodItem {
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

public struct Meal: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var foodItems: [FoodItem]
    
    public init(id: UUID = UUID(), name: String, foodItems: [FoodItem] = []) {
        self.id = id
        self.name = name
        self.foodItems = foodItems
    }
    public static func == (lhs: Meal, rhs: Meal) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.foodItems == rhs.foodItems }
}

public struct WaterTracker: Codable, Equatable {
    public var totalOunces: Double
    public var goalOunces: Double
    public var date: Date
    public init(totalOunces: Double, goalOunces: Double = 64.0, date: Date) { self.totalOunces = totalOunces; self.goalOunces = goalOunces; self.date = date }
}

public struct LoggedExercise: Codable, Identifiable, Hashable {
    public var id: String = UUID().uuidString
    public var name: String
    public var durationMinutes: Int?
    public var caloriesBurned: Double
    public var date: Date
    public var source: String = "manual"
    public var workoutID: String?
    public var sessionID: String?

    public init(id: String = UUID().uuidString, name: String, durationMinutes: Int? = nil, caloriesBurned: Double, date: Date, source: String = "manual", workoutID: String? = nil, sessionID: String? = nil) {
        self.id = id
        self.name = name
        self.durationMinutes = durationMinutes
        self.caloriesBurned = caloriesBurned
        self.date = date
        self.source = source
        self.workoutID = workoutID
        self.sessionID = sessionID
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: LoggedExercise, rhs: LoggedExercise) -> Bool { lhs.id == rhs.id }
}

public extension Array where Element == LoggedExercise {
    /// Collapses a MyFitPlate-logged workout (source "routine"/"manual") that overlaps an
    /// Apple Health workout in time into a single entry — keeping the MyFitPlate name but
    /// using Health's *measured* calories and duration. Prevents the same session (e.g. a
    /// routine you also recorded on your Apple Watch) from being counted twice in the
    /// activity list, the "burned" total, and any eat-back math.
    func dedupedAgainstHealthKit(bufferMinutes: Double = 30) -> [LoggedExercise] {
        let healthKit = filter { $0.source == "HealthKit" }
        guard !healthKit.isEmpty else { return self }

        let buffer = bufferMinutes * 60

        // Apple Health stores `date` as the workout start; MyFitPlate stores it as the
        // completion (end) time. Normalize both to an interval before comparing.
        func interval(_ ex: LoggedExercise) -> (start: Date, end: Date) {
            let dur = Double(ex.durationMinutes ?? 0) * 60
            return ex.source == "HealthKit"
                ? (ex.date, ex.date.addingTimeInterval(dur))
                : (ex.date.addingTimeInterval(-dur), ex.date)
        }
        func overlaps(_ a: LoggedExercise, _ b: LoggedExercise) -> Bool {
            let ia = interval(a), ib = interval(b)
            return ia.start.addingTimeInterval(-buffer) <= ib.end
                && ib.start.addingTimeInterval(-buffer) <= ia.end
        }

        // Pair each MyFitPlate entry to at most one overlapping Health workout.
        var consumedHealthKitIDs = Set<String>()
        var measuredFor: [String: (calories: Double, duration: Int?)] = [:]
        for ex in self where ex.source != "HealthKit" {
            if let match = healthKit.first(where: { !consumedHealthKitIDs.contains($0.id) && overlaps(ex, $0) }) {
                consumedHealthKitIDs.insert(match.id)
                measuredFor[ex.id] = (match.caloriesBurned, match.durationMinutes)
            }
        }

        // Same-day strength fallback: a MyFitPlate routine and an Apple Health strength
        // workout on the same day are almost always the same session, even when the logged
        // times drift apart (MyFitPlate's stored "duration" is a set-count proxy, not wall
        // clock, so a parallel Apple Watch session falls outside the overlap buffer). Merge
        // so the session isn't double-counted in the activity list or the burned total.
        for ex in self where ex.source != "HealthKit" && measuredFor[ex.id] == nil {
            if let match = healthKit.first(where: {
                !consumedHealthKitIDs.contains($0.id)
                    && $0.name.localizedCaseInsensitiveContains("strength")
                    && Calendar.current.isDate($0.date, inSameDayAs: ex.date)
            }) {
                consumedHealthKitIDs.insert(match.id)
                measuredFor[ex.id] = (match.caloriesBurned, match.durationMinutes)
            }
        }

        // Rebuild in original order: drop paired Health workouts, swap matched MyFitPlate
        // entries to the measured calories/duration.
        return compactMap { ex in
            if ex.source == "HealthKit" {
                return consumedHealthKitIDs.contains(ex.id) ? nil : ex
            }
            guard let measured = measuredFor[ex.id] else { return ex }
            var merged = ex
            merged.caloriesBurned = measured.calories
            merged.durationMinutes = measured.duration ?? ex.durationMinutes
            return merged
        }
    }
}

public struct DailyLog: Codable, Identifiable, Equatable {
    public var id: String?
    public var date: Date
    public var meals: [Meal]
    public var totalCaloriesOverride: Double?
    public var waterTracker: WaterTracker?
    public var exercises: [LoggedExercise]?
    public var journalEntries: [JournalEntry]?

    public init(id: String? = nil, date: Date, meals: [Meal], totalCaloriesOverride: Double? = nil, waterTracker: WaterTracker? = nil, exercises: [LoggedExercise]? = nil, journalEntries: [JournalEntry]? = nil) {
        self.id = id
        self.date = date
        self.meals = meals
        self.totalCaloriesOverride = totalCaloriesOverride
        self.waterTracker = waterTracker
        self.exercises = exercises
        self.journalEntries = journalEntries
    }

    public func totalCalories() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.calories } }
    public func totalMacros() -> (protein: Double, fats: Double, carbs: Double) { let p = meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.protein }; let f = meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.fats }; let c = meals.flatMap { $0.foodItems }.reduce(0) { $0 + $1.carbs }; return (p, f, c) }
    public func macroDerivedCalories() -> Double {
        let macros = totalMacros()
        return NutritionCalorieConsistency.macroDerivedCalories(protein: macros.protein, carbs: macros.carbs, fats: macros.fats)
    }
    public func calorieConsistencyStatus() -> NutritionCalorieConsistency.Status {
        let macros = totalMacros()
        return NutritionCalorieConsistency.status(calories: totalCalories(), protein: macros.protein, carbs: macros.carbs, fats: macros.fats)
    }
    public func foodsWithMeaningfulCalorieMacroMismatch() -> [FoodItem] {
        meals.flatMap(\.foodItems).filter(\.hasMeaningfulCalorieMacroMismatch)
    }
    public typealias MicronutrientTotals = (
        calcium: Double, iron: Double, potassium: Double, sodium: Double, vitaminA: Double, vitaminC: Double, vitaminD: Double, vitaminB12: Double, folate: Double, fiber: Double, magnesium: Double, phosphorus: Double, zinc: Double, copper: Double, manganese: Double, selenium: Double, vitaminB1: Double, vitaminB2: Double, vitaminB3: Double, vitaminB5: Double, vitaminB6: Double, vitaminE: Double, vitaminK: Double
    )

    public func totalMicronutrients() -> MicronutrientTotals {
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
    public func totalSaturatedFat() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + ($1.saturatedFat ?? 0) } }
    public func totalPolyunsaturatedFat() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + ($1.polyunsaturatedFat ?? 0) } }
    public func totalMonounsaturatedFat() -> Double { meals.flatMap { $0.foodItems }.reduce(0) { $0 + ($1.monounsaturatedFat ?? 0) } }
    public func totalCaloriesBurnedFromManualExercises() -> Double { return exercises?.filter { $0.source == "manual" }.reduce(0) { $0 + $1.caloriesBurned } ?? 0.0 }
    public func totalCaloriesBurnedFromHealthKitWorkouts() -> Double { return exercises?.filter { $0.source == "HealthKit" }.reduce(0) { $0 + $1.caloriesBurned } ?? 0.0 }
    public static func == (lhs: DailyLog, rhs: DailyLog) -> Bool {
            lhs.id == rhs.id &&
            Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) &&
            lhs.meals == rhs.meals &&
            lhs.totalCaloriesOverride == rhs.totalCaloriesOverride &&
            lhs.waterTracker == rhs.waterTracker &&
            lhs.exercises == rhs.exercises &&
            lhs.journalEntries == rhs.journalEntries
        }

    public enum CodingKeys: String, CodingKey {
            case id, date, meals, totalCaloriesOverride, waterTracker, exercises, journalEntries
    }
}

public struct ServingSizeOption: Identifiable, Hashable {
    public let id = UUID()
    public let description: String
    public let servingWeightGrams: Double?
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let saturatedFat: Double?
    public let polyunsaturatedFat: Double?
    public let monounsaturatedFat: Double?
    public let fiber: Double?
    public let calcium: Double?
    public let iron: Double?
    public let potassium: Double?
    public let sodium: Double?
    public let vitaminA: Double?
    public let vitaminC: Double?
    public let vitaminD: Double?
    public let vitaminB12: Double?
    public let folate: Double?
    public let magnesium: Double?
    public let phosphorus: Double?
    public let zinc: Double?
    public let copper: Double?
    public let manganese: Double?
    public let selenium: Double?
    public let vitaminB1: Double?
    public let vitaminB2: Double?
    public let vitaminB3: Double?
    public let vitaminB5: Double?
    public let vitaminB6: Double?
    public let vitaminE: Double?
    public let vitaminK: Double?

    public init(description: String, servingWeightGrams: Double?, calories: Double, protein: Double, carbs: Double, fats: Double, saturatedFat: Double? = nil, polyunsaturatedFat: Double? = nil, monounsaturatedFat: Double? = nil, fiber: Double? = nil, calcium: Double? = nil, iron: Double? = nil, potassium: Double? = nil, sodium: Double? = nil, vitaminA: Double? = nil, vitaminC: Double? = nil, vitaminD: Double? = nil, vitaminB12: Double? = nil, folate: Double? = nil, magnesium: Double? = nil, phosphorus: Double? = nil, zinc: Double? = nil, copper: Double? = nil, manganese: Double? = nil, selenium: Double? = nil, vitaminB1: Double? = nil, vitaminB2: Double? = nil, vitaminB3: Double? = nil, vitaminB5: Double? = nil, vitaminB6: Double? = nil, vitaminE: Double? = nil, vitaminK: Double? = nil) {
        self.description = description; self.servingWeightGrams = servingWeightGrams; self.calories = calories; self.protein = protein; self.carbs = carbs; self.fats = fats
        self.saturatedFat = saturatedFat; self.polyunsaturatedFat = polyunsaturatedFat; self.monounsaturatedFat = monounsaturatedFat; self.fiber = fiber
        self.calcium = calcium; self.iron = iron; self.potassium = potassium; self.sodium = sodium
        self.vitaminA = vitaminA; self.vitaminC = vitaminC; self.vitaminD = vitaminD; self.vitaminB12 = vitaminB12; self.folate = folate
        self.magnesium = magnesium; self.phosphorus = phosphorus; self.zinc = zinc; self.copper = copper; self.manganese = manganese; self.selenium = selenium
        self.vitaminB1 = vitaminB1; self.vitaminB2 = vitaminB2; self.vitaminB3 = vitaminB3; self.vitaminB5 = vitaminB5; self.vitaminB6 = vitaminB6; self.vitaminE = vitaminE; self.vitaminK = vitaminK
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(description); hasher.combine(servingWeightGrams) }
    public static func == (lhs: ServingSizeOption, rhs: ServingSizeOption) -> Bool { lhs.description == rhs.description && lhs.servingWeightGrams == rhs.servingWeightGrams }
}

public struct AdjustedServingNutrition {
    public let calories: Double
    public let protein: Double
    public let carbs: Double
    public let fats: Double
    public let saturatedFat: Double?
    public let polyunsaturatedFat: Double?
    public let monounsaturatedFat: Double?
    public let fiber: Double?
    public let calcium: Double?
    public let iron: Double?
    public let potassium: Double?
    public let sodium: Double?
    public let vitaminA: Double?
    public let vitaminC: Double?
    public let vitaminD: Double?
    public let vitaminB12: Double?
    public let folate: Double?
    public let magnesium: Double?
    public let phosphorus: Double?
    public let zinc: Double?
    public let copper: Double?
    public let manganese: Double?
    public let selenium: Double?
    public let vitaminB1: Double?
    public let vitaminB2: Double?
    public let vitaminB3: Double?
    public let vitaminB5: Double?
    public let vitaminB6: Double?
    public let vitaminE: Double?
    public let vitaminK: Double?
    public let servingDescription: String
    public let servingWeightGrams: Double
    public let quantityValue: Double
    public let servingUnit: String
}

public enum ServingNutritionCalculator {
    public static func parseQuantity(from servingDescription: String) -> (quantity: Double, baseDescription: String) {
        let components = servingDescription.components(separatedBy: " x ")
        if components.count == 2, let quantity = Double(components[0]), quantity > 0 {
            return (quantity, components[1])
        }
        return (1.0, servingDescription)
    }

    public static func baseServing(from item: FoodItem) -> ServingSizeOption {
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

    public static func adjustedNutrition(base: ServingSizeOption, quantityText: String) -> AdjustedServingNutrition {
        let quantity = safeQuantity(Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)))
        return adjustedNutrition(base: base, quantityValue: quantity)
    }

    public static func adjustedNutrition(base: ServingSizeOption, quantityValue: Double) -> AdjustedServingNutrition {
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

public struct BarcodeQueryResult: Identifiable {
    public let id = UUID()
    public let barcode: String
}
