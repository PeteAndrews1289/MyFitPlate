import SwiftUI

struct ManualGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "item"
    @State private var category = "Misc"

    var initialItem: GroceryListItem?
    let onAdd: (GroceryListItem) -> Void

    private let commonUnits = [
        "item", "meal use", "oz", "lb", "g", "kg", "ml", "L", "fl oz",
        "cup", "tbsp", "tsp", "serving", "clove", "fillet", "tub", "bag", "bottle"
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
        !trimmedName.isEmpty
    }

    private var screenTitle: String {
        initialItem == nil ? "Add Grocery Item" : "Edit Grocery Item"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Grocery List",
                        title: screenTitle,
                        subtitle: initialItem == nil
                            ? "Add something outside the current meal plan."
                            : "Update the name, amount, or shopping category."
                    )

                    itemDetailsSection
                    categorySection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Grocery Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: saveItem) {
                    Label(initialItem == nil ? "Add Item" : "Save Changes", systemImage: "checkmark")
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
        .accessibilityIdentifier("grocery_manual_editor")
        .onAppear(perform: loadInitialItem)
    }

    private var itemDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Item Details",
                subtitle: "Use the amount you expect to buy."
            )

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
            TextField("1", text: $quantity)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("grocery_manual_quantity")
        }
    }

    private var unitField: some View {
        GroceryFormField(title: "Unit") {
            Picker("Unit", selection: $unit) {
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
        guard let item = initialItem else { return }
        name = item.name
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = item.quantity == floor(item.quantity) ? 0 : 2
        quantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
        unit = item.unit
        category = GroceryListBuilder.normalizedCategory(item.category)
    }

    private func saveItem() {
        var newItem = initialItem ?? GroceryListItem(
            name: trimmedName,
            quantity: quantityValue,
            unit: unit,
            category: GroceryListBuilder.normalizedCategory(category),
            source: "manual"
        )
        newItem.name = trimmedName
        newItem.quantity = quantityValue
        newItem.unit = unit
        newItem.category = GroceryListBuilder.normalizedCategory(category)
        onAdd(newItem)
        dismiss()
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
