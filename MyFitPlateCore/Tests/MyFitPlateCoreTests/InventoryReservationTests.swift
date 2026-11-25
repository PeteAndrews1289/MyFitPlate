import XCTest
@testable import MyFitPlateCore

@MainActor
final class InventoryReservationTests: XCTestCase {
    private let day = "2026-11-03"
    private func date(_ key: String) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: key)!
    }
    private func lot(_ amount: Double, unit: String = "g", name: String = "Rice") -> PantryItem {
        var result = PantryItem(name: name, quantity: amount, unit: unit, dateAdded: date(day))
        result.quantityVerified = true; result.preparation = "Raw"; return result
    }
    private func meal(_ id: String, amount: Double, on key: String, batchID: String? = nil) -> PlannedMeal {
        var result = PlannedMeal(id: id, mealType: "Dinner", foodItem: FoodItem(id: id, name: id, calories: 400), ingredients: ["\(amount) g Rice"])
        if let batchID {
            result.cookingBatch = MealCookingBatch(id: batchID, sourceMealID: id, cookingDate: date(key), name: id, totalPortions: 1,
                ingredientsPerPortion: result.plannedIngredients.map(MealCookingIngredient.init), instructions: nil,
                allocations: [.init(mealID: id, date: date(key), portions: 1)])
        }
        return result
    }
    private func plan(_ meal: PlannedMeal, on key: String) -> MealPlanDay { .init(id: key, date: date(key), meals: [meal]) }
    private func snapshot(_ plans: [MealPlanDay], _ stock: [PantryItem], include: String? = nil) throws -> InventoryReservationSnapshot {
        try InventoryReservationRules.snapshot(plans: plans, stock: stock, referenceDayID: day, now: date(day), includingBatchID: include)
    }
    func testDifferentFutureWeeksShareOnePhysicalLotWithoutDoubleReservation() throws {
        let raw = lot(500), first = meal("First", amount: 300, on: day, batchID: "first"), later = meal("Later", amount: 300, on: "2026-11-17", batchID: "later")
        let result = try snapshot([plan(later, on: "2026-11-17"), plan(first, on: day)], [raw])
        XCTAssertEqual(result.reserved(in: raw.id), 500); XCTAssertEqual(result.available(in: raw.id), 0)
        XCTAssertEqual(result.shortages.first?.requirementID, "batch-later")
        XCTAssertEqual(result.shortages.first?.unallocated, 100)
        XCTAssertEqual(result.physicalStock[0].quantity, 500, "Viewing never consumes physical stock")
    }
    func testOwnBatchAllocationIsAvailableOnceAndOtherPlansRequireExplicitReallocation() throws {
        let raw = lot(500), first = meal("First", amount: 300, on: day, batchID: "first"), later = meal("Later", amount: 300, on: "2026-11-17", batchID: "later")
        let result = try snapshot([plan(first, on: day), plan(later, on: "2026-11-17")], [raw])
        XCTAssertEqual(result.available(in: raw.id, for: "batch-first"), 300)
        XCTAssertEqual(result.available(in: raw.id, for: "batch-later"), 200)
        try InventoryReservationRules.validateCooking(batch: first.cookingBatch!, selectedLots: [0: raw.id], snapshot: result, stock: [raw])
        XCTAssertThrowsError(try InventoryReservationRules.validateCooking(batch: later.cookingBatch!, selectedLots: [0: raw.id], snapshot: result, stock: [raw]))
        try InventoryReservationRules.validateCooking(batch: later.cookingBatch!, selectedLots: [0: raw.id], snapshot: result, stock: [raw], allowReallocation: true)
        XCTAssertEqual(raw.quantity, 500)
    }
    func testLinkedLeftoversReserveWholeCookingBatchOnlyOnce() throws {
        let raw = lot(1000)
        var source = meal("Source", amount: 100, on: day, batchID: "batch")
        source.cookingBatch?.totalPortions = 4
        source.cookingBatch?.allocations.append(.init(mealID: "Leftover", date: date("2026-11-04"), portions: 1))
        var leftover = source; leftover.id = "Leftover"
        let result = try snapshot([plan(source, on: day), plan(leftover, on: "2026-11-04")], [raw])
        XCTAssertEqual(result.requirements.count, 1); XCTAssertEqual(result.reserved(in: raw.id), 400)
    }
    func testAcceptedCookReleasesRawReservationAndUndoRestoresIt() throws {
        let raw = lot(1000), source = meal("Source", amount: 400, on: day, batchID: "batch")
        var cooked = PantryItem(name: "Cooked source", quantity: 1, unit: "portion"); cooked.cookedBatch = source.cookingBatch
        let recorded = try snapshot([plan(source, on: day)], [raw, cooked])
        XCTAssertEqual(recorded.requirements[0].state, .alreadyCooked); XCTAssertEqual(recorded.reserved(in: raw.id), 0)
        XCTAssertThrowsError(try InventoryReservationRules.validateCooking(batch: source.cookingBatch!, selectedLots: [0: raw.id], snapshot: recorded, stock: [raw, cooked]))
        cooked.creationUndone = true
        XCTAssertEqual(try snapshot([plan(source, on: day)], [raw, cooked]).reserved(in: raw.id), 400)
    }
    func testRemovedOrResizedSavedPlanReleasesOnlyItsProjectedQuantity() throws {
        let raw = lot(1000), first = meal("First", amount: 300, on: day), second = meal("Second", amount: 200, on: "2026-11-04")
        let before = try snapshot([plan(first, on: day), plan(second, on: "2026-11-04")], [raw])
        let removed = try snapshot([plan(second, on: "2026-11-04")], [raw])
        XCTAssertEqual(before.reserved(in: raw.id), 500); XCTAssertEqual(removed.reserved(in: raw.id), 200)
        XCTAssertEqual(removed.physicalStock[0], raw)
    }
    func testUnknownPackageExpiredAndDifferentlyPreparedLotsCannotCoverPreciseNeed() throws {
        let source = meal("Source", amount: 100, on: "2026-11-10")
        var unknown = lot(100); unknown.quantityVerified = nil
        var expired = lot(100); expired.bestBefore = date("2026-11-04")
        var cooked = lot(100); cooked.preparation = "Cooked"
        let package = lot(1, unit: "package")
        let result = try snapshot([plan(source, on: "2026-11-10")], [unknown, expired, cooked, package])
        XCTAssertTrue(result.allocations.isEmpty); XCTAssertEqual(result.shortages.first?.unallocated, 100)
    }
    func testUnmeasuredIngredientIsUnknownNotOneUnitAndNoStockChanges() throws {
        let source = PlannedMeal(id: "unknown", mealType: "Dinner", ingredients: ["Rice to taste"]), raw = lot(1000)
        let result = try snapshot([plan(source, on: day)], [raw])
        XCTAssertTrue(result.allocations.isEmpty); XCTAssertNil(result.shortages.first?.required)
        XCTAssertNil(result.shortages.first?.unallocated); XCTAssertEqual(result.physicalStock[0], raw)
    }
    func testPastPlansExcludedUntilExactBatchIsSelectedAndFutureScopeHasNoSevenDayCap() throws {
        let raw = lot(1000), old = meal("Old", amount: 100, on: "2026-11-01", batchID: "old"), future = meal("Far", amount: 200, on: "2027-02-03", batchID: "far")
        let plans = [plan(old, on: "2026-11-01"), plan(future, on: "2027-02-03")]
        let ordinary = try snapshot(plans, [raw]); XCTAssertEqual(ordinary.reserved(in: raw.id), 200)
        XCTAssertEqual(ordinary.excludedPastMeals, 1)
        let selectedOld = try snapshot(plans, [raw], include: "old"); XCTAssertEqual(selectedOld.reserved(in: raw.id), 300)
        XCTAssertNotEqual(ordinary.sourceFingerprint, selectedOld.sourceFingerprint)
    }
    func testConflictingLinkedDefinitionsAndDuplicateSourcesFailClosed() throws {
        let raw = lot(1000); let first = meal("First", amount: 100, on: day, batchID: "batch")
        var changed = first; changed.id = "Other"; changed.cookingBatch?.totalPortions = 2
        let result = try snapshot([plan(first, on: day), plan(changed, on: "2026-11-04")], [raw])
        XCTAssertEqual(result.requirements[0].state, .needsReview); XCTAssertTrue(result.allocations.isEmpty)
        XCTAssertThrowsError(try snapshot([plan(first, on: day), plan(first, on: day)], [raw]))
    }
    func testUnitConversionAndSnapshotRoundTripKeepExactPlannedAndPhysicalAmounts() throws {
        let raw = lot(1, unit: "kg"), source = meal("Source", amount: 350, on: day, batchID: "batch")
        let original = try snapshot([plan(source, on: day)], [raw])
        XCTAssertEqual(original.reserved(in: raw.id), 0.35, accuracy: 0.000001)
        let restored = try JSONDecoder().decode(InventoryReservationSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        var changed = raw; changed.quantity = 2
        XCTAssertThrowsError(try InventoryReservationRules.validateCooking(batch: source.cookingBatch!, selectedLots: [0: raw.id], snapshot: restored, stock: [changed]))
    }
    func testReservationServiceRestoresAdvisoryCacheButFailedRefreshIsNotZeroOrFresh() async throws {
        let auth = MockAuthService(); auth.currentUserID = "reservation-owner"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory), repository = MockNutritionRepository()
        let raw = lot(500), source = meal("First", amount: 300, on: day, batchID: "first")
        repository.mockPantryItemsByID[raw.id] = raw; repository.mockMealPlansByDateString[day] = plan(source, on: day)
        let service = InventoryReservationService(drafts: store, auth: auth)
        let refreshed = await service.refresh(using: repository, now: date(day)); XCTAssertTrue(refreshed)
        XCTAssertTrue(service.isFresh); XCTAssertEqual(service.snapshot?.reserved(in: raw.id), 300)
        let restarted = InventoryReservationService(drafts: store, auth: auth)
        XCTAssertEqual(restarted.snapshot?.reserved(in: raw.id), 300); XCTAssertFalse(restarted.isFresh)
        repository.mealPlanError = URLError(.timedOut)
        let failed = await restarted.refresh(using: repository, now: date(day)); XCTAssertFalse(failed)
        XCTAssertEqual(restarted.snapshot?.reserved(in: raw.id), 300); XCTAssertFalse(restarted.isFresh); XCTAssertNotNil(restarted.errorMessage)
    }
    func testReservationCacheAndLateServiceUseStayAccountScoped() async throws {
        let auth = MockAuthService(); auth.currentUserID = "reservation-owner"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory), repository = MockNutritionRepository()
        repository.mockMealPlansByDateString[day] = plan(meal("First", amount: 100, on: day), on: day)
        let service = InventoryReservationService(drafts: store, auth: auth)
        let refreshed = await service.refresh(using: repository, now: date(day)); XCTAssertTrue(refreshed)
        auth.currentUserID = "another-owner"
        XCTAssertNil(service.snapshot)
        let denied = await service.refresh(using: repository, now: date(day)); XCTAssertFalse(denied)
        let other = InventoryReservationService(drafts: store, auth: auth)
        XCTAssertNil(other.snapshot)
    }
    func testCivilSourceDaySkippedInNewTimezoneDoesNotInvalidateUnrelatedCurrentReservations() throws {
        let originalZone = NSTimeZone.default
        let raw = lot(500), future = meal("First", amount: 100, on: day)
        let old = MealPlanDay(id: "2011-12-30", date: Date(timeIntervalSince1970: 1_325_203_200), meals: [])
        let now = date(day), current = plan(future, on: day)
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Pacific/Apia"))
        defer { NSTimeZone.default = originalZone }
        let result = try InventoryReservationRules.snapshot(plans: [old, current], stock: [raw], referenceDayID: day, now: now)
        XCTAssertEqual(result.reserved(in: raw.id), 100)
    }
    func testExplicitReallocationCannotExceedPhysicalStockOrUseUnknownExpiredPreparation() throws {
        var source = meal("First", amount: 300, on: day, batchID: "first")
        source.cookingBatch?.ingredientsPerPortion.append(MealCookingIngredient(IngredientLineParser.normalizedIngredient(from: "300 g Rice")))
        let raw = lot(500), batch = try XCTUnwrap(source.cookingBatch)
        let result = try snapshot([plan(source, on: day)], [raw])
        XCTAssertThrowsError(try InventoryReservationRules.validateCooking(batch: batch, selectedLots: [0: raw.id, 1: raw.id], snapshot: result, stock: [raw], allowReallocation: true))
        for state in 0..<3 {
            var unavailable = raw
            if state == 0 { unavailable.quantityVerified = nil }
            if state == 1 { unavailable.preparation = "Unknown" }
            if state == 2 { unavailable.bestBefore = date("2026-11-02") }
            let checked = try snapshot([plan(source, on: day)], [unavailable])
            XCTAssertThrowsError(try InventoryReservationRules.validateCooking(batch: batch, selectedLots: [0: unavailable.id], snapshot: checked, stock: [unavailable], allowReallocation: true))
        }
    }
}
