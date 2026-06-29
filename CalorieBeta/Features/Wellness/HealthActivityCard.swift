import SwiftUI
import HealthKit

struct HealthActivityCard: View {
    @EnvironmentObject var healthViewModel: HealthKitViewModel
    
    // Default goal, could be customizable later
    private let stepGoal: Double = 10000
    
    var body: some View {
        HStack(spacing: 16) {
            // Steps Section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.brandPrimary)
                    Text("Steps")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(healthViewModel.todaySteps))")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.primary)
                    Text("/ \(Int(stepGoal))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.brandPrimary.opacity(0.15))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(Color.brandPrimary)
                            .frame(width: max(0, min(geometry.size.width * CGFloat(healthViewModel.todaySteps / stepGoal), geometry.size.width)), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 50)
            
            // Active Energy Section
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Active")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(healthViewModel.todayActiveEnergy))")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.primary)
                    Text("kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Small placeholder or label since there's no fixed goal for active energy
                Text("Burned Today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.backgroundPrimary)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        .onAppear {
            if !healthViewModel.isAuthorized {
                healthViewModel.requestAuthorization()
            } else {
                healthViewModel.fetchTodayPassiveData()
            }
        }
    }
}

#Preview {
    let vm = HealthKitViewModel()
    
    HealthActivityCard()
        .environmentObject(vm)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
}
