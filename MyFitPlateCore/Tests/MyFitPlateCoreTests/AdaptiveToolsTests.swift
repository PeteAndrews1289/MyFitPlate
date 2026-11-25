import XCTest
@testable import MyFitPlateCore

final class AdaptiveToolsTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))! }
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    func program() -> WorkoutProgram {
        let exercises = ["Squat", "Press", "Row", "Curl"].map { name in
            RoutineExercise(name: name, sets: (0..<4).map { _ in ExerciseSet(target: "8", reps: 8, weight: 100) }, targetSets: 4)
        }
        let routine = WorkoutRoutine(id: "upper", userID: "u", name: "Upper", dateCreated: today, exercises: exercises)
        return WorkoutProgram(id: "phul", userID: "u", name: "PHUL", routines: [routine], startDate: today,
                              daysOfWeek: [3, 5, 7], currentProgressIndex: 0)
    }
    func meal(_ name: String = "Oats") -> FoodItem { FoodItem(id: name, name: name, calories: 400, protein: 20, carbs: 60, fats: 10, servingWeight: 200) }
    func experiment() throws -> MealExperiment {
        try MealExperimentRules.create(program: program(), routineID: "upper", mealA: meal(), mealB: meal("Toast"),
                                        minutesBefore: 90, startsWithA: true, now: today, calendar: calendar)
    }
    func session(_ id: String = "session", date: Date? = nil) -> WorkoutSessionLog {
        let routine = program().routines[0]
        return WorkoutSessionLog(id: id, date: date ?? today, routineID: routine.id, completedExercises: routine.exercises.map { exercise in
            CompletedExercise(exerciseName: exercise.name, exercise: exercise,
                              sets: exercise.sets.map { _ in CompletedSet(reps: 8, weight: 100, effort: SetEffort(scale: .rir, value: 2)) })
        })
    }

    func testLighterWeekIsTemporaryReviewableAndUndoPreservesProgress() throws {
        let original = program()
        let fingerprint = try PlanFingerprint.make(original)
        let rescue = try WeekRescueRules.preview(program: original, reason: .lighterWeek, workoutDate: today, now: today, calendar: calendar)
        var applied = try WeekRescueRules.applying(rescue, to: original)
        XCTAssertEqual(applied.routine(forSlot: 0)?.exercises[0].sets.count, 3)
        XCTAssertEqual(applied.routine(forSlot: 3)?.exercises[0].sets.count, 4)
        XCTAssertEqual(try PlanFingerprint.make(original), fingerprint)
        XCTAssertEqual(applied.routine(forSlot: 0)?.exercises[0].sets[0].weight, 100)
        applied.currentProgressIndex = 1
        let restored = try WeekRescueRules.undoing(id: rescue.id, in: applied)
        XCTAssertEqual(restored.currentProgressIndex, 1)
        XCTAssertEqual(restored.routine(forSlot: 1)?.exercises[0].sets.count, 4)
        let reloaded = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(applied))
        XCTAssertEqual(reloaded.routine(forSlot: 1)?.exercises[0].sets.count, 3)
    }

    func testRescuePreservesProgramIdentityProgressAndAllFutureGaps() throws {
        var original = program()
        original.currentProgressIndex = 1
        original.skippedIndices = [0]
        let snapshot = try PlanFingerprint.make(original)
        let rescue = try WeekRescueRules.preview(program: original, reason: .missedWorkout, workoutDate: day(4), now: today, calendar: calendar)
        let updated = try WeekRescueRules.applying(rescue, to: original)
        XCTAssertEqual(try PlanFingerprint.make(original), snapshot)
        XCTAssertEqual(updated.id, "phul")
        XCTAssertEqual(updated.currentProgressIndex, 1)
        XCTAssertEqual(updated.skippedIndices, [0])
        XCTAssertEqual(updated.date(forSlot: 1, calendar: calendar), day(4))
        XCTAssertEqual(updated.date(forSlot: 0, calendar: calendar), today)
        for slot in 2..<updated.totalSlots {
            let before = calendar.dateComponents([.day], from: original.date(forSlot: slot - 1, calendar: calendar)!, to: original.date(forSlot: slot, calendar: calendar)!).day
            let after = calendar.dateComponents([.day], from: updated.date(forSlot: slot - 1, calendar: calendar)!, to: updated.date(forSlot: slot, calendar: calendar)!).day
            XCTAssertEqual(before, after)
        }
    }

    func testUndoKeepsLaterProgressAndProgramEdits() throws {
        let base = program()
        let rescue = try WeekRescueRules.preview(program: base, reason: .busyDay, workoutDate: day(1), now: today, calendar: calendar)
        var updated = try WeekRescueRules.applying(rescue, to: base)
        updated.currentProgressIndex = 2
        updated.name = "My PHUL"
        let undone = try WeekRescueRules.undoing(id: rescue.id, in: updated)
        XCTAssertNil(undone.weekRescue)
        XCTAssertEqual(undone.currentProgressIndex, 2)
        XCTAssertEqual(undone.name, "My PHUL")
        XCTAssertThrowsError(try WeekRescueRules.undoing(id: "stale", in: updated))
    }

    func testRescueRejectsStalePreviewAndSecondAdjustment() throws {
        let base = program()
        let rescue = try WeekRescueRules.preview(program: base, reason: .busyDay, workoutDate: day(1), now: today, calendar: calendar)
        var edited = base
        edited.currentProgressIndex = 1
        XCTAssertThrowsError(try WeekRescueRules.applying(rescue, to: edited))
        edited = try WeekRescueRules.applying(rescue, to: base)
        XCTAssertThrowsError(try WeekRescueRules.preview(program: edited, reason: .busyDay, workoutDate: day(2), now: today, calendar: calendar))
    }

    func testShortSessionIsIndependentAndOnlyChangesOneRoutine() throws {
        let base = program()
        let original = try PlanFingerprint.make(base)
        let rescue = try WeekRescueRules.preview(program: base, reason: .lessTime, workoutDate: today, minutes: 20, now: today, calendar: calendar)
        let updated = try WeekRescueRules.applying(rescue, to: base)
        XCTAssertEqual(try PlanFingerprint.make(base), original)
        XCTAssertLessThan(updated.routine(forSlot: 0)!.exercises.count, base.routines[0].exercises.count)
        XCTAssertEqual(updated.routine(forSlot: 0)?.id, base.routines[0].id)
        XCTAssertEqual(try PlanFingerprint.make(updated.routine(forSlot: 1)), try PlanFingerprint.make(base.routines.first))
        XCTAssertLessThanOrEqual(WeekRescueRules.estimatedMinutes(updated.routine(forSlot: 0)!), 20)
    }

    func testShortSessionKeepsWarmupsAndWholeSupersets() throws {
        let base = program()
        base.routines[0].exercises[0].supersetGroupID = "pair"
        base.routines[0].exercises[1].supersetGroupID = "pair"
        base.routines[0].exercises[0].sets.insert(ExerciseSet(isWarmup: true), at: 0)
        let rescue = try WeekRescueRules.preview(program: base, reason: .lessTime, workoutDate: today, minutes: 20, now: today, calendar: calendar)
        let short = try XCTUnwrap(rescue.slots[0].routine)
        XCTAssertTrue(short.exercises[0].sets[0].isWarmup)
        XCTAssertEqual(short.exercises.filter { $0.supersetGroupID == "pair" }.count, 2)
    }

    func testLaterRoutineAndScheduleEditsTakePriorityOverRescue() throws {
        let original = program()
        let rescue = try WeekRescueRules.preview(program: original, reason: .lessTime, workoutDate: today, minutes: 20, now: today, calendar: calendar)
        var changed = try WeekRescueRules.applying(rescue, to: original)
        changed.routines[0].exercises[0].name = "New press"
        XCTAssertEqual(changed.routine(forSlot: 0)?.exercises[0].name, "New press")
        changed.startDate = day(7)
        XCTAssertEqual(changed.date(forSlot: 0, calendar: calendar), day(7))
    }

    func testLegacyProgramAndRescueOutboxRoundTrip() throws {
        let base = program()
        let raw = try JSONEncoder().encode(base)
        XCTAssertNil(try JSONDecoder().decode(WorkoutProgram.self, from: raw).weekRescue)
        let rescue = try WeekRescueRules.preview(program: base, reason: .lessTime, workoutDate: today, minutes: 20, now: today, calendar: calendar)
        let changed = try WeekRescueRules.applying(rescue, to: base)
        let decoded = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(decoded.routine(forSlot: 0)?.exercises.count, changed.routine(forSlot: 0)?.exercises.count)
        XCTAssertLessThan(decoded.routine(forSlot: 0)!.exercises.count, base.routines[0].exercises.count)
    }

    func testRescueDatesHandleDSTWithoutChangingLocalDay() throws {
        let base = program()
        let rescue = try WeekRescueRules.preview(program: base, reason: .missedWorkout, workoutDate: day(7), now: today, calendar: calendar)
        let updated = try WeekRescueRules.applying(rescue, to: base)
        for slot in 0..<updated.totalSlots { XCTAssertEqual(calendar.component(.hour, from: updated.date(forSlot: slot, calendar: calendar)!), 0) }
    }

    func testMealOverlayYieldsToLaterEditsAndUndoReturnsBase() throws {
        let base = MealPlanDay(id: "2026-10-20", date: today, meals: [PlannedMeal(mealType: "Lunch", foodItem: meal())])
        var after = base
        after.meals[0].foodItem = meal("Toast")
        let change = try RescueMealChange(original: base, replacement: after)
        let rescue = try WeekRescueRules.preview(program: program(), reason: .busyDay, workoutDate: day(1), mealChanges: [change], now: today, calendar: calendar)
        XCTAssertEqual(rescue.resolving(base, on: today, calendar: calendar)?.meals[0].foodItem?.name, "Toast")
        var edited = base
        edited.meals[0].foodItem?.calories = 900 // ID equality must not hide nutrition edits.
        XCTAssertEqual(rescue.resolving(edited, on: today, calendar: calendar)?.meals[0].foodItem?.calories, 900)
        XCTAssertNil(rescue.resolving(nil, on: day(1), calendar: calendar))
    }

    func testNewMealOnEmptyDayAndProgramRoundTrip() throws {
        let plan = MealPlanDay(id: "2026-10-20", date: today, meals: [PlannedMeal(mealType: "Dinner", foodItem: meal())])
        let base = program()
        let rescue = try WeekRescueRules.preview(program: base, reason: .busyDay, workoutDate: today,
                                                mealChanges: [try RescueMealChange(original: nil, replacement: plan)], now: today, calendar: calendar)
        let saved = try WeekRescueRules.applying(rescue, to: base)
        let decoded = try JSONDecoder().decode(WorkoutProgram.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.weekRescue?.resolving(nil, on: today, calendar: calendar)?.meals.count, 1)
    }

    func testRescueRejectsPastAndOutOfWindowDatesAndCompletedPlan() throws {
        for date in [day(-1), day(8)] {
            XCTAssertThrowsError(try WeekRescueRules.preview(program: program(), reason: .missedWorkout, workoutDate: date, now: today, calendar: calendar))
        }
        var done = program(); done.currentProgressIndex = 999
        XCTAssertNil(done.routine(forSlot: -1))
        XCTAssertThrowsError(try WeekRescueRules.preview(program: done, reason: .busyDay, workoutDate: day(1), now: today, calendar: calendar))
    }

    func testUsefulQuestionSelectsLargestRelevantRangeOnly() throws {
        let first = meal(), second = meal("Rice")
        let question = UsefulMealQuestionRules.choose(items: [first, second], evidence: [
            MealPortionEvidence(itemID: first.id, lowGrams: 180, highGrams: 220),
            MealPortionEvidence(itemID: second.id, lowGrams: 100, highGrams: 300)
        ], loggedCalories: 1_200, calorieGuide: 2_000)
        XCTAssertEqual(question?.itemID, second.id)
        XCTAssertEqual(question?.lowCalories, 200)
        XCTAssertEqual(question?.highCalories, 600)
    }

    func testSmallOrInvalidPortionRangesNeverInterrupt() {
        let item = meal()
        for range in [(190.0, 210.0), (0, 400), (300, 400), (100, .infinity), (.nan, 300)] {
            XCTAssertNil(UsefulMealQuestionRules.choose(items: [item], evidence: [MealPortionEvidence(itemID: item.id, lowGrams: range.0, highGrams: range.1)], loggedCalories: 1_600, calorieGuide: 2_000))
        }
    }

    func testPortionAnswerScalesAllNutritionAndPreservesIdentity() throws {
        var food = meal(); food.iron = 8
        let changed = try XCTUnwrap(UsefulMealQuestionRules.applying(grams: 100, to: food))
        XCTAssertEqual(changed.id, food.id)
        XCTAssertEqual(changed.calories, 200)
        XCTAssertEqual(changed.protein, 10)
        XCTAssertEqual(changed.iron, 4)
        XCTAssertEqual(changed.servingWeight, 100)
        XCTAssertEqual(changed.servingSize, "100 g")
        XCTAssertNil(UsefulMealQuestionRules.applying(grams: .nan, to: food))
    }

    func testExperimentCounterbalancesSixScheduledSessions() throws {
        let value = try experiment()
        XCTAssertEqual(value.trials.map(\.side), [.a, .b, .b, .a, .a, .b])
        XCTAssertEqual(value.trials.map(\.slot), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(Set(value.trials.map(\.id)).count, 6)
        XCTAssertFalse(value.isFinished)
        var done = program(); done.currentProgressIndex = 999
        XCTAssertThrowsError(try MealExperimentRules.create(program: done, routineID: "upper", mealA: meal(), mealB: meal("Toast"), minutesBefore: 90, startsWithA: true, now: today))
    }

    func testAnotherPairKeepsEarlierEvidenceAndUsesLaterSlots() throws {
        var value = try experiment()
        for index in value.trials.indices { value.trials[index].skipped = true }
        let extended = try MealExperimentRules.addingPair(to: value, program: program(), now: today, calendar: calendar)
        XCTAssertEqual(extended.id, value.id)
        XCTAssertEqual(extended.trials.count, 8)
        XCTAssertEqual(extended.trials.suffix(2).map(\.slot), [6, 7])
        XCTAssertEqual(Set(extended.trials.suffix(2).map { $0.side.rawValue }), Set(["A", "B"]))
        XCTAssertTrue(extended.trials.prefix(6).allSatisfy(\.skipped))
        XCTAssertFalse(extended.isFinished)
        XCTAssertThrowsError(try MealExperimentRules.addingPair(to: extended, program: program(), now: today, calendar: calendar))
    }

    func testExperimentRejectsDuplicateMealAndUnknownWorkout() {
        XCTAssertThrowsError(try MealExperimentRules.create(program: program(), routineID: "upper", mealA: meal(), mealB: meal(" oats "), minutesBefore: 90, startsWithA: true, now: today))
        XCTAssertThrowsError(try MealExperimentRules.create(program: program(), routineID: "missing", mealA: meal(), mealB: meal("Toast"), minutesBefore: 90, startsWithA: true, now: today))
    }

    func testCheckInNeedsRealDistinctWorkoutAndExplicitRatings() throws {
        let value = try experiment()
        let updated = try MealExperimentRules.recording(in: value, trialID: value.trials[0].id, session: session(), energy: 4, comfort: 5, minutesBefore: 90, confounders: [], now: today)
        XCTAssertEqual(updated.trials[0].observation?.workingSets, 16)
        XCTAssertEqual(updated.trials[0].observation?.meanRPE, 8)
        XCTAssertEqual(updated.trials[0].observation?.volume, 12_800)
        XCTAssertThrowsError(try MealExperimentRules.recording(in: updated, trialID: value.trials[1].id, session: session(), energy: 4, comfort: 5, minutesBefore: 90, confounders: [], now: today))
        XCTAssertThrowsError(try MealExperimentRules.recording(in: value, trialID: value.trials[0].id, session: session(), energy: 0, comfort: 5, minutesBefore: 90, confounders: [], now: today))
        var wrong = session(); wrong.routineID = "other"
        XCTAssertThrowsError(try MealExperimentRules.recording(in: value, trialID: value.trials[0].id, session: wrong, energy: 4, comfort: 5, minutesBefore: 90, confounders: [], now: today))
    }

    func testConfoundersAreRetainedButExcludedAndMissingEffortIsNotZero() throws {
        let value = try experiment()
        var changed = session(); changed.completedExercises.removeLast()
        changed.completedExercises[0].sets = [CompletedSet(reps: 8, weight: 100)]
        let updated = try MealExperimentRules.recording(in: value, trialID: value.trials[0].id, session: changed, energy: 4, comfort: 5, minutesBefore: 180, confounders: ["Unusual sleep"], now: today)
        XCTAssertTrue(updated.trials[0].observation!.confounders.contains("Workout exercises changed"))
        XCTAssertTrue(updated.trials[0].observation!.confounders.contains("Meal timing changed"))
        XCTAssertTrue(updated.trials[0].observation!.confounders.contains("Working set count changed"))
        let summary = MealExperimentRules.summary(updated)
        XCTAssertEqual(summary.excluded, 1)
        XCTAssertEqual(summary.a.count, 0)
        XCTAssertNil(summary.a.meanRPE)
        XCTAssertEqual(summary.headline, "Still learning")
    }

    func testThreeCleanSessionsPerMealRequiredForPattern() throws {
        var value = try experiment()
        for index in 0..<6 {
            value = try MealExperimentRules.recording(in: value, trialID: value.trials[index].id, session: session("s\(index)", date: day(index)),
                                                       energy: value.trials[index].side == .a ? 5 : 3, comfort: 4, minutesBefore: 90, confounders: [], now: day(index))
            XCTAssertEqual(MealExperimentRules.summary(value).hasEnoughObservations, index == 5)
        }
        XCTAssertEqual(MealExperimentRules.summary(value).headline, "A pattern worth repeating")
        XCTAssertTrue(value.isFinished)
    }

    @MainActor func testMealOverlayFeedsPlannerAndGroceriesAndUndoRefreshesBoth() async throws {
        let previousAuth = DIContainer.shared.authService
        let previousRepo = DIContainer.shared.nutritionRepository
        let auth = MockAuthService(); auth.currentUserID = "u"
        let repo = MockNutritionRepository()
        DIContainer.shared.authService = auth
        DIContainer.shared.nutritionRepository = repo
        let suite = "rescue-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            DIContainer.shared.authService = previousAuth
            DIContainer.shared.nutritionRepository = previousRepo
            defaults.removePersistentDomain(forName: suite)
        }
        let date = Calendar.current.startOfDay(for: Date())
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let base = MealPlanDay(id: formatter.string(from: date), date: date,
                              meals: [PlannedMeal(mealType: "Dinner", foodItem: meal("Apple"), ingredients: ["1 apple"])])
        let replacement = MealPlanDay(id: base.id, date: date,
                                     meals: [PlannedMeal(mealType: "Dinner", foodItem: meal("Banana"), ingredients: ["2 bananas"])])
        repo.mockMealPlansByDateString[base.id] = base
        repo.mockFetchGroceryListResult = [GroceryListItem(name: "apple", quantity: 1, unit: "item", source: "mealPlan", sourcePlanStart: date),
                                          GroceryListItem(name: "salt", quantity: 1, unit: "jar", source: "manual")]
        let service = MealPlannerService(recipeService: RecipeService(), userDefaults: defaults)
        var rescue: WeekRescueAdjustment?
        service.activeWeekRescue = { _ in rescue }
        var plan = program(); plan.startDate = date; plan.daysOfWeek = [Calendar.current.component(.weekday, from: date)]
        rescue = try WeekRescueRules.preview(program: plan, reason: .busyDay, workoutDate: date,
            mealChanges: [try RescueMealChange(original: base, replacement: replacement)])
        let visible = try await service.fetchPlanResult(for: date, userID: "u").get()
        let original = try await service.fetchBasePlanResult(for: date, userID: "u").get()
        XCTAssertEqual(visible?.meals.first?.foodItem?.name, "Banana")
        XCTAssertEqual(original?.meals.first?.foodItem?.name, "Apple")
        let rescuedList = try await service.fetchSynchronizedGroceryListResult(for: "u", starting: date).get()
        XCTAssertTrue(rescuedList.contains { $0.name.localizedCaseInsensitiveContains("banana") })
        XCTAssertTrue(rescuedList.contains { $0.name == "salt" })
        XCTAssertTrue(repo.savedMealPlans.isEmpty, "An overlay must not publish a second meal write")
        repo.mockFetchGroceryListResult = rescuedList
        rescue = nil
        let restored = try await service.fetchPlanResult(for: date, userID: "u").get()
        XCTAssertEqual(restored?.meals.first?.foodItem?.name, "Apple")
        let restoredList = try await service.fetchSynchronizedGroceryListResult(for: "u", starting: date).get()
        XCTAssertTrue(restoredList.contains { $0.name.localizedCaseInsensitiveContains("apple") })
        XCTAssertFalse(restoredList.contains { $0.name.localizedCaseInsensitiveContains("banana") })
        service.invalidateCache(for: "u")
        repo.mealPlanError = CocoaError(.fileReadUnknown)
        if case .success = await service.fetchPlanResult(for: date, userID: "u") { XCTFail("A failed base read must not become an empty plan") }
    }

    @MainActor func testColdAccountActivationLoadsSavedRescueAndLogoutClearsIt() throws {
        let oldAuth = DIContainer.shared.authService
        let oldRepo = DIContainer.shared.workoutRepository
        let auth = MockAuthService(); auth.currentUserID = "u"
        let repo = MockWorkoutRepository()
        DIContainer.shared.authService = auth; DIContainer.shared.workoutRepository = repo
        let suite = "rescue-activation-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            DIContainer.shared.authService = oldAuth; DIContainer.shared.workoutRepository = oldRepo
            defaults.removePersistentDomain(forName: suite)
        }
        let base = program()
        let rescue = try WeekRescueRules.preview(program: base, reason: .busyDay, workoutDate: day(1), now: today, calendar: calendar)
        let saved = try WeekRescueRules.applying(rescue, to: base)
        repo.onProgramsSnapshotListenerAdded = { _, update in update(.success([saved])) }
        repo.onRoutinesSnapshotListenerAdded = { _, update in update(.success(saved.routines)) }
        let first = WorkoutService(defaults: defaults)
        first.setActiveProgram(base)
        let restarted = WorkoutService(defaults: defaults)
        restarted.activateAccount("u")
        XCTAssertEqual(restarted.activeProgram?.weekRescue?.id, rescue.id)
        restarted.activateAccount(nil)
        XCTAssertNil(restarted.activeProgram)
        XCTAssertTrue(restarted.userPrograms.isEmpty)
    }

    @MainActor func testComparisonPersistenceRestartAccountIsolationAndDelete() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = EditorDraftStore(directory: folder)
        let first = MealExperimentStore(storage: storage)
        first.activateAccount("u")
        let value = try experiment()
        try first.save(value, for: "u")
        let restarted = MealExperimentStore(storage: storage)
        restarted.activateAccount("u")
        XCTAssertEqual(restarted.active?.id, value.id)
        restarted.activateAccount("other")
        XCTAssertTrue(restarted.experiments.isEmpty)
        XCTAssertThrowsError(try restarted.save(value, for: "u"))
        restarted.activateAccount("u")
        try restarted.deleteAll(for: "u")
        XCTAssertNil(try storage.load([MealExperiment].self, userID: "u", scope: "familiar-meal-comparisons-v1"))
    }

    @MainActor func testFailedDiskSaveDoesNotPublishExperiment() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = MealExperimentStore(storage: EditorDraftStore(directory: file))
        store.activateAccount("u")
        XCTAssertThrowsError(try store.save(experiment(), for: "u"))
        XCTAssertTrue(store.experiments.isEmpty)
    }
}
