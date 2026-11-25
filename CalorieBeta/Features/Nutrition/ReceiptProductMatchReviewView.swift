import MyFitPlateCore
import SwiftUI

struct ReceiptProductMatchReviewView: View {
    let item: PantryItem
    let onReviewed: (PantryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingSearch = false
    @State private var pendingFood: FoodItem?
    @State private var product: GroceryProductSnapshot?
    @State private var packageAmount = ""
    @State private var packageUnit = "g"
    @State private var useProductName = false
    @State private var confirmed = false
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    init(item: PantryItem, onReviewed: @escaping (PantryItem) -> Void) {
        self.item = item; self.onReviewed = onReviewed
        _product = State(initialValue: item.productSnapshot)
        _packageAmount = State(initialValue: item.productSnapshot?.packageQuantity.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...3))) } ?? "")
        _packageUnit = State(initialValue: item.productSnapshot?.packageUnit ?? "g")
    }
    private var reviewedProduct: GroceryProductSnapshot? {
        guard var product else { return nil }
        if !packageAmount.isEmpty {
            guard let value = Double(packageAmount.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return nil }
            product.packageQuantity = value; product.packageUnit = packageUnit
        } else { product.packageQuantity = nil; product.packageUnit = nil }
        return product.isValid ? product : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Original receipt row") {
                    Text(item.name).appTextRole(.control)
                    Text("\(item.quantity.formatted()) \(item.unit)")
                    Text("Matching a product does not change this bought amount or convert packages into grams. Review measured stock separately.").foregroundStyle(.secondary)
                }
                Section("Product identity") {
                    Button("Search or scan a matching product") { showingSearch = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("receipt_product_search")
                    if let product {
                        Text(product.name).appTextRole(.control)
                        Text(product.brand ?? "Brand not reported").foregroundStyle(.secondary)
                        Text("Barcode: \(product.barcode.isEmpty ? "Not reported" : product.barcode)")
                        Text("Nutrition serving: \(product.reportedServingDescription ?? "Not reported")").foregroundStyle(.secondary)
                        Text("The nutrition serving is not the package size.").foregroundStyle(.secondary)
                        TextField("Optional package amount from its label", text: $packageAmount).keyboardType(.decimalPad)
                            .accessibilityIdentifier("receipt_product_package_amount")
                        Picker("Package measure", selection: $packageUnit) {
                            ForEach(["g", "kg", "ml", "L", "oz", "lb", "item"], id: \.self) { Text($0).tag($0) }
                        }
                        Toggle("Use the matched product name for this stock", isOn: $useProductName)
                        Toggle("I checked this product against the receipt", isOn: $confirmed)
                    }
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier("receipt_product_review")
            .navigationTitle("Review receipt product").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Use reviewed product") {
                    guard let product = reviewedProduct, confirmed, ownerID == DIContainer.shared.authService.currentUserID else { return }
                    var reviewed = item; reviewed.productSnapshot = product
                    if useProductName { reviewed.name = product.name }
                    onReviewed(reviewed); dismiss()
                }.buttonStyle(AppActionButtonStyle(.primary)).disabled(reviewedProduct == nil || !confirmed)
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                    .accessibilityIdentifier("receipt_product_confirm")
            }
            .sheet(isPresented: $showingSearch, onDismiss: {
                if let pendingFood {
                    product = GroceryProductSnapshot(food: pendingFood, barcode: pendingFood.sourceMetadata?.barcode ?? "")
                    self.pendingFood = nil; confirmed = false; packageAmount = ""
                }
            }) {
                FoodSearchView(dailyLog: .constant(nil), onFoodItemSelected: { food in pendingFood = food; showingSearch = false },
                    searchContext: "receipt_product", selectedMeal: "Lunch")
            }
        }
    }
}
