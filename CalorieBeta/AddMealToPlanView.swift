import SwiftUI

struct AddMealToPlanView: View {
    let date: Date
    @Binding var isPresented: Bool
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @StateObject private var recipeService = RecipeService()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                RecipeListView()
                    .environmentObject(recipeService)
            }
            // Corrected the date formatting in the navigation title
            .navigationTitle("Add Meal to \(date, style: .date)")
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            })
        }
        .onAppear {
            Task {
                await recipeService.fetchUserRecipes()
            }
        }
    }
}

fileprivate extension DateFormatter {
    static var shortDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }
}
