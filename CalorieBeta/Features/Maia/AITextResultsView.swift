import SwiftUI

struct AITextResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dailyLogService: DailyLogService

    @StateObject private var review: MealReviewSaveSession
    @State private var confirmingDiscard = false

    private var foodItems: [FoodItem] { review.items }
    @State private var itemToEdit: FoodItem?

    let onLogComplete: () -> Void

    init(foodItems: [FoodItem], date: Date = Date(), mealName: String = "Dinner", trainingFuelTarget: TrainingFuelTarget? = nil, onLogComplete: @escaping () -> Void) {
        _review = StateObject(wrappedValue: MealReviewSaveSession(
            items: foodItems, userID: DIContainer.shared.authService.currentUserID,
            date: date, mealName: mealName, source: "ai_text", confirmingSourceType: .aiText, trainingFuelTarget: trainingFuelTarget
        ))
        self.onLogComplete = onLogComplete
    }

    var body: some View {
        NavigationStack {
            List {
                if let target = review.checkpoint.trainingFuelTarget {
                    TrainingFuelTargetContextView(target: target, onDismiss: review.isLocked ? nil : { _ = review.removeFuelContext() })
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                    Text("\(review.mealName) · \(review.date.formatted(date: .abbreviated, time: .omitted))")
                        .appTextRole(.secondary)
                        .accessibilityIdentifier("ai_review_destination")
                    if review.restoredReview { Text("Unfinished review restored").appTextRole(.caption).foregroundStyle(.secondary) }
                    if review.isSubmitted { Text("Your reviewed foods are kept for retry").appTextRole(.caption).foregroundStyle(.secondary) }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section {
                    AIReviewOverview(
                        eyebrow: "Maia Text Estimate",
                        title: "Review Your Meal",
                        subtitle: "Maia separated your description into foods. Nothing is logged until you confirm this list.",
                        reviewMessage: "Check portions closely, especially sauces, oils, drinks, and shared plates.",
                        items: foodItems
                    )
                    .accessibilityIdentifier("ai_text_results_overview")
                }
                .listRowInsets(
                    EdgeInsets(
                        top: AppSpacing.compact,
                        leading: AppSpacing.screenHorizontal,
                        bottom: AppSpacing.row,
                        trailing: AppSpacing.screenHorizontal
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    ForEach(foodItems) { item in
                        Button {
                            itemToEdit = item
                        } label: {
                            AIReviewItemRow(item: item, showsEditIndicator: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ai_review_item_\(item.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    AppSectionHeader(
                        title: "Foods to log",
                        subtitle: "Tap an item to edit it, or swipe to remove it."
                    )
                    .textCase(nil)
                    .padding(.bottom, AppSpacing.compact)
                }
                .listRowInsets(
                    EdgeInsets(
                        top: AppSpacing.row,
                        leading: AppSpacing.screenHorizontal,
                        bottom: AppSpacing.row,
                        trailing: AppSpacing.screenHorizontal
                    )
                )
                .listRowBackground(AppPalette.control)
                .disabled(review.isLocked)
            }
            .appFormStyle()
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(review.isSaving)
                        .tint(AppPalette.brand)
                }
                ToolbarItem(placement: .primaryAction) {
                    if !review.isSubmitted {
                        Button("Discard", role: .destructive) { confirmingDiscard = true }.disabled(review.isSaving)
                    }
                }
            }
            .confirmationDialog("Discard this meal review?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard review", role: .destructive) { if review.discard() { dismiss() } }
            } message: { Text("These foods have not been logged.") }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let message = review.errorMessage {
                        Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .accessibilityIdentifier("ai_text_save_error")
                    }
                    Button(action: logAllItems) {
                        Label(logButtonTitle, systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(foodItems.isEmpty || review.isSaving)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.row)
                    .padding(.bottom, AppSpacing.compact)
                    .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppPalette.separator)
                            .frame(height: 1)
                    }
                    .accessibilityIdentifier("ai_text_log_action")
                }
                .background(AppPalette.canvas)
            }
            .sheet(item: $itemToEdit) { item in
                FoodDetailView(
                    initialFoodItem: item,
                    dailyLog: .constant(nil),
                    date: review.date,
                    source: "ai_text_edit",
                    isPresentedModally: true,
                    onLogUpdated: {},
                    onUpdate: update
                )
            }
        }
        .interactiveDismissDisabled(review.isSaving)
        .accessibilityIdentifier("ai_text_results")
        .accessibilityElement(children: .contain)
    }

    private var logButtonTitle: String {
        if review.isSaving { return "Saving…" }
        if review.isSubmitted { return "Retry saving" }
        let noun = foodItems.count == 1 ? "Item" : "Items"
        return "Log \(foodItems.count.formatted()) \(noun)"
    }

    private func update(_ updatedItem: FoodItem) {
        _ = review.updateItem(updatedItem)
    }

    private func delete(_ item: FoodItem) {
        if review.removeItem(id: item.id) { HapticManager.instance.feedback(.light) }
    }

    private func logAllItems() {
        review.save(using: dailyLogService) { accepted in
            if accepted { onLogComplete(); dismiss() }
        }
    }
}
