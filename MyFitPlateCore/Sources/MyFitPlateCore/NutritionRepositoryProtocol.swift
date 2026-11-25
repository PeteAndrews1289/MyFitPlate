import Foundation

public protocol NutritionRepositoryProtocol: Sendable {
    func dailyLogSyncState(userID: String) -> DailyLogSyncState
    func retryPendingDailyLogs(userID: String)
    func discardPendingDailyLogs(userID: String) throws
    func updateDailyLog(userID: String, log: DailyLog, completion: @escaping (Bool) -> Void)
    func saveDailyLog(userID: String, log: DailyLog) async throws
    func fetchLogInternal(userID: String, date: Date, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func fetchLogInternal(userID: String, day: DiaryDayContext, completion: @escaping (Result<DailyLog, Error>) -> Void)
    func addLogSnapshotListener(userID: String, date: Date, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any
    func addLogSnapshotListener(userID: String, day: DiaryDayContext, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any
    func removeLogSnapshotListener(_ handle: Any)
    func fetchDailyHistory(userID: String, startDate: Date?, endDate: Date?) async throws -> [DailyLog]
    func fetchDailyHistoryForReview(userID: String, startDate: Date, endDate: Date) async throws -> [DailyLog]
    func fetchExportDailyHistory(userID: String) async throws -> [DailyLog]
    func fetchRecommendedFoods(userID: String, mealName: String, completion: @escaping (Result<[FoodItem], Error>) -> Void)
    /// Remote atomic acknowledgement only; local optimistic saves cannot implement a move.
    func applyDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult
    func fetchDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult
    /// Nil confirms a permanent cancellation fence; an accepted operation returns its receipt.
    func cancelDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult?
    func undoDiaryTransfer(userID: String, receipt: DiaryTransferReceipt) async throws -> DiaryTransferResult
    
    // Meal Plans & Grocery List
    func fetchMealPlan(userID: String, dateString: String) async throws -> MealPlanDay?
    /// Complete canonical source for advisory reservations across saved periods.
    /// Failure or an unreadable plan must not be represented as zero reservations.
    func fetchMealPlansForStockReservations(userID: String) async throws -> [MealPlanDay]
    func saveMealPlan(userID: String, plan: MealPlanDay) async throws
    func saveFullMealPlanBatch(userID: String, plans: [MealPlanDay]) async throws
    func applyMealPlanChange(userID: String, change: MealPlanChange) async throws
    /// Exact status or permanent cancellation fence for a previously frozen proposal.
    func resolveMealPlanChange(userID: String, change: MealPlanChange, cancelPending: Bool) async throws -> MealPlanChangeResolution
    func discardMealPlans(
        userID: String,
        dateStrings: [String],
        retainingGroceryItems: [GroceryListItem]
    ) async throws
    func fetchGroceryList(userID: String) async throws -> [GroceryListItem]
    func fetchSavedShoppingChoices(userID: String, day: String) async throws -> [GroceryListItem]
    func saveGroceryList(userID: String, items: [GroceryListItem]) async throws
    func applyGroceryMutation(userID: String, mutation: GroceryListMutation) async throws -> [GroceryListItem]
    func resolveGroceryMutation(userID: String, mutation: GroceryListMutation, cancelPending: Bool) async throws -> GroceryMutationResolution
    
    // Checked reusable meal documents and accepted plan history.
    func fetchSavedMealCompositions(userID: String) async throws -> [SavedMealComposition]
    func saveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal) async throws -> SavedMealComposition
    func resolveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution
    func fetchSavedMealWeekTemplates(userID: String) async throws -> [SavedMealWeekTemplate]
    func saveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal) async throws -> SavedMealWeekTemplate
    func resolveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution
    func fetchMealPlanChangeHistory(userID: String, limit: Int) async throws -> [MealPlanChange]

    // Pantry
    func fetchInventory(userID: String) async throws -> [PantryItem]
    func fetchInventoryHistory(userID: String) async throws -> [InventoryReceipt]
    func fetchInventoryIntakeLink(userID: String, foodID: String) async throws -> InventoryIntakeLink?
    func applyInventoryMutation(userID: String, mutation: InventoryMutation) async throws
    func resolveInventoryMutation(userID: String, mutation: InventoryMutation, cancelPending: Bool) async throws -> InventoryResolution
    func addPantrySnapshotListener(userID: String, onChange: @escaping (Result<[PantryItem], Error>) -> Void) -> Any
    func removePantrySnapshotListener(_ handle: Any)
    func savePantryItem(userID: String, item: PantryItem) async throws
    func createPantryReceiptItem(userID: String, receiptID: UUID, item: PantryItem) async throws
    func deletePantryItem(userID: String, itemID: String) async throws
    
    // Recipes
    func fetchRecipes(userID: String) async throws -> [Recipe]
    func saveRecipe(userID: String, recipe: Recipe) async throws -> Recipe
    /// Checked remote acknowledgement for the original editor snapshot, including create-once retry.
    func saveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID) async throws -> Recipe
    func fetchRecipeVersionHistory(userID: String, recipeID: String, limit: Int) async throws -> [RecipeVersionRecord]
    func restoreRecipeVersion(userID: String, proposal: RecipeVersionRestoreProposal) async throws -> Recipe
    func resolveRecipeVersionRestore(userID: String, proposal: RecipeVersionRestoreProposal, cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution
    func resolveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID,
                               cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution
    func deleteRecipe(userID: String, recipeID: String) async throws
    func applyRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation) async throws
    func resolveRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation, cancelPending: Bool) async throws -> RecipeLibraryMutationResolution
    func applySavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation) async throws
    func resolveSavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation, cancelPending: Bool) async throws -> SavedFoodLibraryMutationResolution
    func fetchRecipeLibraryHistory(userID: String, limit: Int) async throws -> [RecipeLibraryMutation]
    func fetchSavedFoodLibraryHistory(userID: String, limit: Int) async throws -> [SavedFoodLibraryMutation]
    
    // Custom Foods
    func saveCustomFood(userID: String, foodItem: FoodItem) async throws
    func saveCustomFoodReplacingDuplicates(
        userID: String,
        foodItem: FoodItem,
        removingFoodIDs: [String]
    ) async throws
    func deleteCustomFood(userID: String, foodItemID: String) async throws
    func removeCustomFoodBarcode(userID: String, foodItemID: String) async throws
    func mergeCustomFoods(userID: String, keepingFoodID: String, removingFoodIDs: [String]) async throws
    func fetchCustomFoods(userID: String) async throws -> [FoodItem]
    
    // Recent Foods
    func saveRecentFood(userID: String, foodItem: FoodItem, source: String, stableID: String) async throws
    func fetchRecentFoods(userID: String, limit: Int) async throws -> [FoodItem]
}

