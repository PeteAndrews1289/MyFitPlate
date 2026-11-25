import MyFitPlateCore
import SwiftUI

struct ManualGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "item"
    @State private var category = "Misc"
    @State private var product: GroceryProductSnapshot?
    @State private var packageQuantity = ""
    @State private var packageUnit = "g"
    @State private var overrideReason = "Personal shopping amount"
    @State private var ready = false
    @State private var newItemID = UUID()
    @State private var operationID = UUID()
    @State private var editingOriginal: GroceryListItem?
    @State private var shoppingStartDate: Date?
    @State private var draftBarcode: String?
    @State private var expectedFingerprint: String?
    @State private var draftError: String?
    @State private var unreadable = false
    @State private var finished = false
    @State private var restored = false
    @State private var confirmingDiscard = false
    @State private var unitNeedsReview = false
    @State private var unitReviewed = false
    @State private var ownerID = DIContainer.shared.authService.currentUserID

    var initialItem: GroceryListItem?
    var initialBarcode: String?
    var initialProduct: GroceryProductSnapshot?
    var initialShoppingStartDate: Date?
    var onReviewedSave: ((GroceryListItem, GroceryListItem?, UUID) -> Bool)?
    let onAdd: (GroceryListItem) -> Void
    private var originalItem: GroceryListItem? { ready ? editingOriginal : initialItem }
    private var draft: GroceryManualDraft {
        GroceryManualDraft(operationID: operationID, itemID: newItemID, original: editingOriginal, shoppingStartDate: shoppingStartDate,
            name: name, quantity: quantity, unit: unit, category: category, barcode: preservedBarcode, product: product,
            packageQuantity: packageQuantity, packageUnit: packageUnit, overrideReason: overrideReason)
    }
    private var draftFingerprint: String? { try? PlanFingerprint.make(draft) }

    private let commonUnits = [
        "item", "meal use", "oz", "lb", "g", "kg", "ml", "L", "fl oz",
        "cup", "tbsp", "tsp", "serving", "package", "carton", "clove", "fillet", "tub", "bag", "bottle"
    ]

    private var availableCategories: [String] {
        let normalized = GroceryListBuilder.normalizedCategory(category)
        return GroceryListBuilder.standardCategories.contains(normalized)
            ? GroceryListBuilder.standardCategories
            : [normalized] + GroceryListBuilder.standardCategories
    }

    private var availableUnits: [String] {
        commonUnits.contains(unit) ? commonUnits : [unit] + commonUnits
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var quantityValue: Double {
        let normalized = quantity.replacingOccurrences(of: ",", with: ".")
        return max(Double(normalized) ?? 1, 0)
    }

    private var canSave: Bool {
        guard !unreadable, !finished, !unitNeedsReview || unitReviewed, ownerID == DIContainer.shared.authService.currentUserID else { return false }
        guard !trimmedName.isEmpty, let amount = Double(quantity.replacingOccurrences(of: ",", with: ".")), amount.isFinite else { return false }
        if !packageQuantity.isEmpty {
            guard let package = Double(packageQuantity.replacingOccurrences(of: ",", with: ".")), package.isFinite, package > 0, package <= 1_000_000 else { return false }
        }
        return originalItem?.quantityUnknown == true ? amount > 0 : amount >= 0
    }

    private var screenTitle: String {
        originalItem == nil ? "Add Grocery Item" : "Edit Grocery Item"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Grocery List",
                        title: screenTitle,
                        subtitle: editorSubtitle
                    )

                    itemDetailsSection
                    if restored {
                        Text("Restored this unfinished shopping review and its original period from this device.").appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if let shoppingStartDate { Text("Shopping period: \(shoppingStartDate.formatted(date: .abbreviated, time: .omitted))").appTextRole(.secondary).foregroundStyle(.secondary) }
                    if let draftError { Text(draftError).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("grocery_manual_error") }
                    if unitNeedsReview { Toggle("I've checked the amount in this new unit", isOn: $unitReviewed).frame(minHeight: 44) }
                    if product != nil { productSection }
                    if originalItem?.source == "mealPlan" {
                        VStack(alignment: .leading, spacing: AppSpacing.row) {
                            AppSectionHeader(title: "Shopping override", subtitle: "Your recipe requirement stays inspectable. A larger future requirement asks you to review this override again.")
                            TextField("Reason", text: $overrideReason)
                        }.appSurface(.quiet)
                    }
                    categorySection
                    if restored || unreadable {
                        Button("Discard only this editor draft", role: .destructive) { confirmingDiscard = true }.frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("grocery_manual_editor")
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Grocery Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if unreadable || persistDraft() { dismiss() } }
                        .tint(AppPalette.brand)
                        .accessibilityHint("Keeps the unfinished editor on this device without adding or editing a shopping row")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveItem) {
                    Label(originalItem == nil ? "Add Item" : "Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!canSave)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("grocery_manual_action")
            }
        }
        .onAppear(perform: loadInitialItem)
        .onChange(of: draftFingerprint) { _, _ in if ready && !finished { _ = persistDraft() } }
        .confirmationDialog("Discard this shopping editor draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard editor draft", role: .destructive, action: discardDraft)
            Button("Keep editing", role: .cancel) {}
        } message: { Text("Only this unfinished editor is removed. The shopping list, acknowledged purchases and pending shopping operations stay intact.") }
    }

    private var itemDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Item Details",
                subtitle: "Use the amount you expect to buy."
            )

            if let barcode = preservedBarcode {
                AppListRow(
                    icon: "barcode",
                    iconColor: AppPalette.brand,
                    title: product == nil ? "Barcode preserved" : "Selected product barcode",
                    subtitle: barcode
                )
                .accessibilityIdentifier("grocery_manual_barcode")
            }

            GroceryFormField(title: "Name") {
                TextField("Chicken breast, blueberries, paper towels", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("grocery_manual_name")
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.row) {
                    quantityField
                    unitField
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    quantityField
                    unitField
                }
            }
        }
        .appSurface(.quiet)
    }

    private var quantityField: some View {
        GroceryFormField(title: "Quantity") {
            TextField(originalItem?.quantityUnknown == true ? "Enter measured amount" : "1", text: $quantity)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("grocery_manual_quantity")
        }
    }

    private var unitField: some View {
        GroceryFormField(title: "Unit") {
            Picker("Unit", selection: Binding(get: { unit }, set: { selected in
                if let amount = Double(quantity.replacingOccurrences(of: ",", with: ".")),
                   let converted = InventoryQuantityRules.convert(amount, from: unit, to: selected) {
                    quantity = converted.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...6)))
                } else if originalItem != nil { unitNeedsReview = true; unitReviewed = false }
                unit = selected
            })) {
                ForEach(availableUnits, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(AppPalette.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("grocery_manual_unit")
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Shopping Category",
                subtitle: "Items are grouped by aisle in your list."
            )

            Picker("Category", selection: $category) {
                ForEach(availableCategories, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(AppPalette.text)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("grocery_manual_category")
        }
        .appSurface(.quiet)
    }

    private func loadInitialItem() {
        guard !ready else { return }
        editingOriginal = initialItem; shoppingStartDate = initialShoppingStartDate ?? initialItem?.sourcePlanStart
        draftBarcode = initialItem?.barcode ?? initialBarcode ?? initialProduct?.barcode
        product = initialItem?.productSnapshot ?? initialProduct
        packageQuantity = product?.packageQuantity.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...3))) } ?? ""
        packageUnit = product?.packageUnit ?? "g"
        if let initialProduct, initialItem == nil { name = initialProduct.name; unit = "package" }
        if let item = initialItem {
        name = item.name
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = item.quantity == floor(item.quantity) ? 0 : 2
        quantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
        if item.quantityUnknown == true { quantity = "" }
        unit = item.unit
        category = GroceryListBuilder.normalizedCategory(item.category)
        overrideReason = item.quantityOverride?.reason ?? "Personal shopping amount"
        }
        do {
            if let saved = try GroceryManualDraftStore(userID: ownerID).load() {
                operationID = saved.operationID; newItemID = saved.itemID; editingOriginal = saved.original
                shoppingStartDate = saved.shoppingStartDate; name = saved.name; quantity = saved.quantity; unit = saved.unit
                category = saved.category; draftBarcode = saved.barcode; product = saved.product
                packageQuantity = saved.packageQuantity; packageUnit = saved.packageUnit; overrideReason = saved.overrideReason
                expectedFingerprint = try PlanFingerprint.make(saved); restored = true
            }
        } catch { unreadable = true; draftError = "Your earlier grocery editor could not be opened. It has been kept; no shopping rows have changed." }
        ready = true
        if let original = editingOriginal, InventoryQuantityRules.convert(1, from: original.unit, to: unit) == nil {
            unitNeedsReview = true; unitReviewed = false
        }
        if !unreadable { _ = persistDraft() }
    }

    private func saveItem() {
        guard canSave else { return }
        var newItem = originalItem ?? GroceryListItem(
            id: newItemID,
            name: trimmedName,
            quantity: quantityValue,
            unit: unit,
            category: GroceryListBuilder.normalizedCategory(category),
            source: preservedBarcode == nil ? "manual" : "barcode",
            barcode: preservedBarcode
        )
        newItem.name = trimmedName
        newItem.quantity = originalItem.flatMap { original in
            unit == original.unit && quantity == Self.quantityText(original.quantity) ? original.quantity : nil
        } ?? quantityValue
        newItem.quantityUnknown = false
        newItem.unit = unit
        newItem.category = GroceryListBuilder.normalizedCategory(category)
        newItem.barcode = preservedBarcode
        newItem.sourcePlanStart = newItem.sourcePlanStart ?? shoppingStartDate
        if product != nil {
            product?.packageQuantity = Double(packageQuantity.replacingOccurrences(of: ",", with: "."))
            product?.packageUnit = packageQuantity.isEmpty ? nil : packageUnit
            newItem.productSnapshot = product
        }
        if let original = originalItem, original.source == "mealPlan",
           original.quantity != newItem.quantity || original.unit != newItem.unit || original.quantityUnknown == true || original.quantityOverride?.requiresReview == true {
            newItem.quantityOverride = GroceryRequirementOverride(
                sourceQuantity: original.quantityOverride?.requiresReview == true ? original.quantity : original.quantityOverride?.sourceQuantity ?? (original.quantityUnknown == true ? nil : original.quantity),
                sourceUnit: original.quantityOverride?.requiresReview == true ? original.unit : original.quantityOverride?.sourceUnit ?? original.unit,
                buyQuantity: newItem.quantity, buyUnit: newItem.unit,
                reason: overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Personal shopping amount" : overrideReason)
        }
        guard persistDraft() else { return }
        if let onReviewedSave {
            guard onReviewedSave(newItem, originalItem, operationID) else {
                draftError = "This shopping change could not be kept. Your fields are still here; a changed row needs refreshed review."
                return
            }
        } else { onAdd(newItem) }
        finished = true
        if let expectedFingerprint {
            do { try GroceryManualDraftStore(userID: ownerID).clear(expectedFingerprint: expectedFingerprint) } catch {
                draftError = "The shopping change is kept. Its earlier editor checkpoint could not be cleared; retrying this same review uses the same operation ID."
            }
        }
        dismiss()
    }

    private var preservedBarcode: String? {
        let value = ready ? draftBarcode : initialItem?.barcode ?? initialBarcode ?? initialProduct?.barcode
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private var editorSubtitle: String {
        if preservedBarcode != nil {
            return "Name this item once while keeping the scanned code for future matching."
        }
        return originalItem == nil
            ? "Add something outside the current meal plan."
            : "Update the name, amount, or shopping category."
    }
    @discardableResult private func persistDraft() -> Bool {
        guard ready, !unreadable, !finished else { return false }
        do {
            let meaningful = editingOriginal != nil || !trimmedName.isEmpty || preservedBarcode != nil || product != nil || quantity != "1" || unit != "item"
            if !meaningful {
                if let expectedFingerprint { try GroceryManualDraftStore(userID: ownerID).clear(expectedFingerprint: expectedFingerprint); self.expectedFingerprint = nil }
                return true
            }
            expectedFingerprint = try GroceryManualDraftStore(userID: ownerID).save(draft, expectedFingerprint: expectedFingerprint)
            return true
        } catch { draftError = "Your previous shopping draft is kept. " + error.localizedDescription; return false }
    }
    private func discardDraft() {
        do {
            let store = GroceryManualDraftStore(userID: ownerID)
            if let expectedFingerprint { try store.clear(expectedFingerprint: expectedFingerprint) } else if unreadable { try store.discardCorrupt() }
            finished = true; dismiss()
        } catch { draftError = "The draft changed and has been kept. " + error.localizedDescription }
    }
    private static func quantityText(_ amount: Double) -> String {
        let formatter = NumberFormatter(); formatter.maximumFractionDigits = amount == floor(amount) ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Package and serving", subtitle: "Buy quantity is separate from the food's nutritional serving.")
            Text(product?.brand ?? "Brand not reported").appTextRole(.secondary).foregroundStyle(.secondary)
            Text("Reported nutrition serving: \(product?.reportedServingDescription ?? "Not reported")")
                .appTextRole(.secondary).accessibilityIdentifier("grocery_product_serving")
            Text("Package size is unknown until you check its label. A 100 g nutrition serving does not establish a 100 g package.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            TextField("Optional amount in one package", text: $packageQuantity).keyboardType(.decimalPad)
                .frame(minHeight: 44).accessibilityIdentifier("grocery_product_package_amount")
            Picker("Package measure", selection: Binding(get: { packageUnit }, set: { selected in
                if let amount = Double(packageQuantity.replacingOccurrences(of: ",", with: ".")),
                   let converted = InventoryQuantityRules.convert(amount, from: packageUnit, to: selected) {
                    packageQuantity = converted.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...6)))
                }
                packageUnit = selected
            })) {
                ForEach(["g", "kg", "ml", "L", "oz", "lb", "fl oz", "item"], id: \.self) { Text($0).tag($0) }
            }.frame(minHeight: 44)
        }.appSurface(.quiet)
    }
}

private struct GroceryFormField<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)

            content
                .appTextRole(.body)
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, AppSpacing.row)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
