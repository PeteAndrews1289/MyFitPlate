import SwiftUI

struct ChallengesView: View {
    @EnvironmentObject var achievementService: AchievementService
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Weekly Challenges")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom)

                if achievementService.activeChallenges.isEmpty {
                    Text("No active challenges right now. Check back next week!")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
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
        .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
    }
}

struct ChallengeCardView: View {
    let challenge: Challenge
    @Environment(\.colorScheme) var colorScheme

    private var progressValue: Double {
        guard challenge.goal > 0 else { return 0 }
        return min(challenge.progress / challenge.goal, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(challenge.title)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(challenge.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("+\(challenge.pointsValue) pts")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(6)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(8)
            }

            ProgressView(value: progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .padding(.vertical, 4)

            HStack {
                Text("Progress: \(Int(challenge.progress)) / \(Int(challenge.goal))")
                    .font(.caption)
                Spacer()
                Text("Ends: \(challenge.expiresAt.dateValue(), style: .relative)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}
