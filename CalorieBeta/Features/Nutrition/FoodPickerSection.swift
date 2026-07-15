import SwiftUI
import MyFitPlateCore

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
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title, subtitle: subtitle.isEmpty ? nil : subtitle)

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(foods.enumerated()), id: \.element.id) { index, food in
                        FoodPickerRow(
                            food: food,
                            isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                            onSelect: onSelect,
                            onQuickLog: onQuickLog,
                            onDelete: onDelete,
                            source: sourceForFood?(food)
                        )

                        if index < foods.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .appSurface(.quiet, padding: 0)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    selectionButton
                    actionButtons
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: AppSpacing.compact) {
                    selectionButton
                    actionButtons
                }
            }
        }
        .padding(AppSpacing.row)
    }

    private var selectionButton: some View {
        Button(action: {
            onSelect(food)
        }) {
            HStack(spacing: 10) {
                foodGlyph

                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                servingLabel
                                evidenceBadges
                            }
                        } else {
                            HStack(spacing: 6) {
                                servingLabel
                                evidenceBadges
                            }
                        }
                    }

                    Text(detailText)
                        .appTextRole(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .appTextRole(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Review serving and nutrition")
    }

    private var servingLabel: some View {
        Text(servingText)
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    @ViewBuilder
    private var foodGlyph: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "fork.knife")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(FoodEmojiMapper.getEmoji(for: food.name))
                    .font(.system(size: 23))
            }
        }
        .frame(width: 46, height: 46)
        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var evidenceBadges: some View {
        if let sourceDescriptor {
            FoodTrustMiniBadge(
                food: food,
                descriptor: sourceDescriptor,
                metadata: food.sourceMetadata
            )
        }

        if FoodDataSanity.isSuspicious(food) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appTextRole(.caption)
                .foregroundStyle(AppPalette.caution)
                .accessibilityLabel("Nutrition data looks off")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.compact) {
            if let onQuickLog {
                Button(action: { onQuickLog(food) }) {
                    Image(systemName: isQuickLogged ? "checkmark" : "plus")
                        .appTextRole(.control)
                        .foregroundStyle(isQuickLogged ? Color.white : AppPalette.brand)
                        .frame(width: 40, height: 40)
                        .background(isQuickLogged ? Color.accentPositive : Color.clear, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(isQuickLogged ? Color.clear : AppPalette.brand.opacity(0.55), lineWidth: 1.4)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isQuickLogged)
                .accessibilityLabel(isQuickLogged ? "\(food.name) logged" : "Quick log \(food.name)")
            }

            if let onDelete {
                Button(role: .destructive, action: { onDelete(food) }) {
                    Image(systemName: "trash")
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(food.name) from recent foods")
            }
        }
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
            return AppPalette.caution
        case .low:
            return evaluation.requiresCorrection ? AppPalette.critical : AppPalette.caution
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
