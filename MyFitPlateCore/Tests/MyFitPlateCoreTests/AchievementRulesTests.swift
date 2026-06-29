import XCTest
@testable import MyFitPlateCore

final class AchievementRulesTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_767_225_600)

    func testDefaultDefinitionsAreUniqueAndCoverExpectedMilestones() {
        let definitions = AchievementRules.defaultDefinitions()
        let ids = definitions.map(\.id)

        XCTAssertEqual(definitions.count, 21)
        XCTAssertEqual(Set(ids).count, definitions.count)
        XCTAssertTrue(ids.contains("first_log"))
        XCTAssertTrue(ids.contains("macro_master"))
        XCTAssertTrue(ids.contains("target_reached"))
        XCTAssertTrue(ids.contains("expert_chef"))

        let scanner = definitions.first { $0.id == "scanner_pro" }
        XCTAssertEqual(scanner?.criteriaType, .barcodeScanUsed)
        XCTAssertEqual(scanner?.pointsValue, 20)

        let targetReached = definitions.first { $0.id == "target_reached" }
        XCTAssertEqual(targetReached?.criteriaValue, 1)
        XCTAssertEqual(targetReached?.pointsValue, 100)
    }

    func testLevelCalculationUsesHighestReachedThreshold() {
        XCTAssertEqual(AchievementRules.level(for: -10), 1)
        XCTAssertEqual(AchievementRules.level(for: 0), 1)
        XCTAssertEqual(AchievementRules.level(for: 99), 1)
        XCTAssertEqual(AchievementRules.level(for: 100), 2)
        XCTAssertEqual(AchievementRules.level(for: 249), 2)
        XCTAssertEqual(AchievementRules.level(for: 250), 3)
        XCTAssertEqual(AchievementRules.level(for: 5_000), 7)
        XCTAssertEqual(AchievementRules.level(for: 20_000), 7)
        XCTAssertEqual(AchievementRules.level(for: 50, thresholds: []), 1)
    }

    func testMergedStatusesCreatesDefaultsAndPreservesFetchedProgress() {
        let definitions = AchievementRules.defaultDefinitions()
        let fetched = UserAchievementStatus(
            id: "server-id",
            achievementID: "first_log",
            isUnlocked: true,
            unlockedDate: fixedDate,
            currentProgress: 1,
            lastProgressUpdate: fixedDate
        )

        let statuses = AchievementRules.mergedStatuses(
            definitions: definitions,
            fetchedStatuses: [fetched]
        )

        XCTAssertEqual(statuses.count, definitions.count)
        XCTAssertEqual(statuses["first_log"], fetched)
        XCTAssertEqual(statuses["macro_master"]?.achievementID, "macro_master")
        XCTAssertFalse(statuses["macro_master"]?.isUnlocked ?? true)
    }

    func testShouldCheckRequiresKnownAndLockedAchievement() {
        let definitions = AchievementRules.defaultDefinitions()
        let unlocked = UserAchievementStatus(
            achievementID: "first_log",
            isUnlocked: true,
            currentProgress: 1
        )

        XCTAssertTrue(AchievementRules.shouldCheck("macro_master", definitions: definitions, statuses: [:]))
        XCTAssertFalse(AchievementRules.shouldCheck("missing", definitions: definitions, statuses: [:]))
        XCTAssertFalse(AchievementRules.shouldCheck(
            "first_log",
            definitions: definitions,
            statuses: ["first_log": unlocked]
        ))
    }

    func testUnlockedStatusSetsDatesProgressAndIdentifier() throws {
        let definition = try XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "macro_master" })
        var existing = UserAchievementStatus(achievementID: definition.id)
        existing.currentProgress = 0.5

        let unlocked = try XCTUnwrap(AchievementRules.unlockedStatus(
            existingStatus: existing,
            definition: definition,
            date: fixedDate
        ))

        XCTAssertEqual(unlocked.id, definition.id)
        XCTAssertEqual(unlocked.achievementID, definition.id)
        XCTAssertTrue(unlocked.isUnlocked)
        XCTAssertEqual(unlocked.unlockedDate, fixedDate)
        XCTAssertEqual(unlocked.lastProgressUpdate, fixedDate)
        XCTAssertEqual(unlocked.currentProgress, definition.criteriaValue, accuracy: 0.001)

        XCTAssertNil(AchievementRules.unlockedStatus(
            existingStatus: unlocked,
            definition: definition,
            date: fixedDate
        ))
    }

    func testProgressStatusCapsProgressAndSkipsTinyChanges() throws {
        let definition = try XCTUnwrap(AchievementRules.defaultDefinitions().first { $0.id == "workout_streak_7" })

        XCTAssertNil(AchievementRules.progressStatus(
            existingStatus: nil,
            definition: definition,
            progress: -3,
            date: fixedDate
        ))

        let capped = try XCTUnwrap(AchievementRules.progressStatus(
            existingStatus: nil,
            definition: definition,
            progress: 99,
            date: fixedDate
        ))
        XCTAssertEqual(capped.currentProgress, 7, accuracy: 0.001)
        XCTAssertEqual(capped.lastProgressUpdate, fixedDate)

        XCTAssertNil(AchievementRules.progressStatus(
            existingStatus: capped,
            definition: definition,
            progress: 7.005,
            date: fixedDate
        ))
    }

    func testDailyGoalEvaluationDetectsCalorieMacroProteinAndWaterHits() {
        let log = DailyLog(
            id: "log",
            date: fixedDate,
            meals: [
                Meal(name: "Dinner", foodItems: [
                    FoodItem(
                        id: "food",
                        name: "Balanced Bowl",
                        calories: 2_050,
                        protein: 145,
                        carbs: 260,
                        fats: 67
                    )
                ])
            ],
            waterTracker: WaterTracker(totalOunces: 72, goalOunces: 64, date: fixedDate)
        )

        let evaluation = AchievementRules.evaluateDailyGoals(
            dailyLog: log,
            targets: AchievementRules.DailyGoalTargets(
                calorieGoal: 2_000,
                protein: 150,
                carbs: 250,
                fats: 70
            )
        )

        XCTAssertTrue(evaluation.calorieHit)
        XCTAssertTrue(evaluation.proteinHit)
        XCTAssertTrue(evaluation.macroMasterHit)
        XCTAssertTrue(evaluation.hydrationHit)
    }

    func testDailyGoalEvaluationHandlesMissesAndMissingCalorieGoal() {
        let log = DailyLog(
            id: "log",
            date: fixedDate,
            meals: [
                Meal(name: "Snack", foodItems: [
                    FoodItem(id: "food", name: "Snack", calories: 900, protein: 20, carbs: 120, fats: 40)
                ])
            ],
            waterTracker: WaterTracker(totalOunces: 20, goalOunces: 64, date: fixedDate)
        )

        let evaluation = AchievementRules.evaluateDailyGoals(
            dailyLog: log,
            targets: AchievementRules.DailyGoalTargets(
                calorieGoal: nil,
                protein: 150,
                carbs: 250,
                fats: 70
            )
        )

        XCTAssertFalse(evaluation.calorieHit)
        XCTAssertFalse(evaluation.proteinHit)
        XCTAssertFalse(evaluation.macroMasterHit)
        XCTAssertFalse(evaluation.hydrationHit)
    }

    func testWeightAndChallengeRules() {
        XCTAssertEqual(
            AchievementRules.weightChangeProgress(initialWeight: 200, currentWeight: 194.75),
            5.25,
            accuracy: 0.001
        )
        XCTAssertTrue(AchievementRules.hasReachedTargetWeight(currentWeight: 180.4, targetWeight: 180))
        XCTAssertFalse(AchievementRules.hasReachedTargetWeight(currentWeight: 181, targetWeight: 180))

        let challenge = Challenge(
            title: "Protein Power",
            description: "Meet protein 4 times.",
            type: .proteinGoalHit,
            goal: 4,
            progress: 3,
            pointsValue: 75,
            expiresAt: fixedDate
        )

        let incomplete = AchievementRules.challengeAfterAddingProgress(challenge, amount: 0.5)
        XCTAssertEqual(incomplete.progress, 3.5, accuracy: 0.001)
        XCTAssertFalse(incomplete.isCompleted)

        let complete = AchievementRules.challengeAfterAddingProgress(challenge, amount: 1)
        XCTAssertEqual(complete.progress, 4, accuracy: 0.001)
        XCTAssertTrue(complete.isCompleted)
    }

    func testPotentialWeeklyChallengesGeneratesExpectedChallenges() {
        let challenges = AchievementRules.potentialWeeklyChallenges(currentDate: fixedDate)
        XCTAssertEqual(challenges.count, 8)
        XCTAssertTrue(challenges.contains { $0.title == "Workout Warrior" && $0.type == .workoutLogged })
        XCTAssertTrue(challenges.contains { $0.title == "Protein Power" && $0.type == .proteinGoalHit })
        
        let weekFromNow = fixedDate.addingTimeInterval(7 * 24 * 60 * 60)
        for challenge in challenges {
            XCTAssertEqual(challenge.expiresAt, weekFromNow)
        }
    }

    func testChefAchievementIDs() {
        let ids = AchievementRules.chefAchievementIDs
        XCTAssertEqual(ids, ["novice_chef", "apprentice_chef", "adept_chef", "expert_chef"])
    }

    func testWorkoutAchievementIDs() {
        let ids = AchievementRules.workoutAchievementIDs
        XCTAssertEqual(ids, ["first_workout", "workout_streak_3", "workout_streak_7", "workout_streak_15"])
    }
}
