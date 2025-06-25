import SwiftUI
// Removed Charts import as we're building manually

struct MicronutrientProgressView: View {
    var dailyLog: DailyLog
    @ObservedObject var goalSettings: GoalSettings
    @Environment(\.colorScheme) var colorScheme

    // Define the order and display names for micronutrients we are tracking
    private let micronutrients: [(key: String, name: String, unit: String)] = [
        ("calcium", "Calcium", "mg"),
        ("iron", "Iron", "mg"),
        ("potassium", "Potassium", "mg"),
        ("vitaminA", "Vitamin A", "mcg"),
        ("vitaminC", "Vitamin C", "mg"),
        ("vitaminD", "Vitamin D", "mcg"),
        ("sodium", "Sodium", "mg") // Keep Sodium last or group differently if needed
    ]

    // Define the grid layout: two columns
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        // Check if goals are loaded
        if goalSettings.calciumGoal != nil { // Using calciumGoal as a proxy
            let totals = dailyLog.totalMicronutrients()

            // Use LazyVGrid for the two-column layout
            LazyVGrid(columns: columns, spacing: 20) { // Added spacing between rows
                ForEach(micronutrients, id: \.key) { micro in
                    let intake = getIntake(for: micro.key, from: totals)
                    let goal = getGoal(for: micro.key)
                    // Calculate percentage (0.0 to potentially > 1.0)
                    let percentageValue = (goal > 0) ? (intake / goal) : 0.0
                    let displayPercentage = Int(round(percentageValue * 100))

                    // Use the new row view
                    MicronutrientRow(
                        name: micro.name,
                        percentage: displayPercentage,
                        progress: percentageValue, // Pass the raw fraction for the bar
                        isSodium: micro.key == "sodium"
                    )
                }
            }
            .padding() // Add padding around the grid

        } else {
             // Loading state
             VStack {
                 ProgressView()
                 Text("Loading Goals...")
                     .font(.caption)
                     .foregroundColor(.gray)
             }
             .frame(minHeight: 180)
         }
    }

    // Helper functions (remain the same)
    private func getIntake(for key: String, from totals: (calcium: Double, iron: Double, potassium: Double, sodium: Double, vitaminA: Double, vitaminC: Double, vitaminD: Double)) -> Double {
        // ... (implementation is the same as previous version) ...
         switch key {
             case "calcium": return totals.calcium
             case "iron": return totals.iron
             case "potassium": return totals.potassium
             case "sodium": return totals.sodium
             case "vitaminA": return totals.vitaminA
             case "vitaminC": return totals.vitaminC
             case "vitaminD": return totals.vitaminD
             default: return 0
         }
    }

    private func getGoal(for key: String) -> Double {
        // ... (implementation is the same as previous version) ...
        switch key {
            case "calcium": return max(goalSettings.calciumGoal ?? 1, 1)
            case "iron": return max(goalSettings.ironGoal ?? 1, 1)
            case "potassium": return max(goalSettings.potassiumGoal ?? 1, 1)
            case "sodium": return goalSettings.sodiumGoal ?? 2300 // UL
            case "vitaminA": return max(goalSettings.vitaminAGoal ?? 1, 1)
            case "vitaminC": return max(goalSettings.vitaminCGoal ?? 1, 1)
            case "vitaminD": return max(goalSettings.vitaminDGoal ?? 1, 1)
            default: return 1
        }
    }
}

// MARK: - Micronutrient Row View
// Represents a single nutrient row in the grid
struct MicronutrientRow: View {
    let name: String
    let percentage: Int
    let progress: Double // Progress as a fraction (0.0 to 1.0+)
    let isSodium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) { // Reduced spacing
            HStack {
                Text(name)
                    .font(.subheadline) // Slightly smaller font
                    .fontWeight(.medium)
                Spacer()
                Text("\(percentage)%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(getPercentageColor()) // Color based on percentage
            }
            CustomProgressBar(value: progress, isSodium: isSodium)
                .frame(height: 8) // Set height for the progress bar
        }
    }

    // Determine text color based on percentage (similar to bar color logic)
    private func getPercentageColor() -> Color {
        if isSodium {
            return progress >= 1.0 ? .red : .primary // Red if sodium >= 100% UL
        } else {
            return progress >= 1.0 ? .green : .primary // Green if >= 100% RDI/AI
        }
    }
}

// MARK: - Custom Progress Bar
// A simple progress bar view
struct CustomProgressBar: View {
    var value: Double // Input value (fraction, e.g., 0.0 to 1.0+)
    var isSodium: Bool
    @Environment(\.colorScheme) var colorScheme

    // Determine fill color based on progress and nutrient type
    private var fillColor: Color {
        if isSodium {
            return value >= 1.0 ? .red : .orange // Red if >= 100% UL, orange otherwise
        } else {
            return value >= 1.0 ? .green : .accentColor // Green if >= 100% RDI/AI, accent otherwise
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background of the progress bar
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .foregroundColor(colorScheme == .dark ? .gray.opacity(0.4) : .gray.opacity(0.2)) // Background color

                // Filled portion of the progress bar
                RoundedRectangle(cornerRadius: 4)
                    // Calculate width, clamping between 0 and full width
                    .frame(width: min(max(0, CGFloat(value) * geometry.size.width), geometry.size.width), height: geometry.size.height)
                    .foregroundColor(fillColor) // Use dynamic fill color
                    .animation(.easeInOut, value: value) // Animate progress changes
            }
        }
    }
}
