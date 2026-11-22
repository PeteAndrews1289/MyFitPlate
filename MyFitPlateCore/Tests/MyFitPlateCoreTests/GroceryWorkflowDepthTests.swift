import XCTest
@testable import MyFitPlateCore

@MainActor
final class GroceryWorkflowDepthTests: XCTestCase {
    private func item(_ name: String = "Rice", quantity: Double = 400, unit: String = "g") -> GroceryListItem {
        GroceryListItem(name: name, quantity: quantity, unit: unit, source: "mealPlan", sourcePlanStart: Date(timeIntervalSince1970: 1_792_000_000))
    }
    private func draft(item: GroceryListItem? = nil) -> GroceryManualDraft {
        GroceryManualDraft(operationID: UUID(), itemID: item?.id ?? UUID(), original: item,
            shoppingStartDate: Date(timeIntervalSince1970: 1_792_000_000), name: "Scanned rice", quantity: "invalid unfinished text",
            unit: "package", category: "Pantry", barcode: "123456789012", product: nil,
            packageQuantity: "", packageUnit: "g", overrideReason: "Personal shopping amount")
    }
    private func temporaryStore() -> (EditorDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (EditorDraftStore(directory: directory), directory)
    }

    func testNutritionServingNeverBecomesPackageSize() {
        let food = FoodItem(id: "product", name: "Rice", calories: 350, servingSize: "100 g", servingWeight: 100)
        var product = GroceryProductSnapshot(food: food, barcode: "123456789012")
        XCTAssertEqual(product.reportedServingWeightGrams, 100)
        XCTAssertNil(product.packageQuantity); XCTAssertNil(product.packageUnit)
        product.packageQuantity = 500; product.packageUnit = "g"
        var row = item("Rice package", quantity: 2, unit: "package"); row.productSnapshot = product
        XCTAssertEqual(row.quantity, 2); XCTAssertEqual(row.unit, "package")
        XCTAssertEqual(row.productSnapshot?.packageQuantity, 500)
        XCTAssertEqual(row.productSnapshot?.reportedServingWeightGrams, 100)
    }

    func testNewMutationHasDeterministicRevisionsAndLegacyDecodeKeepsNil() throws {
        let original = item(); var checked = original; checked.isCompleted = true
        let mutation = GroceryListMutation(before: [original], upserts: [checked], removedIDs: [])
        XCTAssertEqual(mutation.upserts[0].revisionID, GroceryListMutation.revisionID(operationID: mutation.id, itemID: original.id))
        let first = try mutation.applying(to: [original]); let again = try mutation.applying(to: [original])
        XCTAssertEqual(first, again)
        let legacy = try JSONDecoder().decode(GroceryListItem.self, from: JSONEncoder().encode(original))
        XCTAssertNil(legacy.revisionID)
    }

    func testABAChangesCannotAuthorizeAnOlderPendingEdit() throws {
        let original = item(); var middle = original; middle.quantity = 500
        var intended = original; intended.quantity = 900
        let stale = GroceryListMutation(before: [original], upserts: [intended], removedIDs: [])
        let first = GroceryListMutation(before: [original], upserts: [middle], removedIDs: [])
        let afterFirst = try first.applying(to: [original])
        var returned = afterFirst[0]; returned.quantity = original.quantity
        let second = GroceryListMutation(before: afterFirst, upserts: [returned], removedIDs: [])
        let afterSecond = try second.applying(to: afterFirst)
        XCTAssertEqual(afterSecond[0].quantity, original.quantity)
        XCTAssertNotEqual(afterSecond[0].revisionID, original.revisionID)
        XCTAssertThrowsError(try stale.applying(to: afterSecond))
    }

