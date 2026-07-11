import SwiftUI

struct FoodSearchRow: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    private var servingText: String {
        let trimmed = food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Usual serving" : trimmed
    }

    private var detailText: String {
        let cal = Int(food.calories.rounded()).formatted()
        let pro = Int(food.protein.rounded()).formatted()
        return "\(cal) cal • \(pro)g P"
    }

    var body: some View {
        HStack(spacing: 10) {
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

                        Text(servingText)
                            .appFont(size: 12, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(1)

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
                // A tap gesture (not a Button) lets a drag starting on the row pass through to the
                // ScrollView, so scrolling can begin on a food item — Buttons swallow that touch.
                .contentShape(Rectangle())
                .onTapGesture { onSelect(food) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)

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

struct FoodHorizontalScroller: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let source: String?

    init(
        title: String,
        subtitle: String,
        foods: [FoodItem],
        quickLoggedFoodIDs: Set<String>,
        emptyTitle: String,
        emptyMessage: String,
        onSelect: @escaping (FoodItem) -> Void,
        onQuickLog: ((FoodItem) -> Void)?,
        source: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.foods = foods
        self.quickLoggedFoodIDs = quickLoggedFoodIDs
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.onSelect = onSelect
        self.onQuickLog = onQuickLog
        self.source = source
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(foods) { food in
                            FoodCard(
                                food: food,
                                isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                                onSelect: onSelect,
                                onQuickLog: onQuickLog,
                                source: source
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -4)
            }
        }
    }
}

struct FoodCard: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let source: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var cardWidth: CGFloat {
        usesAccessibilityLayout ? 224 : 168
    }

    private var cardHeight: CGFloat {
        usesAccessibilityLayout ? 246 : 164
    }

    private var servingText: String {
        let trimmed = food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Usual serving" : trimmed
    }

    var body: some View {
        Button(action: { onSelect(food) }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(FoodEmojiMapper.getEmoji(for: food.name))
                        .appFont(size: 32)

                    Spacer()

                    if let onQuickLog = onQuickLog {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            onQuickLog(food)
                        }) {
                            Image(systemName: isQuickLogged ? "checkmark.circle.fill" : "plus.circle")
                                .appFont(size: 24)
                                .foregroundColor(isQuickLogged ? .accentPositive : Color(UIColor.secondaryLabel))
                        }
                        .disabled(isQuickLogged)
                        .accessibilityLabel(isQuickLogged ? "\(food.name) logged" : "Quick log \(food.name)")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(usesAccessibilityLayout ? 3 : 2)
                        .multilineTextAlignment(.leading)

                    Text(servingText)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    nutritionFooter
                }
            }
            .padding(14)
            .frame(width: cardWidth, height: cardHeight)
            .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nutritionFooter: some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 4) {
                calorieText
                FoodTrustMiniBadge(food: food, source: source)
            }
        } else {
            HStack(spacing: 6) {
                calorieText
                Spacer(minLength: 0)
                FoodTrustMiniBadge(food: food, source: source)
            }
            .lineLimit(1)
        }
    }

    private var calorieText: some View {
        Text("\(Int(food.calories.rounded()).formatted()) cal")
            .appFont(size: 13, weight: .medium)
            .foregroundColor(.orange)
    }
}

struct FoodSearchLoadingState: View {
    let query: String

    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(Color(UIColor.secondaryLabel))

            Text("Searching foods")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines))
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct FoodSearchEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .appFont(size: 22, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(width: 48, height: 48)
                .background(Color(UIColor.secondarySystemFill), in: Circle())

            VStack(spacing: 4) {
                Text(title)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text(message)
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
