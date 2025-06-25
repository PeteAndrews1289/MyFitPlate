import SwiftUI
import FirebaseAuth

// This view serves as the initial loading screen for the "CalorieBeta" app, displaying a logo
// and progress indicator while data is loaded, with error handling for authentication issues.
struct LandingPageView: View {
    // Environment object to access the app's authentication state.
    @EnvironmentObject var appState: AppState
    // State variable to manage and display any error messages.
    @State private var errorMessage: String?

    // The main body of the view, organized in a ZStack for layered content.
    var body: some View {
        ZStack { // Allows layering of background and content.
            Color.white.edgesIgnoringSafeArea(.all) // Sets a white background across the entire screen.

            VStack(spacing: 20) { // Vertical stack with spacing between elements.
                // Displays the app logo with a circular frame and green border.
                Image("mfp logo") // Placeholder for the app logo (must be added to Assets.xcassets).
                    .resizable() // Allows the image to be resized.
                    .scaledToFit() // Maintains aspect ratio while fitting within bounds.
                    .frame(width: 120, height: 120) // Sets a fixed size for the logo.
                    .clipShape(Circle()) // Clips the image into a circle.
                    .overlay(Circle().stroke(Color.green, lineWidth: 2)) // Adds a green border.
                    .onAppear {
                        print("Loading mfp logo image") // Logs when the image is loaded for debugging.
                    }

                // Displays the app name.
                Text("MyFitPlate")
                    .font(.largeTitle) // Large, prominent font.
                    .fontWeight(.bold) // Bold text for emphasis.
                    .foregroundColor(.black) // Black text for contrast.

                // Conditionally displays error message and retry button or progress indicator.
                if let error = errorMessage { // Shows error state if an error exists.
                    Text(error) // Displays the error message.
                        .foregroundColor(.red) // Red color for error visibility.
                        .padding() // Adds padding around the text.
                    Button("Retry") { // Retry button to reload data.
                        loadData() // Triggers data loading again.
                    }
                    .padding() // Adds padding around the button.
                } else { // Shows progress indicator if no error.
                    ProgressView() // Displays a circular progress indicator.
                        .progressViewStyle(CircularProgressViewStyle(tint: .green)) // Customizes with a green tint.
                        .scaleEffect(1.5) // Increases the size of the progress view.
                }
            }
        }
        .onAppear {
            loadData() // Loads data when the view appears.
        }
    }

    // Loads initial data, checking authentication status and triggering further loading if needed.
    private func loadData() {
        guard let userID = Auth.auth().currentUser?.uid else { // Checks if a user is authenticated.
            errorMessage = "User not authenticated. Please log in." // Sets error if no user.
            return
        }
        // Note: Data loading (e.g., goals, logs) is managed by ContentView, so this is a placeholder.
        // In a full implementation, this could trigger additional data fetches here.
    }
}
