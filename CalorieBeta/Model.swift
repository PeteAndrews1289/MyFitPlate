import Foundation
import FirebaseFirestore
import SwiftUI

enum ExerciseType: String, Codable, CaseIterable {
    case strength = "Strength"
    case cardio = "Cardio"
    case flexibility = "Flexibility"
}

struct WorkoutProgram: Identifiable, Codable {
    @DocumentID var id: String?
    var userID: String
    var name: String
    var dateCreated: Timestamp
    var routines: [WorkoutRoutine]
    var startDate: Timestamp?
    var daysOfWeek: [Int]?
    var currentProgressIndex: Int? = 0
}

class WorkoutRoutine: Identifiable, ObservableObject, Codable, Hashable {
    var id: String
    var userID: String
    @Published var name: String
    var dateCreated: Timestamp
    @Published var exercises: [RoutineExercise]
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, userID, name, dateCreated, exercises, notes
    }

    init(id: String = UUID().uuidString, userID: String, name: String, dateCreated: Timestamp, exercises: [RoutineExercise] = [], notes: String? = nil) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dateCreated = dateCreated
        self.exercises = exercises
        self.notes = notes
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userID = try container.decode(String.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        dateCreated = try container.decode(Timestamp.self, forKey: .dateCreated)
        exercises = try container.decode([RoutineExercise].self, forKey: .exercises)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(exercises, forKey: .exercises)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WorkoutRoutine, rhs: WorkoutRoutine) -> Bool {
        lhs.id == rhs.id
    }
}


struct RoutineExercise: Identifiable, Codable{
    var id: String = UUID().uuidString
    var name: String
    var type: ExerciseType = .strength
    var sets: [ExerciseSet] = []
    var notes: String?
    var restTimeInSeconds: Int = 60
    var alternatives: [String]?
    var targetSets: Int = 3
    var targetReps: String = "8-12"
}

struct ExerciseSet: Identifiable, Codable{
    var id: String = UUID().uuidString
    var isCompleted: Bool = false
    var target: String?
    var previousPerformance: String?
    var isWarmup: Bool = false
    
    var reps: Int = 0
    var weight: Double = 0.0
    var distance: Double = 0.0
    var durationInSeconds: Int = 0
}

struct WorkoutSessionLog: Identifiable, Codable {
    @DocumentID var id: String?
    var date: Timestamp
    var routineID: String
    var completedExercises: [CompletedExercise]
}

struct CompletedExercise: Identifiable, Codable {
    var id: String = UUID().uuidString
    var exerciseName: String
    var exercise: RoutineExercise
    var sets: [CompletedSet]
    var date: Date {
        return Date()
    }
}

struct CompletedSet: Identifiable, Codable {
    var id: String = UUID().uuidString
    var reps: Int
    var weight: Double
    var distance: Double?
    var durationInSeconds: Int?
}

struct UserInsight: Identifiable, Decodable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var category: InsightCategory
    var priority: Int = 0
    var sourceData: String?

    private enum CodingKeys: String, CodingKey {
        case title, message, category, priority, sourceData
    }
    
    enum InsightCategory: String, Codable, Equatable, CaseIterable {
        case nutritionGeneral, hydration, macroBalance, microNutrient, mealTiming, consistency, postWorkout, foodVariety, positiveReinforcement, sugarAwareness, fiberIntake, saturatedFat, smartSuggestion, sleep, calorieFluctuation, weekendTrends, exerciseSynergy
    }
    
    init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            message = try container.decode(String.self, forKey: .message)
            category = (try? container.decode(InsightCategory.self, forKey: .category)) ?? .nutritionGeneral
            priority = (try? container.decode(Int.self, forKey: .priority)) ?? 0
            sourceData = try container.decodeIfPresent(String.self, forKey: .sourceData) // Decode the new property
        }

        init(title: String, message: String, category: InsightCategory, priority: Int = 0, sourceData: String? = nil) {
            self.title = title
            self.message = message
            self.category = category
            self.priority = priority
            self.sourceData = sourceData
        }
}

struct JournalEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: Date
    var text: String
    var category: String
}

struct PlannedMeal: Identifiable, Codable {
    let id: String
    let mealType: String
    var recipeID: String?
    var foodItem: FoodItem?
    var ingredients: [String]?
    var instructions: String?
}

struct MealPlanDay: Identifiable, Codable {
    @DocumentID var id: String?
    var date: Timestamp
    var meals: [PlannedMeal]
}

enum ReportTimeframe: String, CaseIterable, Identifiable {
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case custom = "Custom Range"
    var id: String { self.rawValue }
}

