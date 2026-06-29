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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category)
                    .appFont(size: 19, weight: .bold)
                    .foregroundColor(.textPrimary)

                Spacer()

                Text("\(remainingCount) left")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(remainingCount == 0 ? .accentPositive : Color(UIColor.secondaryLabel))
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    if let index = groceryList.firstIndex(where: { $0.id == item.id }) {
                        GroceryItemRow(
                            item: $groceryList[index],
                            onToggle: onToggle,
                            onEdit: { onEdit(item) },
                            onDelete: { onDelete(item) }
                        )
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: groceryList)
        }
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
        formatter.maximumFractionDigits = 2
        
        if item.quantity == floor(item.quantity) {
             formatter.maximumFractionDigits = 0
        }

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
        if item.source == "manual" {
            return "Manual"
        }

        if item.source == "barcode" {
            return "Scanned"
        }

        if item.source == nil && item.unit.lowercased() == "item" && item.category == "Misc" {
            return "Scanned"
        }

        return nil
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    toggleCompleted()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(item.isCompleted ? .accentPositive : Color(UIColor.tertiaryLabel))
                        .scaleEffect(item.isCompleted ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: item.isCompleted)

                    Text(FoodEmojiMapper.getEmoji(for: item.name))
                        .appFont(size: 24)
                        .frame(width: 44, height: 44)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(item.isCompleted ? 0.6 : 1.0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name.capitalized)
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(item.isCompleted ? Color(UIColor.secondaryLabel) : .textPrimary)
                            .strikethrough(item.isCompleted, color: Color(UIColor.secondaryLabel))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let quantityText {
                                Text(quantityText)
                                    .appFont(size: 12, weight: .bold)
                                    .foregroundColor(.brandPrimary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
                            }

                            if let sourceText {
                                Text(sourceText)
                                    .appFont(size: 12, weight: .bold)
                                    .foregroundColor(.accentCarbs)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.accentCarbs.opacity(0.10), in: Capsule())
                            }
                        }
                    }

                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark \(item.name) incomplete" : "Mark \(item.name) complete")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(item.name)")
        }
        .padding(12)
        .background(
            (item.isCompleted ? Color.backgroundSecondary.opacity(0.46) : Color.backgroundSecondary.opacity(0.78)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.isCompleted ? Color.accentPositive.opacity(0.16) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func toggleCompleted() {
        item.isCompleted.toggle()
        onToggle()
        HapticManager.instance.feedback(.light)
    }
}