    func testInverseChecksExactContentAndUsesFreshRevisionWithoutTouchingOtherRows() throws {
        let first = item(), other = item("Other", quantity: 50)
        var updated = first; updated.quantity = 600
        let operation = GroceryListMutation(before: [first], upserts: [updated], removedIDs: [], title: "Edit amount", shoppingStartDate: first.sourcePlanStart)
        let result = try operation.applying(to: [first, other])
        let inverse = operation.inverse(); XCTAssertNoThrow(try inverse.validateInverse(of: operation))
        let restored = try inverse.applying(to: result)
        XCTAssertEqual(restored[0].quantity, 400); XCTAssertEqual(restored[1], other)
        XCTAssertNotEqual(restored[0].revisionID, first.revisionID)
        var tampered = inverse; tampered.upserts[0].quantity += 1
        XCTAssertThrowsError(try tampered.validateInverse(of: operation))
        tampered = inverse; tampered.shoppingStartDate = Date.distantPast
        XCTAssertThrowsError(try tampered.validateInverse(of: operation))
    }

    func testSetEncodingIsCanonicalAcrossRepeatedCheckpointReloads() throws {
        let rows = (0..<15).map { item("Rice \($0)") }
        let mutation = GroceryListMutation(before: rows, upserts: [], removedIDs: Set(rows.map(\.id)))
        let fingerprint = try mutation.fingerprint
        for _ in 0..<40 {
            let restored = try JSONDecoder().decode(GroceryListMutation.self, from: JSONEncoder().encode(mutation))
            XCTAssertEqual(try restored.fingerprint, fingerprint)
        }
    }

    func testQuantityOverrideSurvivesRefreshButLargerRequirementRequiresReview() {
        let original = item(); var edited = original
        edited.quantity = 250
        edited.quantityOverride = GroceryRequirementOverride(sourceQuantity: 400, sourceUnit: "g", buyQuantity: 250, buyUnit: "g", reason: "Smaller shopping amount")
        let same = GroceryListBuilder.mergeGroceryItems(generatedItems: [original], existingItems: [edited])[0]
        XCTAssertEqual(same.quantity, 250); XCTAssertEqual(same.quantityOverride?.sourceQuantity, 400)
        var larger = original; larger.quantity = 600
        let changed = GroceryListBuilder.mergeGroceryItems(generatedItems: [larger], existingItems: [edited])[0]
        XCTAssertEqual(changed.quantity, 600); XCTAssertTrue(changed.quantityOverride?.requiresReview == true)
        XCTAssertFalse(changed.skippedForPlan == true)
    }

    func testOverrideCannotLeakIntoAnotherShoppingPeriod() {
        let original = item(); var edited = original; edited.skippedForPlan = true
        edited.quantityOverride = GroceryRequirementOverride(sourceQuantity: 400, sourceUnit: "g", buyQuantity: 0, buyUnit: "g")
        var next = original; next.sourcePlanStart = original.sourcePlanStart?.addingTimeInterval(7 * 86_400)
        let changed = GroceryListBuilder.mergeGroceryItems(generatedItems: [next], existingItems: [edited])[0]
        XCTAssertNil(changed.quantityOverride); XCTAssertFalse(changed.skippedForPlan == true); XCTAssertEqual(changed.quantity, 400)
    }

    func testReturningToAPurchasedWeekRestoresItsReceiptExactlyOnce() throws {
        var bought = item("Dry rice", quantity: 400)
        bought.isCompleted = true
        bought.purchasedQuantity = 400
        bought.transferredToPantryQuantity = 150
        let manual = GroceryListItem(name: "Tea", quantity: 1, unit: "item", source: "manual")
        var otherWeek = item("Dry rice", quantity: 200)
        otherWeek.sourcePlanStart = Calendar.current.date(byAdding: .day, value: 7, to: try XCTUnwrap(bought.sourcePlanStart))
        let away = GroceryListBuilder.mergeGroceryItems(generatedItems: [otherWeek], existingItems: [bought, manual])
        XCTAssertNil(away.first { $0.source == "mealPlan" }?.purchasedQuantity)
        XCTAssertTrue(away.contains { $0.id == bought.id && $0.source == "retainedPurchase" })

        let originalNeed = item("Dry rice", quantity: 400)
        let restored = GroceryListBuilder.mergeGroceryItems(generatedItems: [originalNeed], existingItems: away)
        XCTAssertEqual(restored, [bought, manual])
        XCTAssertEqual(GroceryListBuilder.mergeGroceryItems(generatedItems: [originalNeed], existingItems: restored), restored)
        // Earlier versions could already have saved an empty regenerated row beside the receipt.
        XCTAssertEqual(GroceryListBuilder.mergeGroceryItems(generatedItems: [originalNeed], existingItems: [originalNeed] + away), restored)
    }

