import SwiftUI
import MyFitPlateCore

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
                        .font(.system(size: 23))
                        .frame(width: 46, height: 46)
                        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)

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
    let headerActionTitle: String?
    let headerAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        subtitle: String,
        foods: [FoodItem],
        quickLoggedFoodIDs: Set<String>,
        emptyTitle: String,
        emptyMessage: String,
        onSelect: @escaping (FoodItem) -> Void,
        onQuickLog: ((FoodItem) -> Void)?,
        source: String? = nil,
        headerActionTitle: String? = nil,
        headerAction: (() -> Void)? = nil
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
        self.headerActionTitle = headerActionTitle
        self.headerAction = headerAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: title, subtitle: subtitle.isEmpty ? nil : subtitle) {
                if let headerActionTitle, let headerAction {
                    Button(headerActionTitle, action: headerAction)
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.brand)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                }
            }

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                GeometryReader { proxy in
                    let visibleCardCount = dynamicTypeSize.isAccessibilitySize || proxy.size.width < 320 ? 1 : 2
                    let totalSpacing = CGFloat(visibleCardCount - 1) * AppSpacing.row
                    let cardWidth = (proxy.size.width - totalSpacing) / CGFloat(visibleCardCount)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.row) {
                            ForEach(foods) { food in
                                FoodCard(
                                    food: food,
                                    isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                                    onSelect: onSelect,
                                    onQuickLog: onQuickLog,
                                    source: source,
                                    width: cardWidth
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                }
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 254 : 172)
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
    let width: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
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
                    foodGlyph

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
                        .lineLimit(usesAccessibilityLayout ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(servingText)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(usesAccessibilityLayout ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    nutritionFooter
                }
            }
            .padding(AppSpacing.row)
            .frame(width: width, height: cardHeight)
            .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(AppPalette.separator.opacity(0.5), lineWidth: 0.5)
            }
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

    @ViewBuilder
    private var foodGlyph: some View {
        if usesAccessibilityLayout {
            Image(systemName: "fork.knife")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
        } else {
            Text(FoodEmojiMapper.getEmoji(for: food.name))
                .font(.system(size: 30))
                .padding(6)
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)
        }
    }

    private var calorieText: some View {
        Text("\(Int(food.calories.rounded()).formatted()) cal")
            .appFont(size: 13, weight: .medium)
            .foregroundColor(AppPalette.caution)
    }
}

struct FoodSearchLoadingState: View {
    let query: String

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(.secondary)

            Text("Searching foods")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines))
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.quiet, padding: AppSpacing.group)
    }
}

struct FoodSearchEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let primaryActionTitle: String?
    let primaryAction: (() -> Void)?
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)

            VStack(spacing: 4) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let primaryActionTitle, let primaryAction {
                VStack(spacing: 8) {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(AppActionButtonStyle(.primary, fillsWidth: false))

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .appTextRole(.secondary)
                            .foregroundStyle(AppPalette.brand)
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.compact)
        .appSurface(.quiet, padding: AppSpacing.group)
    }
}
