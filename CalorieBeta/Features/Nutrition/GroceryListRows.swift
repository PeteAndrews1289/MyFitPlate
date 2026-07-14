import SwiftUI

struct GroceryCategorySection: View {
    let category: String
    let items: [GroceryListItem]
    @Binding var groceryList: [GroceryListItem]
    let onToggle: () -> Void
    let onEdit: (GroceryListItem) -> Void
    let onDelete: (GroceryListItem) -> Void

    private var remainingCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    private var countDescription: String {
        if remainingCount == 0 {
            return "All checked"
        }
        return "\(remainingCount.formatted()) left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: category, subtitle: countDescription)

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if let itemIndex = groceryList.firstIndex(where: { $0.id == item.id }) {
                        GroceryItemRow(
                            item: $groceryList[itemIndex],
                            onToggle: onToggle,
                            onEdit: { onEdit(item) },
                            onDelete: { onDelete(item) }
                        )

                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
            .animation(AppMotion.standard, value: groceryList)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grocery_category_\(category)")
    }
}

struct GroceryItemRow: View {
    @Binding var item: GroceryListItem
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var quantityText: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = item.quantity == floor(item.quantity) ? 0 : 2

        let formattedQuantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
        let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUnit = unit.lowercased()

        if item.quantity <= 0 {
            return normalizedUnit == "to taste" ? "to taste" : nil
        }
        if normalizedUnit == "to taste" {
            return "to taste"
        }
        if normalizedUnit == "item" || unit.isEmpty {
            return item.quantity == 1 ? "1 item" : "\(formattedQuantity) items"
        }
        if normalizedUnit == "meal use" {
            return item.quantity == 1 ? "1 use" : "\(formattedQuantity) uses"
        }
        return "\(formattedQuantity) \(unit)"
    }

    private var sourceText: String? {
        let source = item.source?.lowercased() ?? ""
        if source.contains("manual") {
            return "Manual"
        }
        if source.contains("barcode") || source.contains("scan") {
            return "Scanned"
        }
        if source.contains("meal") {
            return "Meal plan"
        }
        return nil
    }

    private var metadataText: String {
        [quantityText, sourceText]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private var categorySymbol: String {
        switch GroceryListBuilder.normalizedCategory(item.category) {
        case "Produce": "leaf.fill"
        case "Meat & Seafood": "fork.knife"
        case "Dairy & Eggs": "cup.and.saucer.fill"
        case "Carbohydrates": "takeoutbag.and.cup.and.straw.fill"
        case "Pantry & Oils": "cabinet.fill"
        case "Spices & Seasonings": "sparkles"
        case "Bakery": "birthday.cake.fill"
        default: "basket.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.compact) {
            Button(action: toggleCompleted) {
                HStack(alignment: .center, spacing: AppSpacing.row) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .appTextRole(.control)
                        .foregroundStyle(item.isCompleted ? Color.accentPositive : Color.secondary)
                        .frame(width: 32, height: 44)

                    Image(systemName: categorySymbol)
                        .appTextRole(.control)
                        .foregroundStyle(item.isCompleted ? Color.secondary : AppPalette.brand)
                        .frame(width: 40, height: 40)
                        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name.capitalized)
                            .appTextRole(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(item.isCompleted ? Color.secondary : AppPalette.text)
                            .strikethrough(item.isCompleted, color: Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !metadataText.isEmpty {
                            Text(metadataText)
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name)
            .accessibilityValue("\(metadataText), \(item.isCompleted ? "checked" : "not checked")")
            .accessibilityHint(item.isCompleted ? "Marks this item not checked" : "Marks this item checked")
            .accessibilityIdentifier("grocery_item_\(item.id.uuidString)")

            Menu {
                Button(action: onEdit) {
                    Label("Edit Item", systemImage: "pencil")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete Item", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .appTextRole(.control)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("More options for \(item.name)")
        }
        .padding(.horizontal, AppSpacing.row)
        .padding(.vertical, AppSpacing.compact)
        .background(item.isCompleted ? Color.accentPositive.opacity(0.05) : Color.clear)
    }

    private func toggleCompleted() {
        withAnimation(AppMotion.standard) {
            item.isCompleted.toggle()
        }
        onToggle()
        HapticManager.instance.feedback(.light)
    }
}
