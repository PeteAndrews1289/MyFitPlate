import Foundation
import Combine
import FirebaseAuth
import HealthKit

struct UserInsight: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var category: InsightCategory
    var priority: Int = 0
    var lastShownDate: Date? = nil
    var relatedData: [String: String]?

    enum InsightCategory: String, Codable {
        case nutritionGeneral, hydration, macroBalance, microNutrient, mealTiming, consistency, postWorkout, foodVariety, positiveReinforcement, sugarAwareness, fiberIntake, saturatedFat, smartSuggestion, sleep
    }
}

@MainActor
class InsightsService: ObservableObject {
    @Published var currentInsights: [UserInsight] = []
    @Published var smartSuggestion: UserInsight? = nil
    @Published var isLoadingInsights: Bool = false

    private let dailyLogService: DailyLogService
    private let goalSettings: GoalSettings
    private weak var healthKitViewModel: HealthKitViewModel?
    private var analysisTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()

    init(dailyLogService: DailyLogService, goalSettings: GoalSettings, healthKitViewModel: HealthKitViewModel) {
        self.dailyLogService = dailyLogService
        self.goalSettings = goalSettings
        self.healthKitViewModel = healthKitViewModel
        
        healthKitViewModel.$sleepSamples
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.generateAndFetchInsights()
            }
            .store(in: &cancellables)
    }

    func generateDailySmartInsight() {
        guard let log = dailyLogService.currentDailyLog,
              Calendar.current.isDateInToday(log.date) else {
            self.smartSuggestion = UserInsight(
                title: "Welcome!",
                message: "Start logging your meals and workouts to receive personalized tips here.",
                category: .smartSuggestion, priority: 1)
            return
        }

        let hour = Calendar.current.component(.hour, from: Date())
        let loggedFoods = log.meals.flatMap { $0.foodItems }

        if let lastWorkout = log.exercises?.last(where: { $0.caloriesBurned > 150 }) {
            let workoutEndTime = lastWorkout.date.addingTimeInterval(Double(lastWorkout.durationMinutes ?? 30) * 60)
            if Date().timeIntervalSince(workoutEndTime) < (2 * 60 * 60) {
                self.smartSuggestion = UserInsight(title: "Post-Workout Refuel", message: "Great work on your recent \(lastWorkout.name.lowercased())! A snack with protein and carbs can help with recovery.", category: .smartSuggestion, priority: 100)
                return
            }
        }

        if hour >= 19 {
            let proteinRemaining = (goalSettings.protein) - log.totalMacros().protein
            if proteinRemaining > 15 && proteinRemaining < 50 {
                self.smartSuggestion = UserInsight(title: "Hit Your Protein Goal", message: String(format: "You're just %.0fg of protein away from your goal. A Greek yogurt or protein shake could be a great choice!", proteinRemaining), category: .smartSuggestion, priority: 90)
                return
            }
        }
        
        if hour >= 12 && hour < 15 && !log.meals.contains(where: { $0.name == "Lunch" }) {
            self.smartSuggestion = UserInsight(title: "Lunch Time!", message: "Don't forget to log your lunch to stay on track with your goals for the day.", category: .smartSuggestion, priority: 80)
            return
        }
        
        if hour >= 18 && hour < 21 && !log.meals.contains(where: { $0.name == "Dinner" }) {
            self.smartSuggestion = UserInsight(title: "Time for Dinner?", message: "Remember to log your dinner to get a complete picture of your day's nutrition.", category: .smartSuggestion, priority: 80)
            return
        }

        if !loggedFoods.isEmpty {
            self.smartSuggestion = UserInsight(title: "Keep Up the Great Work!", message: "Consistency is the key to reaching your goals. You're doing great today!", category: .smartSuggestion, priority: 5)
            return
        }
        
        self.smartSuggestion = UserInsight(title: "Have a Great Day!", message: "Log your first meal or workout to get personalized tips and insights.", category: .smartSuggestion, priority: 1)
    }

    func generateAndFetchInsights(forLastDays days: Int = 7, maxInsights: Int = 5) {
        guard let userID = Auth.auth().currentUser?.uid else {
            self.currentInsights = []
            return
        }
        
        let sleepData = self.healthKitViewModel?.sleepSamples ?? []

        isLoadingInsights = true
        analysisTask?.cancel()

        analysisTask = Task {
            let endDate = Calendar.current.startOfDay(for: Date())
            guard let startDate = Calendar.current.date(byAdding: .day, value: -(days - 1), to: endDate) else {
                handleInsightsError(message: "Could not calculate date range for insights.")
                return
            }

            let result = await fetchLogsForAnalysis(userID: userID, startDate: startDate, endDate: endDate)
            
            if Task.isCancelled {
                handleInsightsError(message: nil, isLoading: false)
                return
            }
            
            var potentialInsights: [UserInsight] = []
            
            if let insight = checkSleepDuration(sleepSamples: sleepData) { potentialInsights.append(insight) }
            if let insight = checkSleepConsistency(sleepSamples: sleepData) { potentialInsights.append(insight) }

            switch result {
            case .success(let logs):
                if !logs.isEmpty {
                    if let insight = checkForHighSodium(logs: logs, goals: goalSettings) { potentialInsights.append(insight) }
                    if let insight = checkForLowWaterIntake(logs: logs, goals: goalSettings) { potentialInsights.append(insight) }
                    if let insight = checkForConsistentCalorieDeficit(logs: logs, goals: goalSettings, daysThreshold: 3) { potentialInsights.append(insight) }
                    if let insight = checkForConsistentCalorieSurplus(logs: logs, goals: goalSettings, daysThreshold: 3) { potentialInsights.append(insight) }
                    if let insight = checkProteinIntake(logs: logs, goals: goalSettings) { potentialInsights.append(insight) }
                    if let insight = checkFiberIntake(logs: logs) { potentialInsights.append(insight) }
                    if let insight = checkSaturatedFatIntake(logs: logs) { potentialInsights.append(insight) }
                    if let insight = checkForSkippedMeals(logs: logs, mealName: "Breakfast") { potentialInsights.append(insight) }
                    if let insight = checkMealTimingConsistency(logs: logs) { potentialInsights.append(insight) }
                    if let insight = checkForWeekendVariations(logs: logs, goals: goalSettings) { potentialInsights.append(insight) }
                    if let insight = checkForLowFoodVariety(logs: logs, days: days) { potentialInsights.append(insight) }
                    if let insight = checkExerciseConsistency(logs: logs, days: days) { potentialInsights.append(insight) }
                    if let insight = checkMealBalance(logs: logs, mealName: "Lunch") { potentialInsights.append(insight) }
                    if let insight = checkIronAndVitaminCSynergy(logs: logs, goals: goalSettings) { potentialInsights.append(insight) }
                    if let insight = checkCalciumAndVitaminDSynergy(logs: logs, goals: goalSettings) { potentialInsights.append(insight) }
                    if let insight = checkPostWorkoutNutrition(logs: logs) { potentialInsights.append(insight) }
                    if let insight = checkFrequentSugaryFoods(logs: logs) { potentialInsights.append(insight) }
                    if let insight = checkCalorieGoalAchievement(logs: logs, goals: goalSettings, daysThreshold: 3) { potentialInsights.append(insight) }
                }

                var finalInsights = Array(potentialInsights.sorted(by: { $0.priority > $1.priority }).prefix(maxInsights))

                if finalInsights.isEmpty {
                    finalInsights.append(
                        UserInsight(
                            title: "More Data Needed",
                            message: "Log consistently for a few more days to unlock your personalized weekly insights!",
                            category: .nutritionGeneral,
                            priority: 1
                        )
                    )
                }
                
                handleInsightsError(message: nil, insights: finalInsights, isLoading: false)

            case .failure(let error):
                handleInsightsError(message: "Could not analyze data: \(error.localizedDescription)", isLoading: false)
            }
        }
    }
    
    private func handleInsightsError(message: String?, insights: [UserInsight]? = nil, isLoading: Bool? = nil) {
        if let isLoading = isLoading { self.isLoadingInsights = isLoading }
        if let message = message { self.currentInsights = [UserInsight(title: "Insight Error", message: message, category: .nutritionGeneral)] }
        if let insights = insights { self.currentInsights = insights }
    }

    private func fetchLogsForAnalysis(userID: String, startDate: Date, endDate: Date) async -> Result<[DailyLog], Error> {
        return await withCheckedContinuation { continuation in
            dailyLogService.fetchDailyHistory(for: userID, startDate: startDate, endDate: endDate) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func checkSleepDuration(sleepSamples: [HKCategorySample]) -> UserInsight? {
        guard sleepSamples.count > 3 else { return nil }
        let asleepStates: [HKCategoryValueSleepAnalysis] = [.asleepCore, .asleepDeep, .asleepREM, .asleep]
        let asleepRawValues = Set(asleepStates.map { $0.rawValue })
        let totalAsleep = sleepSamples.filter { asleepRawValues.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let numberOfNights = Set(sleepSamples.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        guard numberOfNights > 0 else { return nil }
        
        let averageSleep = totalAsleep / Double(numberOfNights)
        let averageSleepHours = averageSleep / 3600
        
        if averageSleepHours > 0.1 && averageSleepHours < 6.5 {
            return UserInsight(
                title: "Prioritize Your Sleep",
                message: String(format: "Your average sleep time of %.1f hours is a bit low. Aiming for 7-9 hours can significantly boost energy, mood, and recovery.", averageSleepHours),
                category: .sleep,
                priority: 10
            )
        }
        return nil
    }
    
    private func checkSleepConsistency(sleepSamples: [HKCategorySample]) -> UserInsight? {
        guard sleepSamples.count > 3 else { return nil }
        let calendar = Calendar.current
        let bedtimes = sleepSamples.compactMap { sample -> Date? in
            return sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue ? sample.startDate : nil
        }
        let bedtimeInMinutes = bedtimes.map { Double(calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0)) }
        guard bedtimeInMinutes.count > 1 else { return nil }
        
        let mean = bedtimeInMinutes.reduce(0, +) / Double(bedtimeInMinutes.count)
        let variance = bedtimeInMinutes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(bedtimeInMinutes.count)
        let stdDev = sqrt(variance)

        if stdDev > 75 {
            return UserInsight(
                title: "Consistent Bedtime, Better Rest",
                message: "Your bedtimes have varied quite a bit this week. A more regular sleep schedule, even on weekends, can improve your sleep quality.",
                category: .sleep,
                priority: 8
            )
        }
        return nil
    }
    
    private func checkFiberIntake(logs: [DailyLog]) -> UserInsight? {
        let logsWithFood = logs.filter { !$0.meals.isEmpty }
        guard logsWithFood.count >= 3 else { return nil }
        let averageFiber = logsWithFood.reduce(0.0) { $0 + $1.totalFiber() } / Double(logsWithFood.count)
        let fiberGoal: Double = 28.0

        if averageFiber < (fiberGoal * 0.5) {
            return UserInsight(
                title: "Boost Your Fiber",
                message: String(format: "Your average daily fiber intake (%.1fg) is lower than the recommended 28g. Increasing fiber with foods like whole grains, beans, fruits, and vegetables can improve digestive health and help you feel full.", averageFiber),
                category: .fiberIntake,
                priority: 7,
                relatedData: [
                    "nutrient": "Fiber",
                    "average": String(format: "%.1fg", averageFiber),
                    "goal": "\(Int(fiberGoal))g",
                    "sourceName": "U.S. Food & Drug Administration",
                    "sourceURL": "https://www.fda.gov/food/nutrition-facts-label/daily-value-nutrition-and-supplement-facts-labels"
                ]
            )
        }
        return nil
    }

    private func checkSaturatedFatIntake(logs: [DailyLog]) -> UserInsight? {
        let logsWithFood = logs.filter { !$0.meals.isEmpty }
        guard logsWithFood.count >= 3 else { return nil }
        let totalSatFatGrams = logsWithFood.reduce(0.0) { $0 + $1.totalSaturatedFat() }
        let totalCalories = logsWithFood.reduce(0.0) { $0 + $1.totalCalories() }
        
        guard totalCalories > 0 else { return nil }
        
        let percentageOfCalories = (totalSatFatGrams * 9 / totalCalories) * 100

        if percentageOfCalories > 7.0 {
            return UserInsight(
                title: "Saturated Fat Awareness",
                message: String(format: "On average, about %.0f%% of your calories came from saturated fat. The American Heart Association recommends aiming for 5-6%%. Consider swapping some sources for healthier unsaturated fats like those in avocado, nuts, and olive oil.", percentageOfCalories),
                category: .saturatedFat,
                priority: 8,
                relatedData: [
                    "nutrient": "Saturated Fat",
                    "percentage": String(format: "%.0f%%", percentageOfCalories),
                    "recommendation": "5-6%",
                    "sourceName": "American Heart Association",
                    "sourceURL": "https://www.heart.org/en/healthy-living/healthy-eating/eat-smart/fats/saturated-fat"
                ]
            )
        }
        return nil
    }
    
    private func checkForSkippedMeals(logs: [DailyLog], mealName: String) -> UserInsight? {
        guard logs.count >= 4 else { return nil }
        let mealNameLowercased = mealName.lowercased()
        let skippedCount = logs.filter { log in
            !log.meals.contains { $0.name.lowercased() == mealNameLowercased }
        }.count
        
        if skippedCount >= 3 {
            return UserInsight(
                title: "Consistent Meal Times",
                message: "We've noticed you've skipped \(mealName) a few times this week. Studies suggest that eating regular meals can help regulate metabolism and maintain energy levels throughout the day.",
                category: .mealTiming,
                priority: 5,
                relatedData: [
                    "meal": mealName,
                    "skippedDays": "\(skippedCount)",
                    "sourceName": "Int J Environ Res Public Health. 2021",
                    "sourceURL": "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8538637/"
                ]
            )
        }
        return nil
    }
    
    private func checkCalciumAndVitaminDSynergy(logs: [DailyLog], goals: GoalSettings) -> UserInsight? {
        guard let calciumGoal = goals.calciumGoal, calciumGoal > 0,
              let vitDGoal = goals.vitaminDGoal, vitDGoal > 0,
              logs.count >= 3 else { return nil }
        
        let avgCalcium = logs.reduce(0.0) { $0 + $1.totalMicronutrients().calcium } / Double(logs.count)
        let avgVitD = logs.reduce(0.0) { $0 + $1.totalMicronutrients().vitaminD } / Double(logs.count)

        if avgCalcium < calciumGoal * 0.7 && avgVitD < vitDGoal * 0.7 {
            return UserInsight(
                title: "Calcium and Vitamin D Team-Up",
                message: "Your intake for both Calcium and Vitamin D appears to be on the lower side. These nutrients work together - Vitamin D is essential for your body to absorb calcium effectively. Consider foods fortified with both, or sunlight for Vitamin D!",
                category: .microNutrient,
                priority: 7,
                relatedData: [
                    "nutrient1": "Calcium", "nutrient2": "Vitamin D",
                    "sourceName": "NIH Office of Dietary Supplements",
                    "sourceURL": "https://ods.od.nih.gov/factsheets/Calcium-Consumer/"
                ]
            )
        }
        return nil
    }

    private func checkForHighSodium(logs: [DailyLog], goals: GoalSettings) -> UserInsight? {
        guard let sodiumGoal = goals.sodiumGoal, sodiumGoal > 0, !logs.isEmpty else { return nil }
        let daysWithSodium = logs.filter { $0.totalMicronutrients().sodium > 0 }
        guard daysWithSodium.count >= logs.count / 2 && daysWithSodium.count >= 2 else { return nil }
        let totalSodium = daysWithSodium.reduce(0.0) { $0 + $1.totalMicronutrients().sodium }
        let averageSodium = totalSodium / Double(daysWithSodium.count)
        if averageSodium > sodiumGoal * 1.15 {
            return UserInsight(title: "Sodium Intake Watch", message: String(format: "Your average sodium intake (%.0fmg) has been about 15%% higher than your goal (%.0fmg). Consider checking labels on processed foods, restaurant meals, and sauces.", averageSodium, sodiumGoal), category: .microNutrient, priority: 7, relatedData: ["nutrient": "Sodium", "average": String(format: "%.0fmg", averageSodium), "goal": String(format: "%.0fmg", sodiumGoal)])
        }
        return nil
    }

    private func checkForLowWaterIntake(logs: [DailyLog], goals: GoalSettings) -> UserInsight? {
        let daysWithWaterLog = logs.filter { $0.waterTracker != nil && $0.waterTracker!.goalOunces > 0 }
        guard daysWithWaterLog.count >= 3 else { return nil }
        var consistentlyLowCount = 0
        for log in daysWithWaterLog {
            if let tracker = log.waterTracker, tracker.totalOunces < (tracker.goalOunces * 0.8) {
                consistentlyLowCount += 1
            }
        }
        if consistentlyLowCount >= daysWithWaterLog.count / 2 && consistentlyLowCount >= 2 {
            return UserInsight(title: "Boost Your Hydration", message: "Staying hydrated is key for energy and health! It looks like you're sometimes a bit below your water goal. Keeping a water bottle handy can be a great reminder.", category: .hydration, priority: 8)
        }
        return nil
    }
    
    private func checkForConsistentCalorieDeficit(logs: [DailyLog], goals: GoalSettings, daysThreshold: Int) -> UserInsight? {
        guard let calorieGoal = goals.calories, calorieGoal > 0, logs.count >= daysThreshold else { return nil }
        var deficitDays = 0; var averageDeficitAmount = 0.0; var relevantLogs: [DailyLog] = []
        for log in logs.suffix(daysThreshold * 2) {
            if log.totalCalories() < calorieGoal * 0.85 {
                deficitDays += 1; averageDeficitAmount += (calorieGoal - log.totalCalories()); relevantLogs.append(log)
                if deficitDays >= daysThreshold { break }
            } else {
                deficitDays = 0; averageDeficitAmount = 0.0; relevantLogs = []
            }
        }
        if deficitDays >= daysThreshold && goals.goal.lowercased() != "lose" {
             averageDeficitAmount /= Double(deficitDays)
            return UserInsight(title: "Fueling Your Body", message: String(format: "Noticed your calorie intake has been about %.0f calories below your target for the last %d logged days. Ensure you're eating enough to support your energy and goals!", averageDeficitAmount, deficitDays), category: .nutritionGeneral, priority: 9)
        }
        return nil
    }
    
    private func checkForConsistentCalorieSurplus(logs: [DailyLog], goals: GoalSettings, daysThreshold: Int) -> UserInsight? {
        guard let calorieGoal = goals.calories, calorieGoal > 0, logs.count >= daysThreshold else { return nil }
        var surplusDays = 0; var averageSurplusAmount = 0.0; var relevantLogs: [DailyLog] = []
        for log in logs.suffix(daysThreshold * 2) {
            if log.totalCalories() > calorieGoal * 1.15 {
                surplusDays += 1; averageSurplusAmount += (log.totalCalories() - calorieGoal); relevantLogs.append(log)
                if surplusDays >= daysThreshold { break }
            } else {
                surplusDays = 0; averageSurplusAmount = 0.0; relevantLogs = []
            }
        }
        if surplusDays >= daysThreshold && goals.goal.lowercased() != "gain" {
            averageSurplusAmount /= Double(surplusDays)
            return UserInsight(title: "Mindful Portions", message: String(format: "It looks like your calorie intake has been about %.0f calories over your target for the past %d logged days. Focusing on portion sizes might be helpful.", averageSurplusAmount, surplusDays), category: .nutritionGeneral, priority: 9)
        }
        return nil
    }

    private func checkProteinIntake(logs: [DailyLog], goals: GoalSettings) -> UserInsight? {
        guard goals.protein > 0, logs.count >= 3 else { return nil }
        let averageProtein = logs.reduce(0.0) { $0 + $1.totalMacros().protein } / Double(logs.count)
        let proteinGoal = goals.protein
        if averageProtein < proteinGoal * 0.8 {
            return UserInsight( title: "Boost Your Protein", message: String(format: "Your average protein intake (%.0fg) is a bit below your goal of %.0fg. Protein helps with muscle repair and satiety. Consider adding sources like chicken, beans, tofu, or Greek yogurt.", averageProtein, proteinGoal), category: .macroBalance, priority: 7, relatedData: ["nutrient": "Protein", "average": String(format: "%.0fg", averageProtein), "goal": String(format: "%.0fg", proteinGoal)] )
        } else if averageProtein > proteinGoal * 1.5 && logs.count >= 5 {
             return UserInsight( title: "Protein Intake Note", message: String(format: "Your average protein intake (%.0fg) is noticeably above your goal of %.0fg. While protein is important, ensure a balanced intake of all macros.", averageProtein, proteinGoal), category: .macroBalance, priority: 4, relatedData: ["nutrient": "Protein", "average": String(format: "%.0fg", averageProtein), "goal": String(format: "%.0fg", proteinGoal)] )
        }
        return nil
    }

    private func checkMealTimingConsistency(logs: [DailyLog]) -> UserInsight? {
        guard logs.count >= 5 else { return nil }
        var breakfastTimes: [Int] = []
        for log in logs {
            if let breakfast = log.meals.first(where: { $0.name.lowercased() == "breakfast" }), let firstItemTime = breakfast.foodItems.compactMap({ $0.timestamp }).min() {
                breakfastTimes.append(Calendar.current.component(.hour, from: firstItemTime))
            }
        }
        if breakfastTimes.count >= 3 {
            let timeSpread = (breakfastTimes.max() ?? 0) - (breakfastTimes.min() ?? 0)
            if timeSpread > 3 {
                return UserInsight( title: "Consistent Meal Times?", message: "Having regular meal times can help regulate hunger and energy. We've noticed your breakfast times vary a bit. Could a more consistent schedule help?", category: .mealTiming, priority: 5 )
            }
        }
        return nil
    }

    private func checkForWeekendVariations(logs: [DailyLog], goals: GoalSettings) -> UserInsight? {
        guard let calorieGoal = goals.calories, calorieGoal > 0 else { return nil }
        var weekendCaloriesTotal: Double = 0; var weekendDayCount = 0
        var weekdayCaloriesTotal: Double = 0; var weekdayDayCount = 0
        for log in logs {
            let dayOfWeek = Calendar.current.component(.weekday, from: log.date)
            if dayOfWeek == 1 || dayOfWeek == 7 { weekendCaloriesTotal += log.totalCalories(); weekendDayCount += 1
            } else { weekdayCaloriesTotal += log.totalCalories(); weekdayDayCount += 1 }
        }
        guard weekendDayCount >= 1 && weekdayDayCount >= 2 else { return nil }
        let avgWeekendCals = weekendCaloriesTotal / Double(weekendDayCount)
        let avgWeekdayCals = weekdayCaloriesTotal / Double(weekdayDayCount)
        if avgWeekendCals > calorieGoal * 1.20 && avgWeekendCals > avgWeekdayCals * 1.15 {
            return UserInsight( title: "Weekend Calorie Check-in", message: String(format: "It looks like your calorie intake tends to be higher on weekends (avg %.0f kcal) compared to weekdays (avg %.0f kcal). Being mindful on weekends can help stay on track!", avgWeekendCals, avgWeekdayCals), category: .consistency, priority: 6, relatedData: ["weekendAvg": String(format: "%.0f kcal", avgWeekendCals), "weekdayAvg": String(format: "%.0f kcal", avgWeekdayCals)] )
        }
        return nil
    }
    
    private func checkForLowFoodVariety(logs: [DailyLog], days: Int) -> UserInsight? {
        guard logs.count >= days / 2 && logs.count >= 3 else { return nil }
        var distinctFoodNames: Set<String> = []
        for log in logs {
            for meal in log.meals {
                for item in meal.foodItems {
                    distinctFoodNames.insert(item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        if distinctFoodNames.count < (days * 2) && distinctFoodNames.count > 0 {
            return UserInsight(title: "Spice Up Your Plate!", message: "Eating a variety of foods provides a wider range of nutrients. Try introducing one or two new healthy foods this week!", category: .foodVariety, priority: 4, relatedData: ["distinctItems": "\(distinctFoodNames.count)"])
        }
        return nil
    }
    
    private func checkExerciseConsistency(logs: [DailyLog], days: Int) -> UserInsight? {
        guard logs.count >= days / 2 && logs.count >= 3 else { return nil }
        let daysWithExercise = logs.filter { !($0.exercises?.isEmpty ?? true) }.count
        if Double(daysWithExercise) / Double(logs.count) < 0.4 {
            return UserInsight(title: "Stay Active!", message: "Consistent exercise boosts your metabolism and overall health. We've noticed fewer workout logs recently. Even a short walk or home workout can make a difference!", category: .consistency, priority: 6)
        }
        return nil
    }

    private func checkMealBalance(logs: [DailyLog], mealName: String) -> UserInsight? {
        guard logs.count >= 3 else { return nil }
        var mealProteinCals: Double = 0; var mealCarbCals: Double = 0
        var mealFatCals: Double = 0; var mealTotalCals: Double = 0
        var mealCount = 0

        for log in logs {
            if let meal = log.meals.first(where: { $0.name.lowercased() == mealName.lowercased() }) {
                var currentMealP: Double = 0, currentMealC: Double = 0, currentMealF: Double = 0
                for item in meal.foodItems {
                    currentMealP += item.protein * 4; currentMealC += item.carbs * 4; currentMealF += item.fats * 9
                }
                let currentMealTotal = currentMealP + currentMealC + currentMealF
                if currentMealTotal > 50 {
                    mealProteinCals += currentMealP; mealCarbCals += currentMealC; mealFatCals += currentMealF
                    mealTotalCals += currentMealTotal; mealCount += 1
                }
            }
        }

        guard mealCount >= 2, mealTotalCals > 0 else { return nil }
        let avgPPercent = (mealProteinCals / mealTotalCals) * 100
        let avgCPercent = (mealCarbCals / mealTotalCals) * 100
        let avgFPercent = (mealFatCals / mealTotalCals) * 100

        if avgCPercent > 70 && avgPPercent < 10 {
            return UserInsight(title: "Balancing Your \(mealName)", message: "Your \(mealName.lowercased())s often seem to be high in carbohydrates. Adding a lean protein source could provide more sustained energy and fullness.", category: .macroBalance, priority: 5, relatedData: ["meal": mealName, "avgCarb%": String(format: "%.0f", avgCPercent)])
        } else if avgFPercent > 60 && avgPPercent < 10 {
            return UserInsight(title: "Rethink Your \(mealName) Fats", message: "Your \(mealName.lowercased())s tend to be quite high in fats. While healthy fats are good, balancing with protein and complex carbs is key. Perhaps explore leaner options?", category: .macroBalance, priority: 5, relatedData: ["meal": mealName, "avgFat%": String(format: "%.0f", avgFPercent)])
        }
        return nil
    }
    
    private func checkIronAndVitaminCSynergy(logs: [DailyLog], goals: GoalSettings) -> UserInsight? {
        guard let ironGoal = goals.ironGoal, ironGoal > 0,
              let vitCGoal = goals.vitaminCGoal, vitCGoal > 0,
              logs.count >= 3 else { return nil }

        let avgIron = logs.reduce(0.0) { $0 + ($1.totalMicronutrients().iron) } / Double(logs.count)
        let avgVitC = logs.reduce(0.0) { $0 + ($1.totalMicronutrients().vitaminC) } / Double(logs.count)

        if avgIron < ironGoal * 0.7 && avgVitC < vitCGoal * 0.7 {
            return UserInsight(
                title: "Boost Iron Absorption",
                message: "We've noticed your iron and Vitamin C intake are both a bit on the lower side. Vitamin C helps your body absorb iron more effectively! Try pairing iron-rich foods (like spinach or lentils) with Vitamin C sources (like bell peppers, citrus fruits, or tomatoes).",
                category: .microNutrient,
                priority: 7,
                relatedData: ["nutrient1": "Iron", "nutrient2": "Vitamin C"]
            )
        }
        return nil
    }
    
    private func checkPostWorkoutNutrition(logs: [DailyLog]) -> UserInsight? {
        guard logs.count >= 1 else { return nil }
        var foundWorkoutWithoutPostMeal = false

        for log in logs {
            guard let exercises = log.exercises, !exercises.isEmpty else { continue }
            
            for exercise in exercises where exercise.caloriesBurned > 200 {
                let workoutEndTime = exercise.date.addingTimeInterval(Double(exercise.durationMinutes ?? 30) * 60)
                let twoHoursAfterWorkout = workoutEndTime.addingTimeInterval(2 * 60 * 60)
                
                var postWorkoutMealFound = false
                for meal in log.meals {
                    for item in meal.foodItems {
                        guard let itemTimestamp = item.timestamp else { continue }
                        if itemTimestamp > workoutEndTime && itemTimestamp <= twoHoursAfterWorkout {
                            if item.protein > 10 || item.carbs > 15 {
                                postWorkoutMealFound = true
                                break
                            }
                        }
                    }
                    if postWorkoutMealFound { break }
                }
                if !postWorkoutMealFound {
                    foundWorkoutWithoutPostMeal = true
                    break
                }
            }
            if foundWorkoutWithoutPostMeal { break }
        }

        if foundWorkoutWithoutPostMeal {
            return UserInsight(
                title: "Post-Workout Refuel",
                message: "Great job on your recent workouts! Remember, refueling with some protein and carbs within a couple of hours after a significant session can help with recovery and muscle repair.",
                category: .postWorkout,
                priority: 8
            )
        }
        return nil
    }
    
    private func checkFrequentSugaryFoods(logs: [DailyLog]) -> UserInsight? {
        guard logs.count >= 3 else { return nil }
        let sugaryKeywords = ["soda", "candy", "chocolate bar", "cake", "cookies", "donut", "ice cream", "pastry", "sweet tea", "syrup"]
        var sugaryItemCount = 0
        var distinctSugaryDays = Set<String>()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for log in logs {
            for meal in log.meals {
                for item in meal.foodItems {
                    let itemNameLower = item.name.lowercased()
                    for keyword in sugaryKeywords {
                        if itemNameLower.contains(keyword) {
                            sugaryItemCount += 1
                            distinctSugaryDays.insert(dateFormatter.string(from: log.date))
                            break
                        }
                    }
                }
            }
        }

        if distinctSugaryDays.count >= logs.count / 2 && sugaryItemCount >= logs.count && distinctSugaryDays.count >= 2 {
            return UserInsight(
                title: "Sugar Awareness",
                message: "We've noticed a few items that are often high in added sugars in your logs. While treats are fine in moderation, being mindful of overall sugar intake is beneficial for sustained energy.",
                category: .sugarAwareness,
                priority: 6
            )
        }
        return nil
    }
    
    private func checkCalorieGoalAchievement(logs: [DailyLog], goals: GoalSettings, daysThreshold: Int) -> UserInsight? {
        guard let calorieGoal = goals.calories, calorieGoal > 0, logs.count >= daysThreshold else { return nil }
        
        var daysMetGoal = 0
        for log in logs.suffix(daysThreshold) {
            let calorieIntake = log.totalCalories()
            if calorieIntake >= calorieGoal * 0.9 && calorieIntake <= calorieGoal * 1.1 {
                daysMetGoal += 1
            }
        }
        
        if daysMetGoal >= daysThreshold {
            return UserInsight(
                title: "Great Job on Your Goals!",
                message: "Awesome consistency! You've been hitting your calorie targets for the last \(daysMetGoal) logged days. Keep up the fantastic work!",
                category: .positiveReinforcement,
                priority: 10
            )
        }
        return nil
    }
}
