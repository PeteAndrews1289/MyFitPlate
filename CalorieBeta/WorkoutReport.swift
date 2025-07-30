

import SwiftUI

struct WorkoutReport {
    let totalWorkouts: Int
    let totalCaloriesBurned: Double
    let mostFrequentWorkout: String
}

struct WorkoutReportCard: View {
    let report: WorkoutReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Workout Summary")
                .appFont(size: 17, weight: .semibold)
                .padding([.top, .leading, .trailing])
            
            HStack(spacing: 16) {
                workoutStatBox(value: "\(report.totalWorkouts)", label: "Workouts")
                workoutStatBox(value: String(format: "%.0f", report.totalCaloriesBurned), label: "Calories Burned")
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Most Frequent Activity")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(report.mostFrequentWorkout)
                    .appFont(size: 15)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .asCard()
    }
    
    @ViewBuilder
    private func workoutStatBox(value: String, label: String) -> some View {
        VStack {
            Text(value)
                .appFont(size: 22, weight: .semibold)
                .foregroundColor(.brandPrimary)
            Text(label)
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }
}
