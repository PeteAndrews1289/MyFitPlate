import SwiftUI
import FirebaseAuth

struct AISummaryView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Binding var estimatedItems: [FoodItem]?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("AI Found These Items")) {
                        ForEach(Binding($estimatedItems) ?? .constant([])) { $item in
                            NavigationLink(destination: foodDetailDestination(for: $item)) {
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
                .disabled(estimatedItems?.isEmpty ?? true)
            }
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        estimatedItems = nil
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func itemRow(for item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .appFont(size: 17, weight: .semibold)
            Text("Serving: \(item.servingSize)")
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text("Est: \(Int(item.calories)) cal, P:\(Int(item.protein))g, C:\(Int(item.carbs))g, F:\(Int(item.fats))g")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func foodDetailDestination(for item: Binding<FoodItem>) -> some View {
        FoodDetailView(
            initialFoodItem: item.wrappedValue,
            dailyLog: .constant(nil),
            date: dailyLogService.activelyViewedDate,
            source: "image_result_edit",
            onLogUpdated: { },
            onUpdate: { updatedItem in
                if let index = estimatedItems?.firstIndex(where: { $0.id == updatedItem.id }) {
                    estimatedItems?[index] = updatedItem
                }
            }
        )
    }
    
    private func deleteItem(at offsets: IndexSet) {
        estimatedItems?.remove(atOffsets: offsets)
    }
    
    private func logAllItems() {
        guard let userID = Auth.auth().currentUser?.uid, let items = estimatedItems, !items.isEmpty else { return }
        
        let mealName = "AI Logged Meal"
        dailyLogService.addMealToCurrentLog(for: userID, mealName: mealName, foodItems: items)
        
        estimatedItems = nil
        dismiss()
    }
}
