

import SwiftUI

struct WorkoutReport {
    let totalWorkouts: Int
    let totalCaloriesBurned: Double
    let mostFrequentWorkout: String
}

struct WorkoutReportCard: View {
    let report: WorkoutReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.run")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout Summary")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Training volume and most frequent activity.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            
            HStack(spacing: 10) {
                workoutStatBox(
                    value: "\(report.totalWorkouts)",
                    label: "Workouts",
                    icon: "calendar.badge.checkmark",
                    color: .blue
                )
                workoutStatBox(
                    value: String(format: "%.0f", report.totalCaloriesBurned),
                    label: "Calories",
                    icon: "flame.fill",
                    color: .orange
                )
            }

            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 30, height: 30)
                    .background(Color.brandPrimary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Most frequent")
                        .appFont(size: 11, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Text(report.mostFrequentWorkout)
                        .appFont(size: 15, weight: .semibold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .background(Color.backgroundSecondary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .asCard()
    }
    
    @ViewBuilder
    private func workoutStatBox(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .appFont(size: 13, weight: .bold)
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: Circle())

            Text(value)
                .appFont(size: 22, weight: .bold)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
