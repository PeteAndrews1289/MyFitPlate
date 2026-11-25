import Foundation

struct DiaryUndoReceipt: Codable {
    let id: UUID
    let userID: String
    let before: DailyLog
    let after: DailyLog
    let expiresAt: Date
    var isSubmitted: Bool
    var operationID: String { "diary-undo-\(id.uuidString)" }

    func reversal() throws -> DailyLogMutation {
        var inverse = before
        inverse.mutationBase = try JSONEncoder().encode(after)
        inverse.pendingMutationID = operationID
        inverse.pendingDayReviewUndo = before.nutritionDayReview != after.nutritionDayReview ? true : nil
        let previous = before.meals.flatMap(\.foodItems)
        let accepted = after.meals.flatMap(\.foodItems)
        guard Set(previous.map(\.id)).count == previous.count,
              Set(accepted.map(\.id)).count == accepted.count else { throw FoodEditConflict.changed }
        inverse.pendingFoodEdits = Set(previous.map(\.id) + accepted.map(\.id)).sorted().compactMap { foodID in
            let original = previous.first { $0.id == foodID }
            let saved = accepted.first { $0.id == foodID }
            let originalMeal = before.meals.first { $0.foodItems.contains { $0.id == foodID } }?.id
            let savedMeal = after.meals.first { $0.foodItems.contains { $0.id == foodID } }?.id
            if let original, let saved, FoodEditPrecondition.sameSnapshot(original, saved), originalMeal == savedMeal { return nil }
            return FoodEditPrecondition(foodID: foodID, expected: saved, desired: original,
                                        expectedMealID: savedMeal, desiredMealID: originalMeal)
        }
        return try DailyLogMutation(userID: userID, log: inverse)
    }
}
