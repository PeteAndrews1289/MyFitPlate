import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject var achievementService: AchievementService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Weekly Challenges")
                    .appFont(size: 34, weight: .bold)
                    .padding(.bottom)

                if achievementService.activeChallenges.isEmpty {
                    Text("No active challenges right now. Check back next week!")
                        .appFont(size: 17, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.backgroundSecondary)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                } else {
                    ForEach(achievementService.activeChallenges) { challenge in
                        ChallengeCardView(challenge: challenge)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.backgroundPrimary.edgesIgnoringSafeArea(.all))
    }
}

struct ChallengeCardView: View {
    let challenge: Challenge

    private var progressValue: Double {
        guard challenge.goal > 0 else { return 0 }
        return min(challenge.progress / challenge.goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(challenge.title)
                        .appFont(size: 17, weight: .bold)
                    Text(challenge.description)
                        .appFont(size: 15)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("+\(challenge.pointsValue) pts")
                    .appFont(size: 12, weight: .bold)
                    .padding(6)
                    .background(Color.brandPrimary.opacity(0.2))
                    .cornerRadius(8)
            }

            ProgressView(value: progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: .brandPrimary))
                .padding(.vertical, 4)

            HStack {
                Text("Progress: \(Int(challenge.progress)) / \(Int(challenge.goal))")
                    .appFont(size: 12)
                Spacer()
                Text("Ends: \(challenge.expiresAt.dateValue(), style: .relative)")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}