enum WeightChartTimeframe: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case threeMonths = "3M"
    case year = "Y"
    case allTime = "All"
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .week: return "Last 7 Days"
        case .month: return "Last 30 Days"
        case .threeMonths: return "Last 3 Months"
        case .year: return "Last Year"
        case .allTime: return "All Time"
        }
    }
}

struct GroceryListItem: Identifiable, Codable, Equatable {
    let id = UUID()
    var name: String
    var quantity: Double
    var unit: String
    var isCompleted: Bool = false
    var category: String = "Misc"
}

struct ChallengeType: RawRepresentable, Codable, Hashable {
    var rawValue: String
}
extension ChallengeType {
    static let loggingStreak = ChallengeType(rawValue: "loggingStreak")
    static let proteinGoalHit = ChallengeType(rawValue: "proteinGoalHit")
    static let workoutLogged = ChallengeType(rawValue: "workoutLogged")
    static let calorieRange = ChallengeType(rawValue: "calorieRange")
}

struct Challenge: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var type: ChallengeType
    var goal: Double
    var progress: Double = 0
    var pointsValue: Int
    var isCompleted: Bool = false
    var expiresAt: Timestamp
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

struct BarcodeQueryResult: Identifiable {
    let id = UUID()
    let barcode: String
}

struct RecipeIngredient: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var foodId: String?
    var foodName: String
    var quantity: Double
    var selectedServingDescription: String?
    var selectedServingWeightGrams: Double?
    var calories: Double
    var protein: Double
    var carbs: Double
    var fats: Double
    var saturatedFat: Double?
    var polyunsaturatedFat: Double?
    var monounsaturatedFat: Double?
    var fiber: Double?
    var calcium: Double?
    var iron: Double?
    var potassium: Double?
    var sodium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var vitaminB12: Double?
    var folate: Double?
    var originalImportedString: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RecipeIngredient, rhs: RecipeIngredient) -> Bool { lhs.id == rhs.id }
}

enum MenstrualPhase: String, CaseIterable, Identifiable {
    case menstrual, follicular, ovulatory, luteal
    var id: Self { self }
}

struct CycleSettings: Codable {
    var typicalCycleLength: Int = 28
    var typicalPeriodLength: Int = 5
}

struct CycleDay {
    let date: Date
    let cycleDayNumber: Int
    let phase: MenstrualPhase
}

struct AIInsight: Codable {
    struct TrainingFocus: Codable {
        let title: String
        let description: String
    }
    let phaseTitle: String
    let phaseDescription: String
    let trainingFocus: TrainingFocus
    let hormonalState: String
    let energyLevel: String
    let nutritionTip: String
    let symptomTip: String
}

struct UserRecipe: Codable, Identifiable {
    @DocumentID var id: String?
    var userID: String
    var name: String
    var ingredients: [RecipeIngredient] = []
    var totalServings: Double = 1.0
    var servingSizeDescription: String = "1 serving"
    var totalNutrition: RecipeNutrition = RecipeNutrition()
    var nutritionPerServing: RecipeNutrition = RecipeNutrition()
    var createdAt: Timestamp? = Timestamp(date: Date())
    var updatedAt: Timestamp? = Timestamp(date: Date())
    var instructions: [String]? = []

    struct RecipeNutrition: Codable {
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fats: Double = 0
        var saturatedFat: Double? = 0
        var polyunsaturatedFat: Double? = 0
        var monounsaturatedFat: Double? = 0
        var fiber: Double? = 0
        var calcium: Double? = 0
        var iron: Double? = 0
        var potassium: Double? = 0
        var sodium: Double? = 0
        var vitaminA: Double? = 0
        var vitaminC: Double? = 0
        var vitaminD: Double? = 0
        var vitaminB12: Double? = 0
        var folate: Double? = 0
        var magnesium: Double? = 0
        var phosphorus: Double? = 0
        var zinc: Double? = 0
        var copper: Double? = 0
        var manganese: Double? = 0
        var selenium: Double? = 0
        var vitaminB1: Double? = 0
        var vitaminB2: Double? = 0
        var vitaminB3: Double? = 0
        var vitaminB5: Double? = 0
        var vitaminB6: Double? = 0
        var vitaminE: Double? = 0
        var vitaminK: Double? = 0
    }

