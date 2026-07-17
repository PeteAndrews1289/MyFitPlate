import SwiftUI

struct AIMenuSelectionView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Binding var estimatedItems: [FoodItem]?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItemIDs: Set<String> = []

    private var items: [FoodItem] {
        estimatedItems ?? []
    }

    private var selectedItems: [FoodItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    private var selectedCalories: Int {
        Int(selectedItems.reduce(0) { $0 + $1.calories }.rounded())
    }

    private var selectedProtein: Int {
        Int(selectedItems.reduce(0) { $0 + $1.protein }.rounded())
    }

    var body: some View {
        AppEditorScaffold(
            title: "Review Menu Items",
            subtitle: "Choose only what you ate. Restaurant portions and preparation can change every estimate.",
            dismiss: close
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AIEstimateReviewBanner(
                    title: "Menu estimate",
                    message: "Names and nutrition were inferred from the menu. Review servings before these values enter your totals."
                )

                selectionSummary

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "What You Ate",
                        subtitle: "\(items.count) estimated \(items.count == 1 ? "item" : "items") available"
                    )

                    if items.isEmpty {
                        AppListRow(
                            icon: AppDataAvailabilityReason.notProvided.icon,
                            iconColor: AppPalette.caution,
                            title: "No menu items returned",
                            subtitle: "Close this review and try a clearer image or describe the meal instead."
                        )
                        .appSurface(.quiet, padding: 0)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                menuItemButton(item)

                                if index < items.count - 1 {
                                    Divider().padding(.leading, 68)
                                }
                            }
                        }
                        .appSurface(.quiet, padding: 0)
                    }
                }

                Label(
                    "Selected items are marked as reviewed when you log them. You can still correct each item from the daily log.",
                    systemImage: "checkmark.shield"
                )
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button {
                logSelectedItems()
            } label: {
                Label(
                    selectedItemIDs.isEmpty
                        ? "Select Items to Log"
                        : "Log \(selectedItemIDs.count) \(selectedItemIDs.count == 1 ? "Item" : "Items")",
                    systemImage: "plus"
                )
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(selectedItemIDs.isEmpty)
            .accessibilityIdentifier("ai_menu_log_selected")
        }
        .tint(AppPalette.brand)
        .accessibilityIdentifier("ai_menu_review")
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: selectedItemIDs.isEmpty ? "Nothing Selected Yet" : "Current Selection",
                subtitle: selectedItemIDs.isEmpty
                    ? "Tap each item you actually ate."
                    : "Estimated total before any serving corrections."
            )

            AppMetricStrip(items: [
                AppMetricItem(
                    label: "Items",
                    value: selectedItemIDs.count.formatted(),
                    accent: AppPalette.brand
                ),
                AppMetricItem(
                    label: "Calories",
                    value: "\(selectedCalories.formatted()) cal",
                    accent: AppPalette.energy
                ),
                AppMetricItem(
                    label: "Protein",
                    value: "\(selectedProtein.formatted()) g",
                    accent: AppPalette.protein
                )
            ])
        }
        .appSurface(selectedItemIDs.isEmpty ? .quiet : .interpreted)
        .animation(AppMotion.visibility, value: selectedItemIDs)
    }

    private func menuItemButton(_ item: FoodItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)

        return Button {
            toggleSelection(for: item)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .appFont(size: 22, weight: .semibold)
                    .foregroundStyle(isSelected ? AppPalette.brandText : .secondary)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        Text(item.name)
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                        AIReviewStatusPill(item: item)
                    }

                    Text(item.servingSize.isEmpty ? "Serving needs review" : item.servingSize)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "\(Int(item.calories.rounded()).formatted()) cal  |  P \(Int(item.protein.rounded()).formatted()) g  |  C \(Int(item.carbs.rounded()).formatted()) g  |  F \(Int(item.fats.rounded()).formatted()) g"
                    )
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    AIItemTrustNotes(item: item)
                }
            }
            .padding(AppSpacing.group)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppPalette.interpreted : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(
            "\(isSelected ? "Selected" : "Not selected"). \(item.servingSize). \(Int(item.calories.rounded())) calories."
        )
        .accessibilityHint("Double tap to \(isSelected ? "remove" : "add") this menu estimate")
    }

    private func toggleSelection(for item: FoodItem) {
        HapticsService.shared.playSelection()
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    private func close() {
        estimatedItems = nil
        dismiss()
    }

    private func logSelectedItems() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }

        let confirmedItems = selectedItems.map { item in
            item.markedUserConfirmed(sourceType: item.sourceMetadata?.sourceType ?? .aiMenu)
        }
        guard !confirmedItems.isEmpty else { return }

        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: "AI Menu Log",
            foodItems: confirmedItems,
            source: "ai_menu"
        )

        HapticsService.shared.playSuccess()
        estimatedItems = nil
        dismiss()
    }
}
