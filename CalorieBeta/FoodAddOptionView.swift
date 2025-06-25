import SwiftUI
import FirebaseFirestore

// This view provides options for adding food to the user's log, allowing them to either
// manually add a food item or search for one. It is typically presented as a modal sheet.
struct FoodAddOptionView: View {
    // Bindings to control the navigation flow and visibility of subsequent views.
    @Binding var showManualAdd: Bool // Toggles the manual food addition view.
    @Binding var showSearch: Bool // Toggles the food search view.

    // Environment variable to dismiss the current view.
    @Environment(\.dismiss) var dismiss

    // The main body of the view, wrapped in a NavigationView for a title.
    var body: some View {
        NavigationView {
            // Vertical stack to arrange the buttons and content.
            VStack(spacing: 20) {
                // Button to trigger manual food addition.
                Button(action: {
                    showManualAdd = true // Sets the flag to show the manual add view.
                    dismiss() // Dismisses this view to proceed.
                }) {
                    Text("Manually Add Food") // Button label.
                        .font(.title2) // Larger, bold font for emphasis.
                        .frame(maxWidth: .infinity) // Expands to full width.
                        .padding() // Adds internal padding.
                        .background(Color.blue) // Blue background for visibility.
                        .foregroundColor(.white) // White text for contrast.
                        .cornerRadius(10) // Rounded corners.
                        .padding(.horizontal) // Adds horizontal padding from edges.
                }

                // Button to trigger food search.
                Button(action: {
                    showSearch = true // Sets the flag to show the search view.
                    dismiss() // Dismisses this view to proceed.
                }) {
                    Text("Search for Food") // Button label.
                        .font(.title2) // Larger, bold font.
                        .frame(maxWidth: .infinity) // Expands to full width.
                        .padding() // Adds internal padding.
                        .background(Color.green) // Green background for visibility.
                        .foregroundColor(.white) // White text for contrast.
                        .cornerRadius(10) // Rounded corners.
                        .padding(.horizontal) // Adds horizontal padding.
                }

                Spacer() // Pushes the buttons to the top, leaving space at the bottom.
            }
            .navigationTitle("Add Food") // Sets the navigation bar title.
        }
    }
}