    mutating func calculateTotals() {
        let allIngredientsMatched = !ingredients.contains { $0.foodId == nil }

        guard allIngredientsMatched else {
            return
        }

        var totalCals: Double = 0; var totalP: Double = 0; var totalC: Double = 0; var totalF: Double = 0
        var totalSatF: Double = 0; var totalPolyF: Double = 0; var totalMonoF: Double = 0; var totalFib: Double = 0
        var totalCa: Double = 0; var totalFe: Double = 0; var totalK: Double = 0; var totalNa: Double = 0
        var totalVa: Double = 0; var totalVc: Double = 0; var totalVd: Double = 0
        var totalVb12: Double = 0; var totalFol: Double = 0

        for ingredient in ingredients {
            totalCals += ingredient.calories; totalP += ingredient.protein; totalC += ingredient.carbs; totalF += ingredient.fats
            totalSatF += ingredient.saturatedFat ?? 0; totalPolyF += ingredient.polyunsaturatedFat ?? 0; totalMonoF += ingredient.monounsaturatedFat ?? 0; totalFib += ingredient.fiber ?? 0
            totalCa += ingredient.calcium ?? 0; totalFe += ingredient.iron ?? 0; totalK += ingredient.potassium ?? 0; totalNa += ingredient.sodium ?? 0
            totalVa += ingredient.vitaminA ?? 0; totalVc += ingredient.vitaminC ?? 0; totalVd += ingredient.vitaminD ?? 0
            totalVb12 += ingredient.vitaminB12 ?? 0; totalFol += ingredient.folate ?? 0
        }

        totalNutrition = RecipeNutrition(calories: totalCals, protein: totalP, carbs: totalC, fats: totalF, saturatedFat: totalSatF, polyunsaturatedFat: totalPolyF, monounsaturatedFat: totalMonoF, fiber: totalFib, calcium: totalCa, iron: totalFe, potassium: totalK, sodium: totalNa, vitaminA: totalVa, vitaminC: totalVc, vitaminD: totalVd, vitaminB12: totalVb12, folate: totalFol)

        if totalServings > 0 {
            nutritionPerServing = RecipeNutrition(
                calories: totalCals / totalServings, protein: totalP / totalServings, carbs: totalC / totalServings, fats: totalF / totalServings,
                saturatedFat: totalSatF / totalServings, polyunsaturatedFat: totalPolyF / totalServings, monounsaturatedFat: totalMonoF / totalServings, fiber: totalFib / totalServings,
                calcium: totalCa / totalServings, iron: totalFe / totalServings, potassium: totalK / totalServings, sodium: totalNa / totalServings,
                vitaminA: totalVa / totalServings, vitaminC: totalVc / totalServings, vitaminD: totalVd / totalServings,
                vitaminB12: totalVb12 / totalServings, folate: totalFol / totalServings
            )
        } else {
            nutritionPerServing = RecipeNutrition()
        }
        updatedAt = Timestamp(date: Date())
    }
}


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

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool { lhs.id == rhs.id }
    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fats, saturatedFat, polyunsaturatedFat, monounsaturatedFat, fiber, servingSize, servingWeight, timestamp, calcium, iron, potassium, sodium, vitaminA, vitaminC, vitaminD, vitaminB12, folate, magnesium, phosphorus, zinc, copper, manganese, selenium, vitaminB1, vitaminB2, vitaminB3, vitaminB5, vitaminB6, vitaminE, vitaminK
    }
}
struct Meal: Codable, Identifiable, Equatable { var id: String = UUID().uuidString; var name: String; var foodItems: [FoodItem]; static func == (lhs: Meal, rhs: Meal) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name && lhs.foodItems == rhs.foodItems } }
struct WaterTracker: Codable, Equatable { var totalOunces: Double; var goalOunces: Double; var date: Date; init(totalOunces: Double, goalOunces: Double = 64.0, date: Date) { self.totalOunces = totalOunces; self.goalOunces = goalOunces; self.date = date } }
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
            case id
            case date
            case meals
            case totalCaloriesOverride
            case waterTracker
            case exercises
            case journalEntries
        }
}

enum CalorieGoalMethod: String, CaseIterable, Identifiable, Codable { case dynamicTDEE = "Dynamic (TDEE + Activity)"; case mifflinWithActivity = "Standard (Mifflin + Activity Level)"; var id: String { self.rawValue } }
struct CommunityPost: Identifiable, Codable { @DocumentID var id: String?; let author: String; let content: String; var likes: Int = 0; var isLikedByCurrentUser: Bool = false; var reactions: [String: Int] = [:]; var comments: [Comment] = []; var timestamp: Date = Date(); var groupID: String; struct Comment: Identifiable, Codable { let id: String = UUID().uuidString; let author: String; let content: String; var replies: [Reply] = []; struct Reply: Identifiable, Codable { let id: String = UUID().uuidString; let author: String; let content: String } }; }
struct CommunityGroup: Identifiable, Codable { @DocumentID var id: String?; var name: String; var description: String; var creatorID: String; var isPreset: Bool = false }
struct GroupMembership: Codable { var groupID: String; var userID: String; var joinedAt: Timestamp = Timestamp(date: Date()) }