    func testUnconvertedPurchaseSurvivesRemovingAndRestoringItsPlannedNeed() {
        let original = item()
        var reviewed = original
        reviewed.unconvertedPurchases = [.init(quantity: 2, unit: "bags", transferredToPantryQuantity: 1)]
        let removed = GroceryListBuilder.mergeGroceryItems(generatedItems: [], existingItems: [reviewed])
        XCTAssertEqual(removed.first?.source, "retainedPurchase")
        XCTAssertEqual(removed.first?.unconvertedPurchases, reviewed.unconvertedPurchases)
        XCTAssertEqual(GroceryListBuilder.mergeGroceryItems(generatedItems: [original], existingItems: removed), [reviewed])
    }

    func testSeparatePurchasesAndLegacyUndatedReceiptsKeepTheirOwnAmounts() {
        let need = item()
        var active = item()
        active.purchasedQuantity = 50
        var retained = item()
        retained.source = "retainedPurchase"
        retained.purchasedQuantity = 100
        var undated = retained
        undated.id = UUID()
        undated.sourcePlanStart = nil
        let rows = GroceryListBuilder.mergeGroceryItems(generatedItems: [need], existingItems: [undated, retained, active])
        XCTAssertEqual(rows.map(\.id), [active.id, undated.id, retained.id])
        XCTAssertEqual(rows.map(\.purchasedQuantity), [50, 100, 100])
        XCTAssertFalse(rows[0].isCompleted)
        let legacyOnly = GroceryListBuilder.mergeGroceryItems(generatedItems: [need], existingItems: [undated])
        XCTAssertNil(legacyOnly[0].purchasedQuantity)
        XCTAssertEqual(legacyOnly.last, undated)
    }

    func testStructuredExportPreservesUnknownAmountsAndRedactsCodesByDefault() throws {
        var unknown = item(); unknown.quantityUnknown = true; unknown.barcode = "123456789012"
        let snapshot = GroceryExportRules.document(items: [unknown], stock: [], starting: Date(), pendingChanges: true, stockCoverageAvailable: false)
        XCTAssertTrue(snapshot.containsPendingChanges); XCTAssertFalse(snapshot.stockCoverageAvailable)
        XCTAssertNil(snapshot.rows[0].required); XCTAssertNil(snapshot.rows[0].netToBuy); XCTAssertNil(snapshot.rows[0].confirmedStock)
        XCTAssertNil(snapshot.rows[0].barcode)
        let restored = try JSONSerialization.jsonObject(with: snapshot.jsonData()) as? [String: Any]
        XCTAssertEqual(restored?["schemaVersion"] as? Int, 1)
        XCTAssertTrue(snapshot.plainText.contains("awaiting account acknowledgement"))
    }

    func testExportFilteringAndOverrideRetainOriginalPlanQuantity() {
        let original = item(); var overridden = original; overridden.quantity = 700
        overridden.quantityOverride = GroceryRequirementOverride(sourceQuantity: 400, sourceUnit: "g", buyQuantity: 700, buyUnit: "g")
        var checked = item("Checked"); checked.isCompleted = true
        var skipped = item("Skipped"); skipped.skippedForPlan = true
        let selected = GroceryExportRules.document(items: [overridden, checked, skipped], stock: [], starting: Date())
        XCTAssertEqual(selected.rows.count, 1); XCTAssertEqual(selected.rows[0].required, 400); XCTAssertEqual(selected.rows[0].netToBuy, 700)
        XCTAssertTrue(selected.plainText.contains("Original plan: 400"))
        XCTAssertEqual(GroceryExportRules.document(items: [overridden, checked, skipped], stock: [], starting: Date(), includeChecked: true).rows.count, 3)
    }

