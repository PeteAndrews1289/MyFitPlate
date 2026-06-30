import SwiftUI

struct AITextResultsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @Binding var foodItems: [FoodItem]
    @State private var itemToEdit: FoodItem?
    
    var onLogComplete: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AIEstimateReviewBanner(
                    title: "Text Estimate",
                    message: "Maia parsed this from your description. Review portions before logging, especially sauces, oils, and shared plates."
                )
                .padding([.horizontal, .top])

                List {
                    Section(header: Text("Review Items")) {
                        ForEach($foodItems) { $item in
                            Button(action: {
                                self.itemToEdit = item
                            }) {
                                itemRow(for: item)
                            }
                        }
                        .onDelete(perform: deleteItem)
                    }
                }
                
                Text("Tap an item to edit it, or swipe to remove anything Maia inferred incorrectly.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Log All Items") {
                    logAllItems()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
                .disabled(foodItems.isEmpty)
            }
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $itemToEdit) { item in
                FoodDetailView(
                    initialFoodItem: item,
                    dailyLog: .constant(nil),
                    date: dailyLogService.activelyViewedDate,
                    source: "ai_text_edit",
                    onLogUpdated: {},
                    onUpdate: { updatedItem in
                        // When the user saves in FoodDetailView, this updates our local list
                        if let index = foodItems.firstIndex(where: { $0.id == updatedItem.id }) {
                            foodItems[index] = updatedItem
                        }
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func itemRow(for item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name)
                    .appFont(size: 17, weight: .semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                AIReviewStatusPill(item: item)
            }
            Text("Serving: \(item.servingSize)")
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text("Est: \(Int(item.calories)) cal, P:\(Int(item.protein))g, C:\(Int(item.carbs))g, F:\(Int(item.fats))g")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.tertiaryLabel))
            AIItemTrustNotes(item: item)
        }
        .padding(.vertical, 4)
    }
    
    private func deleteItem(at offsets: IndexSet) {
        foodItems.remove(atOffsets: offsets)
    }
    
    private func logAllItems() {
        guard let userID = DIContainer.shared.authService.currentUserID, !foodItems.isEmpty else { return }
        
        let mealName = "AI Quick Log"
        let reviewedItems = foodItems.map { item in
            item.markedUserConfirmed(sourceType: item.sourceMetadata?.sourceType ?? .aiText)
        }
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: mealName,
            foodItems: reviewedItems,
            source: "ai_text"
        )
        
        onLogComplete()
        dismiss()
    }
}