enum AchievementCriteriaType: String, Codable {
    case loggingStreak, goalHitCount, calorieGoalHitCount, macroGoalHitCount, waterGoalHitCount, weightChange, targetWeightReached, featureUsed, barcodeScanUsed, imageScanUsed, aiRecipeLogged, workoutsLogged, recipesCreated
}

struct AchievementDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let criteriaType: AchievementCriteriaType
    let criteriaValue: Double
    let pointsValue: Int
    let secret: Bool = false
}

struct JournalEmojiMapper {
    static func getEmoji(for category: String) -> String {
        switch category.lowercased() {
        case "recovery":
            return "🧊" // Ice bath, recovery
        case "mindfulness":
            return "🧘" // Meditation, yoga
        case "flexibility":
            return "🙆" // Stretching, flexibility
        case "other":
            return "📝" // Generic note
        default:
            return "📝"
        }
    }
}

struct Nutrition: Codable, Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fats: Double
    var saturatedFat: Double?
    var polyunsaturatedFat: Double?
    var monounsaturatedFat: Double?
    var fiber: Double?
    var calcium: Double?
    var iron: Double?
    var potassium: Double?
    var sodium: Double?
    var vitaminA: Double?
    var vitaminC: Double?
    var vitaminD: Double?
    var vitaminB12: Double?
    var folate: Double?
    
    static var zero: Nutrition {
        Nutrition(calories: 0, protein: 0, carbs: 0, fats: 0)
    }
}

struct Recipe: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    let name: String
    let ingredients: [String]
    let instructions: [String]
    let nutrition: Nutrition
}

struct UserAchievementStatus: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var achievementID: String
    var isUnlocked: Bool = false
    var unlockedDate: Date? = nil
    var currentProgress: Double = 0.0
    var lastProgressUpdate: Date? = nil
    
    static func == (lhs: UserAchievementStatus, rhs: UserAchievementStatus) -> Bool {
        lhs.achievementID == rhs.achievementID &&
        lhs.isUnlocked == rhs.isUnlocked &&
        lhs.unlockedDate == rhs.unlockedDate &&
        lhs.currentProgress == rhs.currentProgress &&
        lhs.lastProgressUpdate == rhs.lastProgressUpdate
    }
}
struct CustomCorners: Shape { var corners: UIRectCorner; var radius: CGFloat; func path(in rect: CGRect) -> Path { let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)); return Path(path.cgPath) } }




