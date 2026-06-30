import SwiftUI

struct AISummaryView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Binding var estimatedItems: [FoodItem]?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AIEstimateReviewBanner(
                    title: "AI Estimate",
                    message: "Check servings and macros before logging. For best accuracy next time, include the whole plate and a clear size reference."
                )
                .padding([.horizontal, .top])

                List {
                    Section(header: Text("Review Items")) {
                        ForEach(Binding($estimatedItems) ?? .constant([])) { $item in
                            NavigationLink(destination: foodDetailDestination(for: $item)) {
                                itemRow(for: item)
                            }
                        }
                        .onDelete(perform: deleteItem)
                    }
                }
                
                Text("Tap any item to edit it, or swipe to remove anything Maia guessed incorrectly.")
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
        guard let userID = DIContainer.shared.authService.currentUserID, let items = estimatedItems, !items.isEmpty else { return }
        
        let mealName = "AI Logged Meal"
        let reviewedItems = items.map { item in
            item.markedUserConfirmed(sourceType: item.sourceMetadata?.sourceType ?? .aiImage)
        }
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: mealName,
            foodItems: reviewedItems,
            source: "ai_image"
        )
        
        estimatedItems = nil
        dismiss()
    }
}

struct AIReviewStatusPill: View {
    let item: FoodItem

    private var statusText: String {
        switch item.sourceMetadata?.reviewStatus {
        case .userEdited:
            return "Edited"
        case .userConfirmed:
            return "Reviewed"
        default:
            return "Needs Review"
        }
    }

    private var tint: Color {
        switch item.sourceMetadata?.reviewStatus {
        case .userEdited, .userConfirmed:
            return .accentPositive
        default:
            return .orange
        }
    }

    var body: some View {
        Text(statusText)
            .appFont(size: 10, weight: .bold)
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

struct AIItemTrustNotes: View {
    let item: FoodItem

    var body: some View {
        if item.hasMeaningfulCalorieMacroMismatch {
            Label("Calories and macros need review", systemImage: "exclamationmark.triangle.fill")
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(.orange)
                .labelStyle(.titleAndIcon)
        }
    }
}

struct AIEstimateReviewBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .appFont(size: 18, weight: .bold)
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Needs Review")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.10), in: Capsule())
                }

                Text(message)
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }
}
