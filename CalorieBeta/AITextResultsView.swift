

import SwiftUI
import FirebaseAuth

struct AITextResultsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService
    
    @Binding var foodItems: [FoodItem]
    @State private var itemToEdit: FoodItem?
    
    var onLogComplete: () -> Void

    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("AI Found These Items")) {
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
                
                Text("You can tap an item to edit it, or swipe to delete it before logging.")
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
                    source: "image_result_edit", // This source tells FoodDetailView how to behave
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
            Text(item.name)
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.primary)
            Text("Serving: \(item.servingSize)")
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text("Est: \(Int(item.calories)) cal, P:\(Int(item.protein))g, C:\(Int(item.carbs))g, F:\(Int(item.fats))g")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
    
    private func deleteItem(at offsets: IndexSet) {
        foodItems.remove(atOffsets: offsets)
    }
    
    private func logAllItems() {
        guard let userID = Auth.auth().currentUser?.uid, !foodItems.isEmpty else { return }
        
        let mealName = "AI Quick Log"
        dailyLogService.addMealToCurrentLog(for: userID, mealName: mealName, foodItems: foodItems)
        
        onLogComplete()
        dismiss()
    }
}
