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
    let sourceForFood: ((FoodItem) -> String)?

    init(
        title: String,
        subtitle: String,
        foods: [FoodItem],
        quickLoggedFoodIDs: Set<String>,
        emptyTitle: String,
        emptyMessage: String,
        onSelect: @escaping (FoodItem) -> Void,
        onQuickLog: ((FoodItem) -> Void)?,
        onDelete: ((FoodItem) -> Void)?,
        sourceForFood: ((FoodItem) -> String)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.foods = foods
        self.quickLoggedFoodIDs = quickLoggedFoodIDs
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.onSelect = onSelect
        self.onQuickLog = onQuickLog
        self.onDelete = onDelete
        self.sourceForFood = sourceForFood
    }

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
                            onDelete: onDelete,
                            source: sourceForFood?(food)
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
    let source: String?

    private var detailText: String {
        guard food.calories > 0 || food.protein > 0 || food.carbs > 0 || food.fats > 0 else {
            return "Tap to review nutrition"
        }

        var parts: [String] = []
        if food.calories > 0 { parts.append("\(Int(food.calories.rounded()).formatted()) cal") }
        if food.protein > 0 { parts.append("P \(Int(food.protein.rounded()).formatted())g") }
        if food.carbs > 0 { parts.append("C \(Int(food.carbs.rounded()).formatted())g") }
        if food.fats > 0 { parts.append("F \(Int(food.fats.rounded()).formatted())g") }
        return parts.joined(separator: "  ")
    }

    private var servingText: String {
        food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Serving details" : food.servingSize
    }

    private var sourceDescriptor: FoodSourceDescriptor? {
        if let metadata = food.sourceMetadata {
            return FoodSourceClassifier.descriptor(for: metadata)
        }
        if let source {
            return FoodSourceClassifier.descriptor(for: source, foodID: food.id)
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
                            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                                    FoodTrustMiniBadge(
                                        food: food,
                                        descriptor: sourceDescriptor,
                                        metadata: food.sourceMetadata
                                    )
                                }

                                if FoodDataSanity.isSuspicious(food) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .appFont(size: 10, weight: .bold)
                                        .foregroundColor(.orange)
                                        .accessibilityLabel("Nutrition data looks off")
                                }
                            }

                            Text(detailText)
                                .appFont(size: 11, weight: .semibold)
                                .foregroundColor(Color(UIColor.secondaryLabel))
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
                            .foregroundColor(isQuickLogged ? .white : .brandPrimary)
                            .frame(width: 36, height: 36)
                            .background(isQuickLogged ? Color.accentPositive : Color.clear, in: Circle())
                            .overlay(
                                Circle()
                                    .stroke(isQuickLogged ? Color.clear : Color.brandPrimary.opacity(0.55), lineWidth: 1.4)
                            )
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

struct FoodTrustMiniBadge: View {
    let food: FoodItem
    let descriptor: FoodSourceDescriptor
    let metadata: FoodSourceMetadata?

    init(food: FoodItem, source: String? = nil) {
        self.food = food
        self.metadata = food.sourceMetadata
        self.descriptor = FoodSourceClassifier.descriptor(
            for: source ?? "unknown",
            foodID: food.id,
            metadata: food.sourceMetadata
        )
    }

    init(food: FoodItem, descriptor: FoodSourceDescriptor, metadata: FoodSourceMetadata? = nil) {
        self.food = food
        self.descriptor = descriptor
        self.metadata = metadata
    }

    private var evaluation: FoodTrustEvaluation {
        FoodTrustEvaluation.evaluate(item: food, descriptor: descriptor, metadata: metadata)
    }

    private var tint: Color {
        switch evaluation.level {
        case .excellent, .strong:
            return .accentPositiveText
        case .review:
            return .orange
        case .low:
            return evaluation.requiresCorrection ? .red : .orange
        }
    }

    private var title: String {
        switch evaluation.level {
        case .excellent:
            return "Excellent"
        case .strong:
            return "Strong"
        case .review:
            return evaluation.label.hasPrefix("Reviewed") ? "Reviewed" : "Review"
        case .low:
            if evaluation.requiresCorrection {
                return "Fix"
            }
            return evaluation.label.hasPrefix("Reviewed") ? "Reviewed" : "Review"
        }
    }

    private var icon: String {
        switch evaluation.level {
        case .excellent, .strong:
            return "shield.checkered"
        case .review:
            return "exclamationmark.circle.fill"
        case .low:
            return evaluation.requiresCorrection
                ? "exclamationmark.triangle.fill"
                : "exclamationmark.circle.fill"
        }
    }

    var body: some View {
        Label(title, systemImage: icon)
            .labelStyle(.titleAndIcon)
            .appFont(size: 10, weight: .bold)
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
            .accessibilityLabel("\(evaluation.label), \(descriptor.title)")
    }
}