public extension NutritionRepositoryProtocol {
    func fetchSavedShoppingChoices(userID: String, day: String) async throws -> [GroceryListItem] { [] }
    func fetchDailyHistoryForReview(userID: String, startDate: Date, endDate: Date) async throws -> [DailyLog] {
        throw WeeklyTargetReviewError.unavailable
    }
    func resolveGroceryMutation(userID: String, mutation: GroceryListMutation, cancelPending: Bool) async throws -> GroceryMutationResolution { throw GroceryChecklistError.unavailable }
    func fetchRecipeLibraryHistory(userID: String, limit: Int) async throws -> [RecipeLibraryMutation] { throw LibraryMutationError.unavailable }
    func fetchSavedFoodLibraryHistory(userID: String, limit: Int) async throws -> [SavedFoodLibraryMutation] { throw LibraryMutationError.unavailable }
    func fetchSavedMealCompositions(userID: String) async throws -> [SavedMealComposition] { throw MealPlanChangeReceiptError.unavailable }
    func saveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal) async throws -> SavedMealComposition { throw MealPlanChangeReceiptError.unavailable }
    func resolveSavedMealComposition(userID: String, proposal: MealCompositionSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution { throw MealPlanChangeReceiptError.unavailable }
    func fetchSavedMealWeekTemplates(userID: String) async throws -> [SavedMealWeekTemplate] { throw MealPlanChangeReceiptError.unavailable }
    func saveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal) async throws -> SavedMealWeekTemplate { throw MealPlanChangeReceiptError.unavailable }
    func resolveSavedMealWeekTemplate(userID: String, proposal: MealWeekTemplateSaveProposal, cancelPending: Bool) async throws -> PlanningDocumentSaveResolution { throw MealPlanChangeReceiptError.unavailable }
    func fetchMealPlanChangeHistory(userID: String, limit: Int) async throws -> [MealPlanChange] { throw MealPlanChangeReceiptError.unavailable }
    func applyRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation) async throws { throw LibraryMutationError.unavailable }
    func resolveRecipeLibraryMutation(userID: String, mutation: RecipeLibraryMutation, cancelPending: Bool) async throws -> RecipeLibraryMutationResolution { throw LibraryMutationError.unavailable }
    func applySavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation) async throws { throw LibraryMutationError.unavailable }
    func resolveSavedFoodLibraryMutation(userID: String, mutation: SavedFoodLibraryMutation, cancelPending: Bool) async throws -> SavedFoodLibraryMutationResolution { throw LibraryMutationError.unavailable }
    func resolveMealPlanChange(userID: String, change: MealPlanChange, cancelPending: Bool) async throws -> MealPlanChangeResolution {
        throw MealPlanChangeReceiptError.unavailable
    }
    func saveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID) async throws -> Recipe { throw RecipeRevisionError.unavailable }
    func fetchRecipeVersionHistory(userID: String, recipeID: String, limit: Int) async throws -> [RecipeVersionRecord] { throw RecipeRevisionError.unavailable }
    func restoreRecipeVersion(userID: String, proposal: RecipeVersionRestoreProposal) async throws -> Recipe { throw RecipeRevisionError.unavailable }
    func resolveRecipeVersionRestore(userID: String, proposal: RecipeVersionRestoreProposal, cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution { throw RecipeRevisionError.unavailable }
    func resolveRecipeRevision(userID: String, expected: Recipe?, updated: Recipe, operationID: UUID,
                               cancelIfUnaccepted: Bool) async throws -> RecipeRevisionResolution { throw RecipeRevisionError.unavailable }
    func applyDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult { throw DiaryTransferError.unsupported }
    func fetchDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult { throw DiaryTransferError.unsupported }
    func cancelDiaryTransfer(userID: String, command: DiaryTransferCommand) async throws -> DiaryTransferResult? { throw DiaryTransferError.unsupported }
    func undoDiaryTransfer(userID: String, receipt: DiaryTransferReceipt) async throws -> DiaryTransferResult { throw DiaryTransferError.unsupported }
    func fetchLogInternal(userID: String, day: DiaryDayContext, completion: @escaping (Result<DailyLog, Error>) -> Void) {
        guard day.isOwned(by: userID), DiaryDayContext.dayKey(for: day.originalDate) == day.dayKey else {
            completion(.failure(DiaryTransferError.unsupported)); return
        }
        fetchLogInternal(userID: userID, date: day.originalDate, completion: completion)
    }
    func addLogSnapshotListener(userID: String, day: DiaryDayContext, onChange: @escaping (Result<DailyLog, Error>) -> Void) -> Any {
        guard day.isOwned(by: userID), DiaryDayContext.dayKey(for: day.originalDate) == day.dayKey else {
            onChange(.failure(DiaryTransferError.unsupported)); return UUID()
        }
        return addLogSnapshotListener(userID: userID, date: day.originalDate, onChange: onChange)
    }
    func createPantryReceiptItem(userID: String, receiptID: UUID, item: PantryItem) async throws { throw GroceryChecklistError.invalid }
    func fetchInventory(userID: String) async throws -> [PantryItem] { throw InventoryError.unavailable }
    func fetchInventoryHistory(userID: String) async throws -> [InventoryReceipt] { throw InventoryError.unavailable }
    func fetchInventoryIntakeLink(userID: String, foodID: String) async throws -> InventoryIntakeLink? { throw InventoryError.unavailable }
    func applyInventoryMutation(userID: String, mutation: InventoryMutation) async throws { throw InventoryError.unavailable }
    func resolveInventoryMutation(userID: String, mutation: InventoryMutation, cancelPending: Bool) async throws -> InventoryResolution { throw InventoryError.unavailable }
    func fetchExportDailyHistory(userID: String) async throws -> [DailyLog] {
        try await fetchDailyHistory(userID: userID, startDate: nil, endDate: nil)
    }
    func dailyLogSyncState(userID: String) -> DailyLogSyncState { .synced }
    func retryPendingDailyLogs(userID: String) {}
    func discardPendingDailyLogs(userID: String) throws {}
}
