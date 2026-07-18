import SwiftUI

struct AITextResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dailyLogService: DailyLogService

    @State private var foodItems: [FoodItem]
    @State private var itemToEdit: FoodItem?

    let onLogComplete: () -> Void

    init(foodItems: [FoodItem], onLogComplete: @escaping () -> Void) {
        _foodItems = State(initialValue: foodItems)
        self.onLogComplete = onLogComplete
    }

    var body: some View {
        NavigationStack {
            List {
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
                        top: AppSpacing.group,
                        leading: AppSpacing.screenHorizontal,
                        bottom: AppSpacing.section,
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
                        title: "Estimated Items",
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: logAllItems) {
                    Label(logButtonTitle, systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(foodItems.isEmpty)
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
            .sheet(item: $itemToEdit) { item in
                FoodDetailView(
                    initialFoodItem: item,
                    dailyLog: .constant(nil),
                    date: dailyLogService.activelyViewedDate,
                    source: "ai_text_edit",
                    onLogUpdated: {},
                    onUpdate: update
                )
            }
        }
        .accessibilityIdentifier("ai_text_results")
    }

    private var logButtonTitle: String {
        let noun = foodItems.count == 1 ? "Item" : "Items"
        return "Log \(foodItems.count.formatted()) \(noun)"
    }

    private func update(_ updatedItem: FoodItem) {
        guard let index = foodItems.firstIndex(where: { $0.id == updatedItem.id }) else { return }
        foodItems[index] = updatedItem
    }

    private func delete(_ item: FoodItem) {
        foodItems.removeAll { $0.id == item.id }
        HapticManager.instance.feedback(.light)
    }

    private func logAllItems() {
        guard let userID = DIContainer.shared.authService.currentUserID, !foodItems.isEmpty else { return }

        let reviewedItems = foodItems.map { item in
            item.markedUserConfirmed(sourceType: item.sourceMetadata?.sourceType ?? .aiText)
        }
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: "AI Quick Log",
            foodItems: reviewedItems,
            source: "ai_text"
        )

        onLogComplete()
        dismiss()
    }
}
