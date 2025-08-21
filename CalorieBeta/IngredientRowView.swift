
import SwiftUI

struct IngredientRowView: View {
    @Binding var ingredient: RecipeIngredient
    @State private var foodItem: FoodItem?
    private let foodAPIService = FatSecretFoodAPIService()
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(ingredient.foodName)
                    .appFont(size: 16, weight: .semibold)
                
                if let foodItem = foodItem {
                    Text("\(foodItem.calories, specifier: "%.0f") kcal, P: \(foodItem.protein, specifier: "%.0f")g, C: \(foodItem.carbs, specifier: "%.0f")g, F: \(foodItem.fats, specifier: "%.0f")g")
                        .appFont(size: 12)
                        .foregroundColor(.secondary)
                } else {
                    Text("Tap to match ingredient...")
                        .appFont(size: 12)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if foodItem != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "magnifyingglass.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: findMatchingFood)
    }
    
    private func findMatchingFood() {
        guard ingredient.foodId == nil else {
            // If we already have an ID, we can assume it's matched.
            // A more robust solution might re-fetch details here.
            return
        }
        
        foodAPIService.fetchFoodByQuery(query: ingredient.foodName) { result in
            DispatchQueue.main.async {
                if case .success(let items) = result, let bestMatch = items.first {
                    self.foodItem = bestMatch
                    self.ingredient.foodId = bestMatch.id
                }
            }
        }
    }
}