    func testManualDraftRetainsCodeRangeInvalidTextAndRejectsStaleEditor() throws {
        let previous = DIContainer.shared.authService; let auth = MockAuthService(); auth.currentUserID = "shopper"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previous }
        let (store, directory) = temporaryStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = GroceryManualDraftStore(userID: "shopper", store: store)
        let original = draft(); let fingerprint = try drafts.save(original, expectedFingerprint: nil)
        let restored = try XCTUnwrap(drafts.load())
        XCTAssertEqual(restored.operationID, original.operationID); XCTAssertEqual(restored.barcode, "123456789012")
        XCTAssertEqual(restored.shoppingStartDate, original.shoppingStartDate); XCTAssertEqual(restored.quantity, "invalid unfinished text")
        var newer = restored; newer.name = "New correction"
        _ = try drafts.save(newer, expectedFingerprint: fingerprint)
        XCTAssertThrowsError(try drafts.clear(expectedFingerprint: fingerprint))
        XCTAssertEqual(try drafts.load()?.name, "New correction")
        auth.currentUserID = "another"; XCTAssertThrowsError(try drafts.load())
    }

    func testAcceptedRemovalHistoryAndConditionalUndoSurviveRelaunch() async throws {
        let previous = DIContainer.shared.authService; let auth = MockAuthService(); auth.currentUserID = "shopper"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previous }
        let (store, directory) = temporaryStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = item(), other = item("Other")
        let repository = MockNutritionRepository(); repository.mockFetchGroceryListResult = [first, other]
        let session = GroceryChecklistSession(userID: "shopper", store: store)
        XCTAssertTrue(session.installRemote([first, other]))
        XCTAssertTrue(session.stage([other], title: "Remove manual need", shoppingStartDate: first.sourcePlanStart))
        await session.retry(using: repository)
        let restored = GroceryChecklistSession(userID: "shopper", store: store)
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertTrue(restored.undo(restored.history[0], shoppingStartDate: first.sourcePlanStart))
        await restored.retry(using: repository)
        XCTAssertEqual(repository.mockFetchGroceryListResult.count, 2)
        XCTAssertEqual(repository.mockFetchGroceryListResult.first(where: { $0.id == first.id })?.quantity, 400)
        XCTAssertNotNil(restored.history[0].undoneBy)
    }

    func testStaleGroceryCheckpointCannotDropNewerPendingOperations() {
        let previous = DIContainer.shared.authService; let auth = MockAuthService(); auth.currentUserID = "shopper"; DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previous }
        let (store, directory) = temporaryStore(); defer { try? FileManager.default.removeItem(at: directory) }
        let first = GroceryChecklistSession(userID: "shopper", store: store)
        let stale = GroceryChecklistSession(userID: "shopper", store: store)
        XCTAssertTrue(first.stage([item("First")]))
        XCTAssertFalse(stale.stage([item("Second")]))
        let restored = GroceryChecklistSession(userID: "shopper", store: store)
        XCTAssertEqual(restored.items.map(\.name), ["First"]); XCTAssertEqual(restored.pendingCount, 1)
    }

    func testIncompatibleEarlierPackagePurchasesRemainInspectableAndFoldOnlyOnce() {
        var generated = item(quantity: 600, unit: "g"); generated.requirementKey = "rice|unspecified|mass"
        var old = generated; old.unit = "package"; old.quantity = 2; old.purchasedQuantity = 2; old.transferredToPantryQuantity = 1
        let changed = GroceryListBuilder.mergeGroceryItems(generatedItems: [generated], existingItems: [old])[0]
        XCTAssertNil(changed.purchasedQuantity)
        XCTAssertEqual(changed.unconvertedPurchases?.first?.quantity, 2)
        XCTAssertEqual(changed.unconvertedPurchases?.first?.unit, "package")
        let again = GroceryListBuilder.mergeGroceryItems(generatedItems: [generated], existingItems: [changed])[0]
        XCTAssertEqual(again.unconvertedPurchases?.count, 1)
        var packageRequirement = generated; packageRequirement.unit = "package"; packageRequirement.quantity = 3
        let folded = GroceryListBuilder.mergeGroceryItems(generatedItems: [packageRequirement], existingItems: [again])[0]
        XCTAssertEqual(folded.purchasedQuantity, 2); XCTAssertEqual(folded.transferredToPantryQuantity, 1)
        XCTAssertNil(folded.unconvertedPurchases)
    }
}
