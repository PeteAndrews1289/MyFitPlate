import SwiftUI
import FirebaseFirestore

// This view allows users to manually enter and save food details (name and calories) associated
// with a barcode, storing the data in Firestore. It is typically presented as a sheet.
struct ManualFoodEntryView: View {
    // The barcode associated with the food item being entered.
    var barcode: String

    // State variables to manage user input for food details.
    @State private var name = "" // Stores the name of the food.
    @State private var calories = "" // Stores the calorie value as a string.

    // Environment variable to dismiss the current view.
    @Environment(\.dismiss) var dismiss

    // The main body of the view, organized in a vertical stack.
    var body: some View {
        VStack { // Vertical stack to arrange the content.
            Text("Add New Food") // Title of the view.
                .font(.headline) // Uses a bold, larger font for emphasis.

            // Input field for the food name.
            TextField("Food Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle()) // Applies a rounded border style.

            // Input field for calories, restricted to numeric input.
            TextField("Calories", text: $calories)
                .keyboardType(.numberPad) // Shows a numeric keypad.
                .textFieldStyle(RoundedBorderTextFieldStyle()) // Rounded border style.

            // Button to save the entered data to Firestore.
            Button("Save") {
                saveToFirestore() // Calls the save function.
                dismiss() // Dismisses the view after saving.
            }
            .padding() // Adds internal padding.
            .background(Color.green) // Green background for visibility.
            .foregroundColor(.white) // White text for contrast.
            .cornerRadius(8) // Rounded corners.
        }
        .padding() // Adds padding around the entire view.
    }

    // Saves the entered food details to Firestore under the barcode document.
    private func saveToFirestore() {
        let db = Firestore.firestore() // Initializes the Firestore database instance.
        db.collection("barcodes").document(barcode).setData([ // Accesses or creates a document with the barcode ID.
            "name": name, // Stores the food name.
            "calories": Double(calories) ?? 0 // Converts calories to Double, defaults to 0 if invalid.
        ])
    }
}
