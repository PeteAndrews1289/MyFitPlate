import XCTest
@testable import MyFitPlateCore

final class GroceryPresentationRulesTests: XCTestCase {
    func testRepeatedUnitPresentationAndNameEditKeepExactCanonicalQuantity() throws {
        var original = GroceryListItem(name: "Chicken", quantity: 2.333333333333, unit: "kg", source: "mealPlan")
        original.purchasedQuantity = 0.375; original.transferredToPantryQuantity = 0.125
        var current = original
        for _ in 0..<20 {
            for system in [GroceryUnitSystem.imperial, .metric] {
                let display = GroceryListBuilder.applyUnitSystem(current, system: system)
                current = GroceryPresentationRules.canonicalized([display], against: [original])[0]
                XCTAssertEqual(try PlanFingerprint.make(current), try PlanFingerprint.make(original))
            }
        }
        var edit = GroceryListBuilder.applyUnitSystem(original, system: .imperial)
        edit.name = "My chicken"
        let canonical = GroceryPresentationRules.canonicalized([edit], against: [original])[0]
        XCTAssertEqual(canonical.name, "My chicken")
        XCTAssertEqual(canonical.quantity, original.quantity)
        XCTAssertEqual(canonical.unit, original.unit)
        XCTAssertEqual(canonical.purchasedQuantity, original.purchasedQuantity)
    }
    func testEditedDisplayedAmountConvertsBackWithoutMassVolumeInference() {
        let original = GroceryListItem(name: "Chicken", quantity: 1, unit: "kg", source: "mealPlan")
        var display = GroceryListBuilder.applyUnitSystem(original, system: .imperial)
        display.quantity += 1
        let canonical = GroceryPresentationRules.canonicalized([display], against: [original])[0]
        XCTAssertEqual(canonical.quantity, 1.45359237, accuracy: 0.00000001)
        var incompatible = display; incompatible.unit = "package"
        XCTAssertEqual(GroceryPresentationRules.canonicalized([incompatible], against: [original])[0].unit, "package")
    }
    func testSameWeekReconciliationRetainsOriginalUnitAndPurchasedAmounts() {
        let date = Calendar.current.startOfDay(for: Date())
        var original = GroceryListItem(name: "Rice", quantity: 0.3, unit: "kg", source: "mealPlan", sourcePlanStart: date)
        original.purchasedQuantity = 0.2; original.transferredToPantryQuantity = 0.1
        let generated = GroceryListItem(name: "Rice", quantity: 300, unit: "g", source: "mealPlan", sourcePlanStart: date)
        let result = GroceryListBuilder.mergeGroceryItems(generatedItems: [generated], existingItems: [original])
        XCTAssertEqual(result[0].id, original.id)
        XCTAssertEqual(result[0].unit, "kg")
        XCTAssertEqual(result[0].quantity, 0.3)
        XCTAssertEqual(result[0].purchasedQuantity, 0.2)
        XCTAssertEqual(result[0].transferredToPantryQuantity, 0.1)
    }
    func testSharingMatchesRemainingNeedAndKeepsUnknownPackageSemantics() {
        let date = Calendar.current.startOfDay(for: Date())
        var stock = PantryItem(name: "Rice", quantity: 400, unit: "g")
        stock.quantityVerified = true; stock.preparation = "Raw"
        let rice = GroceryListItem(name: "Rice", quantity: 600, unit: "g", source: "mealPlan")
        let package = GroceryListItem(name: "Spinach", quantity: 1, unit: "package", source: "manual")
        let checked = GroceryListItem(name: "Coffee", quantity: 2, unit: "item", isCompleted: true, source: "manual")
        let text = GroceryPresentationRules.shareText(items: [rice, package, checked], stock: [stock], starting: date, includeChecked: false)
        XCTAssertTrue(text.contains("buy 200 g"))
        XCTAssertTrue(text.contains("buy 1 package"))
        XCTAssertFalse(text.contains("Coffee"))
        XCTAssertTrue(text.contains("weights stay unknown"))
        let all = GroceryPresentationRules.shareText(items: [rice, package, checked], stock: [stock], starting: date, includeChecked: true)
        XCTAssertTrue(all.contains("Coffee")); XCTAssertTrue(all.contains("checked"))
    }
}
