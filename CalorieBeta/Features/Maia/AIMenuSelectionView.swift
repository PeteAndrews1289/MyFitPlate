import SwiftUI

struct AIMenuSelectionView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Binding var estimatedItems: [FoodItem]?
    @Environment(\.dismiss) var dismiss

    @State private var selectedItemIDs: Set<String> = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AIEstimateReviewBanner(
                    title: "Menu Estimate",
                    message: "Pick only what you ate. Restaurant portions vary, so use this as a smart estimate rather than a verified menu label."
                )
                .padding()

                List {
                    Section(header: Text("Select What You Ate")) {
                        ForEach(estimatedItems ?? []) { item in
                            Button(action: {
                                toggleSelection(for: item)
                            }) {
                                HStack {
                                    itemRow(for: item)
                                    Spacer()
                                    if selectedItemIDs.contains(item.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.brandPrimary)
                                            .appFont(size: 22)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                            .appFont(size: 22)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Button("Log Selected Items") {
                    logSelectedItems()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
                .disabled(selectedItemIDs.isEmpty)
            }
            .navigationTitle("Menu Results")
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
    
    private func toggleSelection(for item: FoodItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }
    
    @ViewBuilder
    private func itemRow(for item: FoodItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name)
                    .appFont(size: 17, weight: .semibold)
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
    
    private func logSelectedItems() {
        guard let userID = DIContainer.shared.authService.currentUserID, let items = estimatedItems else { return }
        
        let selectedItems = items
            .filter { selectedItemIDs.contains($0.id) }
            .map { item in
                item.markedUserConfirmed(sourceType: item.sourceMetadata?.sourceType ?? .aiMenu)
            }
        guard !selectedItems.isEmpty else { return }
        
        let mealName = "AI Menu Log"
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: mealName,
            foodItems: selectedItems,
            source: "ai_menu"
        )
        
        estimatedItems = nil
        dismiss()
    }
}
