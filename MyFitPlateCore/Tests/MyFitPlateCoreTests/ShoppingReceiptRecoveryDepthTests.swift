import XCTest
@testable import MyFitPlateCore

@MainActor
final class ShoppingReceiptRecoveryDepthTests: XCTestCase {
    private var auth: MockAuthService!
    private var previous: AuthServiceProtocol!
    private var directory: URL!
    private var drafts: EditorDraftStore!
    override func setUp() {
        previous = DIContainer.shared.authService; auth = MockAuthService(); auth.currentUserID = "reviewer"
        DIContainer.shared.authService = auth
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        drafts = EditorDraftStore(directory: directory)
    }
    override func tearDown() { DIContainer.shared.authService = previous; try? FileManager.default.removeItem(at: directory) }
    func testCancellationFencesEveryDependentReviewAndRestoresOnlyExplicitNewReview() async throws {
        let repository = MockNutritionRepository()
        let initial = GroceryListItem(name: "Rice", quantity: 100, unit: "g")
        repository.mockFetchGroceryListResult = [initial]
        let session = GroceryChecklistSession(userID: "reviewer", store: drafts)
        XCTAssertTrue(session.installRemote([initial]))
        var first = initial; first.quantity = 200
        XCTAssertTrue(session.stage([first]))
        var second = session.items[0]; second.quantity = 300
        XCTAssertTrue(session.stage([second]))
        let frozen = session.checkpoint.operations
        let cancelledAll = await session.cancelAllPending(using: repository); XCTAssertTrue(cancelledAll)
        XCTAssertEqual(session.pendingCount, 0); XCTAssertEqual(session.cancelledDrafts.count, 2)
        XCTAssertEqual(session.items, [initial])
        for mutation in frozen { do { try await repository.applyGroceryMutation(userID: "reviewer", mutation: mutation); XCTFail("Cancelled exact operation replayed") } catch {} }
        let restored = GroceryChecklistSession(userID: "reviewer", store: drafts)
        let cancelled = try XCTUnwrap(restored.cancelledDrafts.last)
        let fresh = GroceryListMutation(before: restored.items, upserts: cancelled.mutation.upserts, removedIDs: [], title: "Explicit new review")
        XCTAssertTrue(restored.stageReviewedCancelledDraft(cancelled, proposal: fresh))
        await restored.retry(using: repository)
        XCTAssertEqual(restored.items.first?.quantity, 300)
        XCTAssertEqual(restored.cancelledDrafts.last?.restoredBy, fresh.id)
    }
    func testStatusAfterAcknowledgementLossKeepsAcceptedHistoryAndUnrelatedRows() async throws {
        let repository = MockNutritionRepository()
        let first = GroceryListItem(name: "Rice", quantity: 100, unit: "g")
        repository.mockFetchGroceryListResult = [first]
        let session = GroceryChecklistSession(userID: "reviewer", store: drafts)
        XCTAssertTrue(session.installRemote([first])); var changed = first; changed.quantity = 200
        XCTAssertTrue(session.stage([changed]))
        repository.groceryMutationFailureAfterCommit = URLError(.timedOut)
        await session.retry(using: repository); XCTAssertEqual(session.pendingCount, 1)
        let other = GroceryListItem(name: "Milk", quantity: 1, unit: "L")
        repository.mockFetchGroceryListResult.append(other)
        await session.checkSavedStatus(using: repository)
        XCTAssertEqual(session.pendingCount, 0); XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.items.count, 2)
    }
    func testCancellationRecordsAcceptedPrefixWithoutErasingDependentDesiredValues() async throws {
        let repository = MockNutritionRepository(), session = GroceryChecklistSession(userID: "reviewer", store: drafts)
        let original = GroceryListItem(name: "Rice", quantity: 100, unit: "g")
        repository.mockFetchGroceryListResult = [original]; XCTAssertTrue(session.installRemote([original]))
        var first = original; first.quantity = 200; XCTAssertTrue(session.stage([first]))
        let accepted = try XCTUnwrap(session.checkpoint.operations.first)
        var later = session.items[0]; later.quantity = 300; XCTAssertTrue(session.stage([later]))
        try await repository.applyGroceryMutation(userID: "reviewer", mutation: accepted)
        let cancelledAll = await session.cancelAllPending(using: repository); XCTAssertTrue(cancelledAll)
        XCTAssertEqual(session.items.first?.quantity, 200); XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.cancelledDrafts.first?.mutation.upserts.first?.quantity, 300)
    }
    func testAtomicReceiptFailureDoesNotImportAValidPrefixAndRetriesAllRowsOnce() async throws {
        let repository = MockNutritionRepository()
        let apple = PantryItem(name: "Apple", quantity: 2, unit: "item"), milk = PantryItem(name: "Milk", quantity: 1, unit: "L")
        repository.pantryItemErrors[milk.id] = URLError(.timedOut)
        let session = PantryReceiptImportSession(userID: "reviewer", items: [apple, milk], store: drafts)
        await session.save(using: repository)
        XCTAssertTrue(repository.mockPantryItemsByID.isEmpty); XCTAssertTrue(session.isSubmitted)
        let exact = try XCTUnwrap(session.checkpoint.ledgerMutation)
        let restored = PantryReceiptImportSession(userID: "reviewer", store: drafts)
        XCTAssertEqual(restored.checkpoint.ledgerMutation?.id, exact.id)
        repository.pantryItemErrors = [:]; await restored.save(using: repository)
        XCTAssertTrue(restored.isComplete); XCTAssertEqual(repository.mockPantryItemsByID.count, 2)
        await restored.save(using: repository); XCTAssertEqual(repository.savedPantryItems.count, 2)
    }
    func testSameReceiptDigestCannotImportDifferentOrAdditionalRowsAfterLocalHistoryLoss() async throws {
        let repository = MockNutritionRepository(), purchaseDate = Date()
        let first = PantryReceiptImportSession(userID: "reviewer", store: drafts)
        XCTAssertTrue(first.replaceSource(items: [PantryItem(name: "Apple", quantity: 2, unit: "item")], purchaseDate: purchaseDate, digest: "same-source"))
        await first.save(using: repository); XCTAssertTrue(first.isComplete); XCTAssertTrue(first.finish())
        try drafts.remove(userID: "reviewer", scope: "pantry-receipt-import-history")
        let other = PantryReceiptImportSession(userID: "reviewer", store: drafts)
        XCTAssertTrue(other.replaceSource(items: [PantryItem(name: "Milk", quantity: 1, unit: "L"), PantryItem(name: "Sauce", quantity: 1, unit: "item")], purchaseDate: purchaseDate, digest: "same-source"))
        await other.save(using: repository)
        XCTAssertFalse(other.isComplete); XCTAssertTrue(other.needsDuplicateDecision)
        XCTAssertEqual(repository.mockPantryItemsByID.count, 1)
        await other.beginSeparateImport(using: repository)
        XCTAssertFalse(other.isSubmitted); XCTAssertTrue(other.hasConfirmedSeparateImport)
        await other.save(using: repository)
        XCTAssertTrue(other.isComplete); XCTAssertEqual(repository.mockPantryItemsByID.count, 3)
    }
    func testReceiptSignatureNormalizesOnlyCompatibleUnitsAndCapturesCivilDay() throws {
        let day = Date(), id = UUID()
        let gram = PantryItem(id: id, name: "Rice", quantity: 1000, unit: "g")
        let kilogram = PantryItem(id: UUID(), name: "rice", quantity: 1, unit: "kg")
        let package = PantryItem(name: "Rice", quantity: 1, unit: "package")
        let a = try PantryReceiptIdentityRules.contentSignature(items: [gram], purchaseDate: day, purchaseDayKey: "2026-11-02")
        XCTAssertEqual(a, try PantryReceiptIdentityRules.contentSignature(items: [kilogram], purchaseDate: day, purchaseDayKey: "2026-11-02"))
        XCTAssertNotEqual(a, try PantryReceiptIdentityRules.contentSignature(items: [package], purchaseDate: day, purchaseDayKey: "2026-11-02"))
        XCTAssertNotEqual(a, try PantryReceiptIdentityRules.contentSignature(items: [gram], purchaseDate: day, purchaseDayKey: "2026-11-03"))
    }
    func testOptionalPrintedLinePriceAndStoreContextFreezeIndependentlyFromBoughtQuantity() async throws {
        let repository = MockNutritionRepository()
        var item = PantryItem(name: "Rice", quantity: 2, unit: "package")
        var evidence = PantryPurchaseEvidence(originalReceiptName: "RCE PKG", receiptRowQuantity: 2, receiptRowUnit: "count")
        evidence.printedLinePriceText = "4.75"; item.purchaseEvidence = evidence
        let session = PantryReceiptImportSession(userID: "reviewer", items: [item], store: drafts)
        XCTAssertTrue(session.updateContext(storeName: "Review Store", currency: "usd"))
        repository.inventoryFailureBeforeCommit = URLError(.timedOut)
        await session.save(using: repository)
        let frozen = try XCTUnwrap(session.checkpoint.ledgerMutation)
        XCTAssertEqual(frozen.after.first?.quantity, 2); XCTAssertEqual(frozen.after.first?.unit, "package")
        XCTAssertEqual(frozen.after.first?.purchaseEvidence?.reviewedPrice, 4.75)
        XCTAssertEqual(frozen.after.first?.purchaseEvidence?.currency, "USD")
        XCTAssertEqual(frozen.after.first?.purchaseEvidence?.storeName, "Review Store")
        XCTAssertEqual(frozen.after.first?.purchaseEvidence?.originalReceiptName, "RCE PKG")
        XCTAssertFalse(session.updateContext(storeName: "Changed", currency: "EUR"))
        let restored = PantryReceiptImportSession(userID: "reviewer", store: drafts)
        XCTAssertEqual(try restored.checkpoint.ledgerMutation?.fingerprint(), try frozen.fingerprint())
        repository.inventoryFailureBeforeCommit = nil; await restored.save(using: repository)
        XCTAssertEqual(repository.mockPantryItemsByID[item.id]?.purchaseEvidence?.reviewedPrice, 4.75)
        XCTAssertNil(repository.mockPantryItemsByID[item.id]?.productSnapshot, "A printed price is not a package or nutritional serving")
    }
    func testInvalidUnfinishedPriceTextSurvivesRelaunchAndCannotBecomeStockOrZero() async throws {
        let repository = MockNutritionRepository()
        var item = PantryItem(name: "Rice", quantity: 2, unit: "package")
        var evidence = PantryPurchaseEvidence(); evidence.printedLinePriceText = "4..75"; item.purchaseEvidence = evidence
        let session = PantryReceiptImportSession(userID: "reviewer", items: [item], store: drafts)
        let restored = PantryReceiptImportSession(userID: "reviewer", store: drafts)
        XCTAssertEqual(restored.items.first?.purchaseEvidence?.printedLinePriceText, "4..75")
        await restored.save(using: repository)
        XCTAssertFalse(restored.isSubmitted); XCTAssertTrue(repository.mockPantryItemsByID.isEmpty)
        evidence.printedLinePriceText = ""; item.purchaseEvidence = evidence
        XCTAssertTrue(session.update(items: [item], purchaseDate: session.checkpoint.purchaseDate))
        XCTAssertNil(session.items.first?.purchaseEvidence?.reviewedPrice)
    }
}
