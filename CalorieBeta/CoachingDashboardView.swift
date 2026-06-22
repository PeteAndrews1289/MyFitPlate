import SwiftUI

struct CoachingDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var goalSettings: GoalSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.brandPrimary)
                            Text("Maia's Strategy")
                                .appFont(size: 22, weight: .bold)
                        }

                        Text("Here is my reasoning for your macro targets this week.")
                            .appFont(size: 15)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .padding(.bottom, 10)

                        VStack(alignment: .leading, spacing: 16) {
                            CoachingInsightRow(
                                icon: "chart.line.down.forward",
                                title: "Weight Plateau Detected",
                                description: "Your average weight has been stable for 10 days. I've adjusted your daily carbohydrates down by 15g to resume fat loss while preserving workout energy.",
                                color: .orange
                            )

                            CoachingInsightRow(
                                icon: "flame.fill",
                                title: "High Activity Adaptation",
                                description: "You burned an average of 400 active calories/day this week. Your protein target is elevated to 1.1g/lb to ensure optimal recovery.",
                                color: .red
                            )

                            CoachingInsightRow(
                                icon: "moon.zzz.fill",
                                title: "Sleep Debt Adjustment",
                                description: "Your sleep consistency is below 70%. I recommend prioritizing whole-food fats tonight to support hormone production and restorative sleep.",
                                color: .indigo
                            )
                        }
                    }
                    .padding(20)
                    .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Coaching Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}

private struct CoachingInsightRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(description)
                    .appFont(size: 14)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
        }
    }
}