struct FoodEmojiMapper { static let foodEmojiMap: [String: String] = ["hotdog":"🌭","hot dog":"🌭","burger":"🍔","hamburger":"🍔","cheeseburger":"🍔","pizza":"🍕","taco":"🌮","burrito":"🌯","fries":"🍟","sandwich":"🥪","wrap":"🌯","nachos":"🌮","steak":"🥩","chicken":"🍗","fish":"🐟","shrimp":"🍤","prawn":"🍤","egg":"🥚","eggs":"🥚","bacon":"🥓","sausage":"🌭","ham":"🥓","pork":"🥓","beef":"🥩","lamb":"🍖","turkey":"🍗","oyster":"🐚","caviar":"🐟","rice":"🍚","pasta":"🍝","spaghetti":"🍝","ravioli":"🍝","bread":"🍞","toast":"🍞","noodles":"🍜","ramen":"🍜","pho":"🍜","pad thai":"🍜","bagel":"🥯","croissant":"🥐","pretzel":"🥨","bun":"🥐","roll":"🥐","apple":"🍎","banana":"🍌","orange":"🍊","grape":"🍇","strawberry":"🍓","watermelon":"🍉","pear":"🍐","cherry":"🍒","mango":"🥭","pineapple":"🍍","peach":"🍑","kiwi":"🥝","lemon":"🍋","lime":"🍋","blueberry":"🫐","raspberry":"🫐","carrot":"🥕","broccoli":"🥦","tomato":"🍅","potato":"🥔","corn":"🌽","lettuce":"🥬","cucumber":"🥒","onion":"🧅","garlic":"🧄","pepper":"🌶️","mushroom":"🍄","spinach":"🥬","cabbage":"🥬","zucchini":"🥒","eggplant":"🍆","cake":"🍰","carrot cake":"🍰","chocolate cake":"🍰","red velvet cake":"🍰","cheesecake":"🍰","cookie":"🍪","ice cream":"🍦","donut":"🍩","chocolate":"🍫","candy":"🍬","cupcake":"🧁","pie":"🥧","apple pie":"🥧","pudding":"🍮","bread pudding":"🍮","panna cotta":"🍮","waffle":"🧇","pancake":"🥞","coffee":"☕","tea":"🍵","juice":"🍹","beer":"🍺","wine":"🍷","milk":"🥛","cocktail":"🍸","soda":"🥤","water":"💧","sushi":"🍣","sashimi":"🍣","sushi roll":"🍣","curry":"🍛","chicken curry":"🍛","dumpling":"🥟","gyoza":"🥟","samosa":"🥟","egg roll":"🥟","falafel":"🧆","paella":"🍲","tempura":"🍤","cheese":"🧀","grilled cheese":"🧀","peanut":"🥜","popcorn":"🍿","lollipop":"🍭","honey":"🍯","jam":"🍇","butter":"🧈","oil":"🛢️","soup":"🥣","miso soup":"🥣","french onion soup":"🥣","hot and sour soup":"🥣","clam chowder":"🥣","lobster bisque":"🥣","salad":"🥗","greek salad":"🥗","caesar salad":"🥗","caprese salad":"🥗","beet salad":"🥗","fruit salad":"🥗","stew":"🍲","casserole":"🍲","quesadilla":"🌮"]; static func getEmoji(for foodName: String) -> String { let l = foodName.lowercased(); if let e = foodEmojiMap[l] { return e }; if let c = foodEmojiMap.first(where: { l.contains($0.key) }) { return c.value }; let w = l.split(separator: " ").map { String($0) }; if let f = w.first, let m = foodEmojiMap[f] { return m }; return "🍽️" } }

struct ExerciseEmojiMapper {
    static let exerciseEmojiMap: [String: String] = [
        "running": "🏃", "run": "🏃",
        "walking": "🚶", "walk": "🚶", "power walk": "🚶‍♀️",
        "jogging": "🏃‍♂️",
        "cycling": "🚴", "bike": "🚴", "stationary bike": "🚴‍♀️",
        "swimming": "🏊", "swim": "🏊‍♀️",
        "hiking": "🥾",
        "jumping jacks": "🤸",
        "jump rope": "🤸‍♀️",
        "stair climbing": "🧗", "stairs": "🧗‍♀️",
        "elliptical": "🚲",
        "rowing": "🚣",
        "hiit": "⏱️", "high intensity interval training": "⏱️",
        "strength training": "🏋️", "weights": "🏋️‍♀️", "weight lifting": "🏋️",
        "bodyweight exercises": "🤸‍♂️",
        "push-ups": "💪",
        "pull-ups": "💪",
        "squats": "🦵",
        "lunges": "🦵",
        "deadlifts": "🏋️",
        "bench press": "🏋️",
        "kettlebell": "💣",
        "crossfit": "🏋️‍♂️",
        "calisthenics": "🤸",
        "basketball": "🏀",
        "soccer": "⚽", "football": "⚽",
        "american football": "🏈",
        "tennis": "🎾",
        "volleyball": "🏐",
        "baseball": "⚾",
        "golf": "⛳",
        "skiing": "⛷️",
        "snowboarding": "🏂",
        "boxing": "🥊",
        "martial arts": "🥋",
        "yoga": "🧘", "yoga flow": "🧘‍♀️",
        "pilates": "🧘‍♂️",
        "dancing": "💃", "dance": "🕺",
        "stretching": "🙆",
        "meditation": "🧘",
        "gardening": "🧑‍🌾",
        "cleaning": "🧹"
    ]

    static func getEmoji(for exerciseName: String) -> String {
        let lowercasedName = exerciseName.lowercased()
        if let emoji = exerciseEmojiMap[lowercasedName] {
            return emoji
        }
        for (key, emoji) in exerciseEmojiMap {
            if lowercasedName.contains(key) {
                return emoji
            }
        }
        return "🤸"
    }
}

struct ActionButtonLabel: View { let title: String; let icon: String; @Environment(\.colorScheme) var colorScheme; var body: some View { HStack { Image(systemName: icon).foregroundColor(Color.accentColor).frame(width: 24, height: 24); Text(title).foregroundColor(colorScheme == .dark ? .white : .black).font(.headline); Spacer() }.padding().background(colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(red: 245/255, green: 245/255, blue: 245/255).opacity(0.5)).cornerRadius(12) } }
