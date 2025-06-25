import SwiftUI

// This view allows users to manually add a food item by entering its nutritional details.
// It is typically presented as a sheet and triggers a callback when a food item is logged.
struct AddFoodView: View {
    // Closure to notify the parent view when a new food item is logged.
    var onFoodLogged: (FoodItem) -> Void

    // State variables to manage user input for food details.
    @State private var foodName = "" // Stores the name of the food.
    @State private var calories = "" // Stores the calorie value as a string.
    @State private var protein = "" // Stores the protein value in grams.
    @State private var carbs = "" // Stores the carbohydrate value in grams.
    @State private var fats = "" // Stores the fat value in grams.

    // Environment variable to dismiss the current view.
    @Environment(\.dismiss) var dismiss

    // The main body of the view, organized in a vertical stack.
    var body: some View {
        VStack(spacing: 12) { // Vertical stack with spacing between elements.
            // Input field for the food name.
            TextField("Food Name", text: $foodName)
                .textFieldStyle(RoundedBorderTextFieldStyle()) // Applies a rounded border style.
                .padding(.horizontal) // Adds horizontal padding from edges.

            // Input field for calories, restricted to numeric input.
            TextField("Calories", text: $calories)
                .keyboardType(.decimalPad) // Shows a numeric keypad with decimals.
                .textFieldStyle(RoundedBorderTextFieldStyle()) // Rounded border style.
                .padding(.horizontal) // Adds horizontal padding.

            // Input field for protein in grams.
            TextField("Protein (g)", text: $protein)
                .keyboardType(.decimalPad) // Numeric keypad for decimal input.
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // Input field for carbohydrates in grams.
            TextField("Carbs (g)", text: $carbs)
                .keyboardType(.decimalPad) // Numeric keypad.
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // Input field for fats in grams.
            TextField("Fats (g)", text: $fats)
                .keyboardType(.decimalPad) // Numeric keypad.
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // Button to log the food item.
            Button(action: logFood) {
                Text("Log Food") // Button label.
                    .font(.title3) // Slightly larger font for emphasis.
                    .frame(maxWidth: .infinity) // Expands to full width.
                    .padding(.vertical, 8) // Adds vertical padding inside the button.
                    .background(Color.green) // Green background for visibility.
                    .foregroundColor(.white) // White text for contrast.
                    .cornerRadius(10) // Rounded corners.
                    .padding(.horizontal, 40) // Adds extra horizontal padding.
            }
        }
        .navigationTitle("Add Food") // Sets the navigation bar title.
    }

    // Validates input and logs the new food item, then dismisses the view.
    private func logFood() {
        // Ensures the food name is not empty and calories can be converted to a Double.
        guard !foodName.isEmpty, let caloriesValue = Double(calories) else {
            print("Invalid input: food name or calories") // Logs an error for debugging.
            return
        }

        // Converts optional numeric inputs to Doubles, defaulting to 0 if invalid.
        let proteinValue = Double(protein) ?? 0.0
        let carbsValue = Double(carbs) ?? 0.0
        let fatsValue = Double(fats) ?? 0.0

        // Creates a new FoodItem with the entered values.
        let newFood = FoodItem(
            id: UUID().uuidString, // Generates a unique ID for the food item.
            name: foodName,
            calories: caloriesValue,
            protein: proteinValue,
            carbs: carbsValue,
            fats: fatsValue,
            servingSize: "N/A", // Placeholder for serving size.
            servingWeight: 0.0 // Placeholder for serving weight.
        )

        onFoodLogged(newFood) // Calls the callback to notify the parent view.
        dismiss() // Dismisses the view after logging.
    }
}
