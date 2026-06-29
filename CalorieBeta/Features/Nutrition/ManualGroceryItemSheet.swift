import SwiftUI

struct ManualGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "item"
    @State private var category = "Misc"

    var initialItem: GroceryListItem?
    let onAdd: (GroceryListItem) -> Void

    private let categories = ["Produce", "Protein", "Carbohydrates", "Dairy", "Pantry", "Misc"]
    private let units = ["item", "meal use", "oz", "lb", "g", "cup", "tbsp", "tsp", "serving"]

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Item")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)

                        TextField("Chicken breast, blueberries, paper towels...", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(14)
                            .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        HStack(spacing: 10) {
                            TextField("Qty", text: $quantity)
                                .keyboardType(.decimalPad)
                                .padding(14)
                                .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .frame(maxWidth: 100)

                            Picker("Unit", selection: $unit) {
                                ForEach(units, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(categories, id: \.self) { option in
                                categoryButton(for: option)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(16)
                .padding(.bottom, 86)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Manual Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(initialItem == nil ? "Add Item" : "Save Changes") {
                    var newItem = initialItem ?? GroceryListItem(
                        name: trimmedName,
                        quantity: quantityValue,
                        unit: unit,
                        category: category,
                        source: "manual"
                    )
                    if initialItem != nil {
                        newItem.name = trimmedName
                        newItem.quantity = quantityValue
                        newItem.unit = unit
                        newItem.category = category
                    }
                    onAdd(newItem)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Color.backgroundPrimary.opacity(0.98).ignoresSafeArea(edges: .bottom))
            }
        }
        .onAppear {
            if let item = initialItem {
                name = item.name
                let formatter = NumberFormatter()
                formatter.maximumFractionDigits = 2
                if item.quantity == floor(item.quantity) {
                    formatter.maximumFractionDigits = 0
                }
                quantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
                unit = item.unit
                category = item.category
            }
        }
    }

    @ViewBuilder
    private func categoryButton(for option: String) -> some View {
        let isSelected = (category == option)
        let fgColor: Color = isSelected ? Color.brandPrimary : Color(UIColor.secondaryLabel)
        let bgSelection = Color.brandPrimary.opacity(0.14)
        let bgDefault = Color.backgroundPrimary.opacity(0.58)
        let bgColor: Color = isSelected ? bgSelection : bgDefault
        
        Button {
            category = option
            HapticManager.instance.feedback(.light)
        } label: {
            Text(option)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(fgColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "cart.badge.plus")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(initialItem == nil ? "Add Grocery Item" : "Edit Grocery Item")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(initialItem == nil ? "Add anything you need outside the generated meal plan." : "Update this item's details.")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
        }
        .padding(18)
        .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
