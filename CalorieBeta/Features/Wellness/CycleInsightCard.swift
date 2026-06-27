import SwiftUI

struct MaiaCycleInsightCard: View {
    let insight: AIInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.brandPrimary)
                Text("Maia's Phase Guide")
                    .appFont(size: 18, weight: .bold)
                Spacer()
            }
            .padding(.bottom, 4)

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
        .padding(20)
        .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.brandPrimary.opacity(0.3), lineWidth: 1)
        )
    }
}
