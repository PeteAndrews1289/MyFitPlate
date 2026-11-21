import SwiftUI
import MyFitPlateCore

struct FoodPickerSection: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let loggingFoodIDs: Set<String>
    let isBuildingMeal: Bool
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
        loggingFoodIDs: Set<String> = [],
        isBuildingMeal: Bool = false,
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
        self.loggingFoodIDs = loggingFoodIDs
        self.isBuildingMeal = isBuildingMeal
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
                            isLogging: loggingFoodIDs.contains(food.id),
                            isBuildingMeal: isBuildingMeal,
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
    var isLogging = false
    var isBuildingMeal = false
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?
    let source: String?
    var selectionID: String?
    var quickActionID: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayName: String {
        FoodSearchRanking.productDisplayName(food.name, brandName: food.sourceMetadata?.brandName)
    }

    // Many catalog records prefix the brand to the title. Put it on its own
    // line so it cannot truncate the flavor or size that distinguishes variants.
    private var brandAndProduct: (brand: String, product: String)? {
        guard let brand = FoodSearchRanking.reportedBrandName(food.sourceMetadata?.brandName),
              let prefix = displayName.range(of: brand + " ", options: [.anchored, .caseInsensitive, .diacriticInsensitive]) else { return nil }
        let product = String(displayName[prefix.upperBound...])
        return product.isEmpty ? nil : (brand, product)
    }

    private var detailText: String {
        let serving = ServingNutritionCalculator.displayPortion(food.servingSize)
        if food.sourceMetadata?.sourceType == .nihDSLD {
            return "\(serving) · \(food.reportedMicronutrientCount) label nutrients"
        }
        let energy = food.calories.isFinite && food.calories >= 0 ? "\(food.calories.formatted(.number.precision(.fractionLength(0)))) cal" : nil
        if let label = food.sourceMetadata?.labeledServing, !label.isEmpty {
            return ["Labeled serving " + label, energy.map { $0 + " per " + serving }].compactMap { $0 }.joined(separator: " · ")
        }
        return [serving.isEmpty ? nil : serving, energy].compactMap { $0 }.joined(separator: " · ")
    }

    private var portionNotice: String? { food.loggingPortionNotice(source: source) }

    private var selectionAccessibilityLabel: String {
        [displayName, detailText, portionNotice].compactMap { $0 }.joined(separator: ", ")
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
        .padding(.horizontal, AppSpacing.row)
        .padding(.vertical, AppSpacing.compact)
    }

    private var selectionButton: some View {
        Button(action: {
            onSelect(food)
        }) {
            HStack(spacing: 10) {
                foodGlyph

                VStack(alignment: .leading, spacing: 4) {
                    let identity = brandAndProduct
                    if let identity {
                        Text(identity.brand).appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    Text(identity?.product ?? displayName)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize || identity != nil ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detailText)
                        .appFont(size: 13)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if let portionNotice {
                        Text(portionNotice).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    }
                }

                Spacer(minLength: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLogging)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(selectionID ?? "food_picker_row_\(food.id)")
        .accessibilityLabel(selectionAccessibilityLabel)
        .accessibilityHint("Review serving and nutrition")
    }

    @ViewBuilder
    private var foodGlyph: some View {
        Group {
            if food.sourceMetadata?.sourceType == .nihDSLD {
                Image(systemName: "pills.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(FoodEmojiMapper.getEmoji(for: food.name))
                    .font(.system(size: 26))
            }
        }
        .frame(width: 40, height: 40)
        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .accessibilityHidden(true)
    }

    private var actionTitle: String {
        if isQuickLogged { return isBuildingMeal ? "Selected" : "Logged" }
        if portionNotice != nil { return "Review" }
        return isBuildingMeal ? "Select" : "Log"
    }

    private var actionSymbol: String {
        if isQuickLogged { return "checkmark" }
        return portionNotice == nil ? "plus" : "slider.horizontal.3"
    }

    private var actionLabel: String {
        if isLogging { return "Preparing " + displayName }
        if isQuickLogged { return displayName + (isBuildingMeal ? " selected" : " logged") }
        return (actionTitle == "Log" ? "Quick log" : actionTitle) + " " + displayName
    }

    private var actionButtons: some View {
        HStack(spacing: AppSpacing.compact) {
            if let onQuickLog {
                Button(action: { if portionNotice != nil { onSelect(food) } else { onQuickLog(food) } }) {
                    HStack(spacing: 5) {
                        if isLogging { ProgressView() } else { Image(systemName: actionSymbol) }
                        Text(actionTitle)
                    }
                        .appFont(size: 17, weight: .medium)
                        .foregroundStyle(isQuickLogged ? AppPalette.brandText : AppPalette.text)
                        .padding(.horizontal, AppSpacing.compact)
                        .frame(minWidth: 64, minHeight: 44)
                        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isQuickLogged || isLogging)
                .accessibilityLabel(actionLabel)
                .accessibilityValue(detailText)
                .accessibilityHint(portionNotice ?? (isBuildingMeal ? "Keeps this amount in the meal draft without leaving search" : "Adds the shown amount without leaving search"))
                .accessibilityIdentifier(quickActionID ?? "food_picker_add_\(food.id)")
            }

            if let onDelete {
                Button(role: .destructive, action: { onDelete(food) }) {
                    Image(systemName: "trash")
                        .appTextRole(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
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
        switch descriptor.sourceKey {
        case "health_canada_cnf":
            return "Health Canada"
        case "nih_dsld":
            return "NIH label"
        default:
            break
        }

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
