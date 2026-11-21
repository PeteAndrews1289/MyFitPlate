import XCTest
@testable import MyFitPlateCore

final class DailyLogMutationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private func food(_ id: String) -> FoodItem {
        FoodItem(id: id, name: id, calories: 100, protein: 10, carbs: 10, fats: 2)
    }
    private func mutation(_ before: DailyLog, _ edit: (inout DailyLog) -> Void) throws -> DailyLogMutation {
        var after = before.rememberingMutationBase()
        edit(&after)
        return try DailyLogMutation(userID: "a", log: after)
    }

    func testTwoStaleDevicesKeepBothFoodAdditions() throws {
        let initial = DailyLog(id: "day", date: date, meals: [Meal(name: "Lunch", foodItems: [food("original")])])
        let first = try mutation(initial) { $0.meals[0].foodItems.append(food("first")) }
        let second = try mutation(initial) { $0.meals[0].foodItems.append(food("second")) }
        let final = second.applying(to: first.applying(to: initial))
        XCTAssertEqual(Set(final.meals[0].foodItems.map(\.id)), ["original", "first", "second"])
    }

    func testOfflineEmptyCacheCannotEraseServerFood() throws {
        let emptyCache = DailyLog(id: "day", date: date, meals: [])
        let remote = DailyLog(id: "day", date: date, meals: [Meal(name: "Breakfast", foodItems: [food("remote")])])
        let addition = try mutation(emptyCache) { $0.meals.append(Meal(name: "Lunch", foodItems: [food("offline")])) }
        let merged = addition.applying(to: remote)
        XCTAssertEqual(Set(merged.meals.flatMap(\.foodItems).map(\.id)), ["remote", "offline"])
    }

    func testConcurrentFirstMealIDsRemainEditableAfterMergingByName() throws {
        let empty = DailyLog(id: "day", date: date, meals: [])
        let first = try mutation(empty) { $0.meals = [Meal(name: "Lunch", foodItems: [food("a")])] }
        let second = try mutation(empty) { $0.meals = [Meal(name: "Lunch", foodItems: [food("b")])] }
        let remote = second.applying(to: first.applying(to: empty))
        let edit = try mutation(second.after) { $0.meals[0].foodItems[0].calories = 250 }
        let edited = edit.applying(to: remote)
        XCTAssertEqual(edited.meals.count, 1)
        XCTAssertEqual(edited.meals[0].foodItems.first { $0.id == "b" }?.calories, 250)
        let deletion = try mutation(second.after) { $0.meals.removeAll() }
        XCTAssertEqual(deletion.applying(to: edited).meals[0].foodItems.map(\.id), ["a"])
    }

    func testDeleteWinsOverStaleEditWithoutRemovingConcurrentAdditions() throws {
        let initial = DailyLog(id: "day", date: date, meals: [Meal(name: "Lunch", foodItems: [food("old")])])
        let deletion = try mutation(initial) { $0.meals[0].foodItems.removeAll() }
        let editing = try mutation(initial) { $0.meals[0].foodItems[0].calories = 999; $0.meals[0].foodItems.append(food("new")) }
        for merged in [deletion.applying(to: editing.applying(to: initial)), editing.applying(to: deletion.applying(to: initial))] {
            XCTAssertEqual(merged.meals[0].foodItems.map(\.id), ["new"])
        }
    }

    func testWaterRetriesAreIdempotentAndIndependentIncrementsAccumulate() throws {
        let initial = DailyLog(id: "day", date: date, meals: [], waterTracker: WaterTracker(totalOunces: 16, date: date))
        let first = try mutation(initial) { $0.waterTracker?.totalOunces += 8 }
        let second = try mutation(initial) { $0.waterTracker?.totalOunces += 4 }
        let merged = second.applying(to: first.applying(to: initial))
        XCTAssertEqual(merged.waterTracker?.totalOunces, 28)
        XCTAssertEqual(first.applying(to: merged).waterTracker?.totalOunces, 28)
    }

    func testCheckedFoodEditRejectsChangedOrDeletedSameEntry() throws {
        let original = food("selected")
        let initial = DailyLog(id: "day", date: date, meals: [Meal(name: "Lunch", foodItems: [original])])
        var desired = original; desired.calories = 150
        let edit = try mutation(initial) {
            $0.meals[0].foodItems = [desired]
            $0.pendingFoodEdit = FoodEditPrecondition(original: original, desired: desired)
        }
        var changed = initial; changed.meals[0].foodItems[0].calories = 300
        XCTAssertThrowsError(try edit.applying(to: changed, checkingFoodEdits: true))
        var deleted = initial; deleted.meals[0].foodItems = []
        XCTAssertThrowsError(try edit.applying(to: deleted, checkingFoodEdits: true))
        var duplicate = initial; duplicate.meals[0].foodItems.append(original)
        XCTAssertThrowsError(try edit.applying(to: duplicate, checkingFoodEdits: true))
    }

    func testCheckedFoodEditMergesUnrelatedChangesAndReplayCannotUndoLaterEdit() throws {
        let original = food("selected"), other = food("other")
        let initial = DailyLog(id: "day", date: date, meals: [Meal(name: "Lunch", foodItems: [original, other])])
        var desired = original; desired.calories = 150
        let edit = try mutation(initial) {
            $0.meals[0].foodItems[0] = desired
            $0.pendingFoodEdit = FoodEditPrecondition(original: original, desired: desired)
        }
        var remote = initial; remote.meals[0].foodItems[1].calories = 250
        remote.meals[0].foodItems.append(food("remote-addition"))
        let accepted = try edit.applying(to: remote, checkingFoodEdits: true)
        XCTAssertEqual(accepted.meals[0].foodItems.map(\.calories), [150, 250, 100])
        var later = accepted; later.meals[0].foodItems[0].calories = 450
        let replayed = try edit.applying(to: later, checkingFoodEdits: true)
        XCTAssertEqual(replayed.meals[0].foodItems.map(\.calories), [450, 250, 100])
        XCTAssertEqual(replayed.appliedMutationIDs?.filter { $0 == edit.id }.count, 1)
        var alreadyDesired = remote; alreadyDesired.meals[0].foodItems[0] = desired
        XCTAssertNoThrow(try edit.applying(to: alreadyDesired, checkingFoodEdits: true))
    }

    func testCheckedBatchUndoRequiresAllTargetsAndPreservesUnrelatedFoods() throws {
        let original = food("selected"), added = food("added"), removed = food("removed")
        let baseline = DailyLog(id: "day", date: date, meals: [Meal(name: "Lunch", foodItems: [original, added])])
        let inverse = try mutation(baseline) {
            $0.meals[0].foodItems = [original, removed]
            $0.pendingFoodEdits = [
                FoodEditPrecondition(foodID: added.id, expected: added, desired: nil),
                FoodEditPrecondition(foodID: removed.id, expected: nil, desired: removed)
            ]
        }
        var remote = baseline; remote.meals[0].foodItems[0].calories = 333
        let accepted = try inverse.applying(to: remote, checkingFoodEdits: true)
        XCTAssertEqual(accepted.meals[0].foodItems.map(\.id), [original.id, removed.id])
        XCTAssertEqual(accepted.meals[0].foodItems[0].calories, 333)
        remote.meals[0].foodItems[1].calories = 222
        XCTAssertThrowsError(try inverse.applying(to: remote, checkingFoodEdits: true))
        XCTAssertNoThrow(try inverse.applying(to: accepted, checkingFoodEdits: true))
    }

    func testCheckedMoveUndoRejectsConcurrentPlacementEvenWhenNutritionIsIdentical() throws {
        let selected = food("selected")
        let lunch = Meal(name: "Lunch", foodItems: [])
        let dinner = Meal(name: "Dinner", foodItems: [selected])
        let baseline = DailyLog(id: "day", date: date, meals: [lunch, dinner])
        let inverse = try mutation(baseline) {
            $0.meals[0].foodItems = [selected]; $0.meals[1].foodItems = []
            $0.pendingFoodEdits = [FoodEditPrecondition(foodID: selected.id, expected: selected, desired: selected,
                expectedMealID: dinner.id, desiredMealID: lunch.id)]
        }
        let accepted = try inverse.applying(to: baseline, checkingFoodEdits: true)
        XCTAssertEqual(accepted.meals[0].foodItems.map(\.id), [selected.id])
        XCTAssertTrue(accepted.meals[1].foodItems.isEmpty)
        var movedAgain = baseline; movedAgain.meals[1].foodItems = []
        movedAgain.meals.append(Meal(name: "Snack", foodItems: [selected]))
        XCTAssertThrowsError(try inverse.applying(to: movedAgain, checkingFoodEdits: true))
    }

    func testJournalAndExerciseChangesDoNotReplaceUnrelatedEntries() throws {
        let initial = DailyLog(id: "day", date: date, meals: [])
        let first = try mutation(initial) { $0.journalEntries = [JournalEntry(id: "a", date: date, text: "First", category: "note")] }
        let second = try mutation(initial) {
            $0.journalEntries = [JournalEntry(id: "b", date: date, text: "Second", category: "note")]
            $0.exercises = [LoggedExercise(id: "run", name: "Run", caloriesBurned: 100, date: date)]
        }
        let merged = second.applying(to: first.applying(to: initial))
        XCTAssertEqual(merged.journalEntries?.count, 2)
        XCTAssertEqual(merged.exercises?.map(\.id), ["run"])
    }

    func testOutboxSurvivesRelaunchAndOnlyAcknowledgesTheSelectedAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.json")
        let initial = DailyLog(id: "day", date: date, meals: [])
        let operation = try mutation(initial) { $0.meals = [Meal(name: "Lunch", foodItems: [food("offline")])] }
        let store = DailyLogMutationStore(fileURL: url)
        try store.append(operation)
        try store.append(operation)
        let reopened = DailyLogMutationStore(fileURL: url)
        XCTAssertEqual(try reopened.pending(userID: "a").map(\.id), [operation.id])
        XCTAssertTrue(try reopened.pending(userID: "b").isEmpty)
        try reopened.acknowledge(operation)
        XCTAssertTrue(try store.pending(userID: "a").isEmpty)
        try store.append(operation)
        let otherAccount = try DailyLogMutation(userID: "b", log: initial)
        try store.append(otherAccount)
        try reopened.removeAll(userID: "a")
        XCTAssertTrue(try store.pending(userID: "a").isEmpty)
        XCTAssertEqual(try store.pending(userID: "b").count, 1)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try store.append(operation))
        XCTAssertEqual(try String(contentsOf: url), "corrupt")
    }
}
