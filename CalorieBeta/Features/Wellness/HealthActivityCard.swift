import SwiftUI
import HealthKit

struct HealthActivityCard: View {
    @EnvironmentObject var healthViewModel: HealthKitViewModel

    // Default goal, could be customizable later
    private let stepGoal: Double = 10000

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .foregroundColor(.blue)
                    Text("Steps")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(Int(healthViewModel.todaySteps.rounded()).formatted())
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.primary)
                    Text("/ \(Int(stepGoal).formatted()) steps")
                        .appFont(size: 12)
                        .foregroundColor(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                            .frame(height: 6)

                        Capsule()
                            .fill(Color.blue)
                            .frame(width: max(0, min(geometry.size.width * CGFloat(healthViewModel.todaySteps / stepGoal), geometry.size.width)), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 50)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Active")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(Int(healthViewModel.todayActiveEnergy.rounded()).formatted())
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.primary)
                    Text("cal")
                        .appFont(size: 12)
                        .foregroundColor(.secondary)
                }

                Text("Burned today")
                    .appFont(size: 11, weight: .medium)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .asCard()
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
