import SwiftUI

struct FoodPickerSection: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 9) {
                    ForEach(foods) { food in
                        FoodPickerRow(
                            food: food,
                            isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                            onSelect: onSelect,
                            onQuickLog: onQuickLog,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

struct FoodPickerRow: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    private var detailText: String {
        guard food.calories > 0 || food.protein > 0 || food.carbs > 0 || food.fats > 0 else {
            return "Tap to review nutrition"
        }

        var parts: [String] = []
        if food.calories > 0 { parts.append("\(Int(food.calories.rounded())) cal") }
        if food.protein > 0 { parts.append("P \(Int(food.protein.rounded()))g") }
        if food.carbs > 0 { parts.append("C \(Int(food.carbs.rounded()))g") }
        if food.fats > 0 { parts.append("F \(Int(food.fats.rounded()))g") }
        return parts.joined(separator: "  ")
    }

    private var servingText: String {
        food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Serving details" : food.servingSize
    }

    private var sourceDescriptor: FoodSourceDescriptor? {
        if let metadata = food.sourceMetadata {
            return FoodSourceClassifier.descriptor(for: metadata)
        }
        return FoodSourceClassifier.descriptor(forFoodID: food.id)
    }

    // No swipe-to-reveal here: a row-level DragGesture claims vertical drags too, which
    // blocked ScrollView scrolling that started on a food item. Quick log and delete are
    // already inline buttons on the row, so the swipe duplicated them at the cost of scroll.
    var body: some View {
            HStack(spacing: 10) {
                Button(action: {
                    onSelect(food)
                }) {
                    HStack(spacing: 12) {
                        Text(FoodEmojiMapper.getEmoji(for: food.name))
                            .appFont(size: 23)
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                                .appFont(size: 15, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                Text(servingText)
                                    .appFont(size: 12, weight: .medium)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .lineLimit(1)

                                if let sourceDescriptor {
                                    FoodSourceMiniBadge(descriptor: sourceDescriptor)
                                }
                            }

                            Text(detailText)
                                .appFont(size: 11, weight: .semibold)
                                .foregroundColor(.brandPrimary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.right")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onQuickLog {
                    Button(action: { onQuickLog(food) }) {
                        Image(systemName: isQuickLogged ? "checkmark" : "plus")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(isQuickLogged ? Color.accentPositive : Color.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isQuickLogged)
                    .accessibilityLabel("Quick log \(food.name)")
                }

                if let onDelete {
                    Button(role: .destructive, action: { onDelete(food) }) {
                        Image(systemName: "trash")
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(food.name) from recent foods")
                }
            }
            .padding(12)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
    }
}

private struct FoodSourceMiniBadge: View {
    let descriptor: FoodSourceDescriptor

    private var tint: Color {
        switch descriptor.sourceKey {
        case "usda", "fatsecret", "manual", "planned":
            return .accentPositive
        case "open_food_facts", "recent":
            return .blue
        case "ai_estimate":
            return .orange
        default:
            return .brandPrimary
        }
    }

    var body: some View {
        Label(descriptor.title, systemImage: descriptor.systemImage)
            .labelStyle(.titleAndIcon)
            .appFont(size: 10, weight: .bold)
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
            .accessibilityLabel("\(descriptor.title), \(descriptor.confidence)")
    }
}
