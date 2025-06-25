import SwiftUI
import FirebaseAuth // Added import

struct WeightChartViewController: View { // This is a SwiftUI View
    @EnvironmentObject var goalSettings: GoalSettings

    // Removed @State weight and targetWeight, as they come from goalSettings
    @State private var showTargetWeightSheet = false // controls the visibility of the target weight sheet
    @State private var targetWeightInput: String = "" // Separate state for the TextField input

    var body: some View {
        // Changed NavigationView to VStack as it's embedded, not root
        VStack {
            if let target = goalSettings.targetWeight {
                // Show the current target weight and a "Change" button.
                HStack {
                    Text("Target: \(String(format: "%.1f", target)) lbs") // Simplified label
                        .font(.subheadline) // Smaller font
                    Spacer()
                    Button(action: {
                        // Pre-fill sheet input with current target
                        targetWeightInput = String(format: "%.1f", target)
                        showTargetWeightSheet = true // Opens the sheet to change the target weight.
                    }) {
                        Text("Change")
                            .font(.subheadline) // Smaller font
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)

                if let progress = goalSettings.calculateWeightProgress() {
                    // Use the custom ProgressBar
                    ProgressBar(
                        currentWeight: goalSettings.weight,
                        initialWeight: goalSettings.weightHistory.first?.weight ?? goalSettings.weight, // Use first history entry or current weight
                        targetWeight: target // Pass the non-optional target
                    )
                    .padding(.horizontal)
                    .frame(height: 15) // Give progress bar fixed height

                    // Display percentage text below the bar
                    Text("Progress: \(String(format: "%.0f", progress))%") // Use integer percentage
                        .font(.caption) // Smaller font
                        .foregroundColor(.gray)
                        .padding(.top, 2)

                }

                // Commented out weekly change insight for now to focus on progress bar
                // if let weeklyChange = goalSettings.calculateWeeklyWeightChange() {
                //     Text(weeklyChangeInsight(weeklyChange))
                //         .font(.caption)
                //         .foregroundColor(.gray)
                //         .padding(.horizontal)
                // }

            } else {
                // Show a button to set the target weight.
                Button(action: {
                    targetWeightInput = "" // Clear input field for initial set
                    showTargetWeightSheet = true // Opens the sheet to set a target weight.
                }) {
                    Text("Set Target Weight")
                        .font(.subheadline) // Smaller font
                        .padding(.vertical, 8) // Adjust padding
                        .padding(.horizontal, 12)
                       // .frame(maxWidth: .infinity) // Remove if button shouldn't be full width
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8) // Slightly smaller corner radius
                }
                .padding(.horizontal)
            }
        }
        // Removed height constraint from VStack, let content determine size
        .sheet(isPresented: $showTargetWeightSheet) {
            NavigationView { // NavigationView inside sheet for title/toolbar
                Form {
                    Section(header: Text("Target Weight")) {
                        TextField("Enter target weight (lbs)", text: $targetWeightInput)
                            .keyboardType(.decimalPad)
                    }
                    Button(action: {
                        saveTargetWeight()
                        showTargetWeightSheet = false
                    }) {
                        Text("Save Target Weight")
                           // .font(.title2) // Use default button font
                            .frame(maxWidth: .infinity, alignment: .center) // Center button text
                           // .padding() // Default padding is often fine
                           // .background(Color.blue) // Form button style might handle this
                           // .foregroundColor(.white)
                           // .cornerRadius(10)
                    }
                   // .padding(.top) // Form adds spacing
                }
                .navigationTitle("Set Target Weight")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showTargetWeightSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction){
                         Button("Save") {
                             saveTargetWeight()
                             showTargetWeightSheet = false
                         }
                         // Disable save if input is invalid
                         .disabled(Double(targetWeightInput) == nil || (Double(targetWeightInput) ?? 0) <= 0)
                    }
                }
            }
        }
    }

    private func saveTargetWeight() {
        guard let targetValue = Double(targetWeightInput), targetValue > 0 else {
             print("Invalid target weight input: \(targetWeightInput)")
            return
        }
        print("Valid target weight input: \(targetValue)")
        goalSettings.targetWeight = targetValue
        if let userID = Auth.auth().currentUser?.uid {
            print("Saving target weight for user: \(userID)")
            goalSettings.saveUserGoals(userID: userID)
        } else {
            print("No authenticated user found when saving target weight")
        }
        goalSettings.recalculateAllGoals()
    }

    // ProgressBar Struct Definition (should be inside or accessible to WeightChartViewController)
    struct ProgressBar: View {
        let currentWeight: Double
        let initialWeight: Double
        let targetWeight: Double

        // Calculate progress fraction (0.0 to 1.0)
        var progress: Double {
            let totalChangeNeeded = initialWeight - targetWeight
            // Avoid division by zero if initial and target are the same
            guard abs(totalChangeNeeded) > 0.01 else {
                return abs(currentWeight - targetWeight) < 0.01 ? 1.0 : 0.0 // 100% if already at target, else 0%
            }
            let changeSoFar = initialWeight - currentWeight
            // Clamp progress between 0 and 1
            return max(0.0, min(1.0, changeSoFar / totalChangeNeeded))
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background bar
                    Rectangle()
                        .fill(Color.gray.opacity(0.3)) // Slightly darker background
                        .frame(height: 8) // Thinner bar
                        .cornerRadius(4)
                    // Progress bar
                    Rectangle()
                        .fill(progressColor) // Use dynamic color
                        .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                        .cornerRadius(4)
                        .animation(.easeInOut, value: progress) // Animate progress changes
                }
            }
            .frame(height: 8) // Ensure GeometryReader container has height
        }

        // Determine color based on progress direction
        var progressColor: Color {
             // Gaining towards a higher target OR Losing towards a lower target
            if (targetWeight > initialWeight && currentWeight > initialWeight) || (targetWeight < initialWeight && currentWeight < initialWeight) {
                 return Color(red: 67/255, green: 173/255, blue: 111/255) // Green for progress
             } else if progress > 0 {
                 return .orange // Orange if moving away from start but not target direction
             } else {
                 return .gray.opacity(0.3) // No progress or moving wrong way from start
             }
        }
    }

     // Keep this commented out or remove if not used
     // private func weeklyChangeInsight(_ weeklyChange: Double) -> String{ ... }
}

// Removed Preview as it requires EnvironmentObject setup
// #Preview { WeightChartViewController() }
