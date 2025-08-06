import SwiftUI

struct CycleInsightCard: View {
    let insight: AIInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Swapped Text elements for better hierarchy
            Text(insight.phaseTitle)
                .appFont(size: 20, weight: .semibold)
                .foregroundColor(.accentPositive)
            Text(insight.phaseDescription)
                .appFont(size: 14)
            
            Divider()

            VStack(alignment: .leading) {
                Text("Training Focus")
                    .appFont(size: 12).foregroundColor(.secondary)
                Text(insight.trainingFocus.title)
                    .appFont(size: 16, weight: .medium)
                Text(insight.trainingFocus.description)
                    .appFont(size: 14)
            }
            
            Divider()

            HStack {
                VStack(alignment: .leading) {
                    Text("Hormonal State")
                        .appFont(size: 12).foregroundColor(.secondary)
                    Text(insight.hormonalState)
                        .appFont(size: 16, weight: .medium)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Energy Level")
                        .appFont(size: 12).foregroundColor(.secondary)
                    Text(insight.energyLevel)
                        .appFont(size: 16, weight: .medium)
                        .foregroundColor(.brandPrimary)
                }
            }
            
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Nutrition Tip")
                    .appFont(size: 12).foregroundColor(.secondary)
                Text(insight.nutritionTip)
                    .appFont(size: 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Symptom Tip")
                    .appFont(size: 12).foregroundColor(.secondary)
                Text(insight.symptomTip)
                    .appFont(size: 14)
            }
            
            Text("Cycle phases are estimates and should not be used as a form of birth control or medical advice.")
                .appFont(size: 10)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(15)
    }
}
