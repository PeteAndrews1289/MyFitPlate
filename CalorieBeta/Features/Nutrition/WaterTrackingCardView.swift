import SwiftUI
import FirebaseAuth

struct WaterTrackingCardView: View {
    @EnvironmentObject var dailyLogService : DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    
    var date: Date
    var insight: UserInsight?
    
    private let waterIncrement: Double = 8.0

    private var waterIntake: Double {
        dailyLogService.currentDailyLog?.waterTracker?.totalOunces ?? 0.0
    }

    private var waterGoal: Double {
        max(1, goalSettings.waterGoal)
    }

    private var remainingWater: Double {
        max(waterGoal - waterIntake, 0)
    }
    
    var body: some View {
        let progress = max(0, min(1, waterIntake / waterGoal))
        
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.fill")
                            .appFont(size: 14, weight: .bold)
                            .foregroundColor(.cyan)
                            .frame(width: 30, height: 30)
                            .background(Color.cyan.opacity(0.12), in: Circle())

                        Text("Hydration")
                            .appFont(size: 21, weight: .bold)
                            .foregroundColor(.textPrimary)
                    }

                    Text(remainingWater > 0 ? "\(Int(remainingWater.rounded())) oz left to hit your goal." : "Goal reached. Keep sipping as needed.")
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))

                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.cyan.opacity(0.12))

                                Capsule()
                                    .fill(LinearGradient(colors: [.cyan, Color.brandPrimary.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * CGFloat(progress))
                                    .animation(.easeInOut(duration: 0.45), value: progress)
                            }
                        }
                        .frame(height: 10)

                        HStack {
                            Text("\(Int(waterIntake.rounded())) / \(Int(waterGoal.rounded())) oz")
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(.textPrimary)

                            Spacer()

                            Text("\(Int((progress * 100).rounded()))%")
                                .appFont(size: 12, weight: .semibold)
                                .foregroundColor(.cyan)
                        }
                    }

                    HStack(spacing: 10) {
                        WaterAdjustButton(icon: "minus", title: "-\(Int(waterIncrement)) oz") {
                            HapticManager.instance.feedback(.light)
                            adjustWater(by: -waterIncrement)
                        }
                        .disabled(waterIntake < waterIncrement && waterIntake != 0)

                        WaterAdjustButton(icon: "plus", title: "+\(Int(waterIncrement)) oz") {
                            HapticManager.instance.feedback(.medium)
                            adjustWater(by: waterIncrement)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.cyan, Color.brandPrimary.opacity(0.72)]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: geometry.size.height * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.5), value: progress)

                        WaterBottleShape()
                            .stroke(Color(UIColor.secondaryLabel).opacity(0.78), lineWidth: 1.5)
                    }
                    .mask(WaterBottleShape())
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(width: 62, height: 104)
            }

            if let insight = insight {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.yellow)
                        .frame(width: 28, height: 28)
                        .background(Color.yellow.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title)
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(.textPrimary)

                        Text(insight.message)
                            .appFont(size: 12)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(4)
                    }
                }
                .padding(12)
                .background(Color.backgroundPrimary.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
    }
    
    private func adjustWater(by amount: Double) {
        guard let userID = Auth.auth().currentUser?.uid else {
            return
        }
        let newIntake = waterIntake + amount
        if newIntake >= 0 {
            dailyLogService.addWaterToCurrentLog(for: userID, amount: amount, goalOunces: goalSettings.waterGoal)
        } else if waterIntake > 0 && amount < 0 {
             dailyLogService.addWaterToCurrentLog(for: userID, amount: -waterIntake, goalOunces: goalSettings.waterGoal)
        }
    }
}

private struct WaterAdjustButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .appFont(size: 12, weight: .bold)
                Text(title)
                    .appFont(size: 12, weight: .semibold)
            }
            .foregroundColor(.brandPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.brandPrimary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
