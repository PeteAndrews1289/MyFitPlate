import SwiftUI
import FirebaseAuth

struct WeeklyCheckInView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var adaptiveGoalService: AdaptiveGoalService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    if adaptiveGoalService.dataConfidence == .high || adaptiveGoalService.dataConfidence == .medium {
                        statsSection
                        actionSection
                    } else {
                        needsDataSection
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Weekly Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.brandPrimary)
                .padding()
                .background(Color.brandPrimary.opacity(0.12), in: Circle())
            
            Text("Time for your check-in!")
                .appFont(size: 24, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("We've analyzed your weight and nutrition data from the past 3 weeks to adjust your metabolism estimate.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 16)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Data")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(adaptiveGoalService.dataConfidence.rawValue)
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(Color(adaptiveGoalService.dataConfidence.colorName))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(adaptiveGoalService.dataConfidence.colorName).opacity(0.12), in: Capsule())
            }
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Avg Intake",
                    value: adaptiveGoalService.last21DaysCalorieAverage != nil ? "\(Int(adaptiveGoalService.last21DaysCalorieAverage!))" : "--",
                    subtitle: "kcal / day",
                    icon: "fork.knife",
                    color: .orange
                )
                
                StatCard(
                    title: "Weight Trend",
                    value: adaptiveGoalService.weightChangeRatePerDay != nil ? "\(String(format: "%.2f", adaptiveGoalService.weightChangeRatePerDay! * 7))" : "--",
                    subtitle: "lbs / week",
                    icon: "scalemass.fill",
                    color: .teal
                )
            }
            
            Divider()
            
            VStack(spacing: 8) {
                Text("Calculated TDEE")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(adaptiveGoalService.calculatedTDEE != nil ? "\(Int(adaptiveGoalService.calculatedTDEE!))" : "--")
                        .appFont(size: 48, weight: .heavy)
                        .foregroundColor(.textPrimary)
                    Text(" kcal")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .asCard()
    }
    
    private var actionSection: some View {
        VStack(spacing: 12) {
            Button(action: acceptTargets) {
                Text("Accept New Targets")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            
            Button(action: skipCheckIn) {
                Text("Keep Current Targets")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var needsDataSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("Needs More Data")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)
            
            Text("We need at least 7 days of weight data and 10 days of food logs to confidently adjust your TDEE.")
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
            
            Button(action: skipCheckIn) {
                Text("Check back later")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .asCard()
    }
    
    private func acceptTargets() {
        HapticFeedback.selection()
        goalSettings.calorieGoalMethod = .dynamicTDEE
        goalSettings.lastCheckInDate = Date()
        goalSettings.recalculateAllGoals()
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
    
    private func skipCheckIn() {
        HapticFeedback.selection()
        goalSettings.lastCheckInDate = Date()
        if let userID = Auth.auth().currentUser?.uid {
            goalSettings.saveUserGoals(userID: userID)
        }
        dismiss()
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .padding(8)
                .background(color.opacity(0.12), in: Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                Text(value)
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
