import SwiftUI

struct AIMenuSelectionView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Binding var estimatedItems: [FoodItem]?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var review: MealReviewSaveSession
    @State private var confirmingDiscard = false

    init(estimatedItems: Binding<[FoodItem]?>, date: Date = Date(), mealName: String = "Dinner", trainingFuelTarget: TrainingFuelTarget? = nil) {
        _estimatedItems = estimatedItems
        _review = StateObject(wrappedValue: MealReviewSaveSession(
            items: estimatedItems.wrappedValue ?? [], userID: DIContainer.shared.authService.currentUserID,
            date: date, mealName: mealName, source: "ai_menu", selectsAllItems: false, confirmingSourceType: .aiMenu, trainingFuelTarget: trainingFuelTarget
        ))
    }

    private var selectedItemIDs: Set<String> { review.selectedItemIDs }

    private var items: [FoodItem] {
        review.items
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
            title: "Review menu",
            subtitle: "Choose only what you ate. Restaurant portions and preparation can change every estimate.",
            dismiss: close
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                if let target = review.checkpoint.trainingFuelTarget {
                    TrainingFuelTargetContextView(target: target, onDismiss: review.isLocked ? nil : { _ = review.removeFuelContext() })
                }

                Text("\(review.mealName) · \(review.date.formatted(date: .abbreviated, time: .omitted))")
                    .appTextRole(.secondary).accessibilityIdentifier("ai_review_destination")
                if review.restoredReview { Text("Restored your unfinished review.").foregroundStyle(.secondary) }
                if review.isSubmitted { Text("Your selection is kept for a safe retry.").foregroundStyle(.secondary) }
                AIEstimateReviewBanner(
                    title: "Menu estimate",
                    message: "Names and nutrition were inferred from the menu. Review servings before these values enter your totals."
                )

                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(
                        title: "What you ate",
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
            selectionSummary
            if let message = review.errorMessage {
                Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai_menu_save_error")
            }
            Button {
                logSelectedItems()
            } label: {
                Label(
                    review.isSaving ? "Saving…" : review.isSubmitted ? "Retry saving" : selectedItemIDs.isEmpty
                        ? "Select items to log"
                        : "Log \(selectedItemIDs.count) \(selectedItemIDs.count == 1 ? "Item" : "Items")",
                    systemImage: "plus"
                )
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .disabled(selectedItemIDs.isEmpty || review.isSaving)
            .accessibilityIdentifier("ai_menu_log_selected")
        }
        .interactiveDismissDisabled(review.isSaving)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !review.isSubmitted {
                    Button("Discard", role: .destructive) { confirmingDiscard = true }.disabled(review.isSaving)
                }
            }
        }
        .confirmationDialog("Discard this menu review?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard review", role: .destructive) { if review.discard() { close() } }
        } message: { Text("These foods have not been logged.") }
        .tint(AppPalette.brand)
        .accessibilityIdentifier("ai_menu_review")
    }

    private var selectionSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selectedItemIDs.isEmpty ? "Choose what you ate" : "\(selectedItemIDs.count) selected")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            Spacer(minLength: AppSpacing.compact)
            if !selectedItemIDs.isEmpty {
                Text("\(selectedCalories.formatted()) cal · \(selectedProtein.formatted()) g protein")
                    .appTextRole(.secondary).monospacedDigit()
            }
        }.animation(AppMotion.visibility, value: selectedItemIDs)
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
        .disabled(review.isLocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(
            "\(isSelected ? "Selected" : "Not selected"). \(item.servingSize). \(Int(item.calories.rounded())) calories."
        )
        .accessibilityHint("Double tap to \(isSelected ? "remove" : "add") this menu estimate")
    }

    private func toggleSelection(for item: FoodItem) {
        if review.toggleSelection(id: item.id) { HapticsService.shared.playSelection() }
    }

    private func close() {
        guard !review.isSaving else { return }
        estimatedItems = nil
        dismiss()
    }

    private func logSelectedItems() {
        review.save(using: dailyLogService) { accepted in
            if accepted { HapticsService.shared.playSuccess(); close() }
        }
    }
}
