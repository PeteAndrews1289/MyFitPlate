import SwiftUI
import HealthKit

struct HealthActivityCard: View {
    @EnvironmentObject var healthViewModel: HealthKitViewModel
    @AppStorage("hasRequestedAppleHealthAccess") private var hasRequestedAppleHealthAccess = false

    // Default goal, could be customizable later
    private let stepGoal: Double = 10000

    var body: some View {
        Group {
            if healthViewModel.hasSyncedHealthData {
                connectedContent
            } else {
                connectContent
            }
        }
        .asCard()
        .onAppear {
            if healthViewModel.isAuthorized {
                healthViewModel.fetchTodayPassiveData()
            }
        }
    }

    private var connectedContent: some View {
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
    }

    private var connectContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.red)
                .frame(width: 46, height: 46)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Add Apple Health context")
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Bring steps, activity, sleep, and recovery into your dashboard.")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(hasRequestedAppleHealthAccess ? "Review access" : "Connect") {
                if hasRequestedAppleHealthAccess,
                   let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                } else {
                    hasRequestedAppleHealthAccess = true
                    healthViewModel.authError = nil
                    healthViewModel.requestAuthorization()
                }
            }
            .appFont(size: 12, weight: .bold)
            .buttonStyle(.bordered)
            .tint(.brandPrimary)
            .accessibilityHint(
                hasRequestedAppleHealthAccess
                    ? "Opens Settings so you can review Apple Health access"
                    : "Shows Apple's Health access request"
            )
        }
        .accessibilityElement(children: .contain)
        .onChange(of: healthViewModel.isAuthorized) { _, isAuthorized in
            if isAuthorized {
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
