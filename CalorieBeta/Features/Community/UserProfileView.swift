import SwiftUI
import FirebaseAuth

struct UserProfileView: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var achievementService: AchievementService
    @Environment(\.dismiss) var dismiss

    @State private var errorMessage: ErrorMessage?
    @State private var showingChallenges = false

    private var userLevelDisplay: String {
        "Level \(achievementService.userAchievementLevel)"
    }

    private var pointsToNextLevel: Int {
        let currentLevelIndex = achievementService.userAchievementLevel - 1
        guard currentLevelIndex >= 0 && currentLevelIndex < achievementService.levelThresholds.count - 1 else {
            return 0
        }
        return achievementService.levelThresholds[currentLevelIndex + 1] - achievementService.userTotalAchievementPoints
    }

    private var progressToNextLevel: Double {
        let currentLevelIndex = achievementService.userAchievementLevel - 1
        guard currentLevelIndex >= 0 else { return 0.0 }

        let currentLevelThreshold = currentLevelIndex < achievementService.levelThresholds.count ? achievementService.levelThresholds[currentLevelIndex] : achievementService.userTotalAchievementPoints
        let pointsInCurrentLevel = achievementService.userTotalAchievementPoints - currentLevelThreshold

        let nextLevelThresholdIndex = currentLevelIndex + 1
        guard nextLevelThresholdIndex < achievementService.levelThresholds.count else { return 1.0 }

        let pointsForNextLevelSpan = achievementService.levelThresholds[nextLevelThresholdIndex] - currentLevelThreshold

        if pointsForNextLevelSpan <= 0 { return 1.0 }
        return min(max(0.0, Double(pointsInCurrentLevel) / Double(pointsForNextLevelSpan)), 1.0)
    }

    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            ScrollView {
                VStack(spacing: 18) {
                    profileHeader()
                    userLevelAndPointsSection()
                    weeklyChallengesSection()

                    dailyStats()
                    achievementsSection(
                        definitions: achievementService.achievementDefinitions,
                        statuses: achievementService.userStatuses,
                        isLoading: achievementService.isLoading
                    )
                }
                .padding()
            }
        }
        .onAppear {
             if let userID = Auth.auth().currentUser?.uid {
                  goalSettings.loadUserGoals(userID: userID)
                  achievementService.fetchUserStatuses(userID: userID)
                  achievementService.listenToUserProfile(userID: userID)
             }
        }
        .alert(item: $errorMessage) { message in
            Alert(title: Text("Error"), message: Text(message.text), dismissButton: .default(Text("OK")))
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingChallenges) {
            ChallengesView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    func profileHeader() -> some View {
         HStack(alignment: .top, spacing: 14) {
              Image(systemName: "person.crop.circle.fill")
                 .font(.system(size: 58, weight: .regular))
                 .foregroundColor(.brandPrimary)
                 .frame(width: 72, height: 72)
                 .background(Color.brandPrimary.opacity(0.10), in: Circle())

              VStack(alignment: .leading, spacing: 5) {
                  Text(goalSettings.gender == "Male" ? "Fitness Journey" : "Wellness Path")
                      .appFont(size: 24, weight: .bold)
                      .foregroundColor(.textPrimary)

                  Text(Auth.auth().currentUser?.email ?? "MyFitPlate User")
                      .foregroundColor(Color(UIColor.secondaryLabel))
                      .appFont(size: 13)
                      .lineLimit(1)

                  Text(userLevelDisplay)
                      .appFont(size: 12, weight: .bold)
                      .foregroundColor(.white)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 6)
                      .background(Color.brandPrimary, in: Capsule())
                      .shadow(color: .brandPrimary.opacity(0.4), radius: 4, x: 0, y: 2)
              }

             Spacer()
          }
         .padding(20)
         .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    func userLevelAndPointsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Level Progress")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("\(achievementService.userTotalAchievementPoints) total achievement points")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                Text(userLevelDisplay)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
            }

            ProgressView(value: progressToNextLevel, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .brandPrimary))
                .scaleEffect(x:1, y:1.5, anchor: .center)

            HStack {
                Text("\(achievementService.userTotalAchievementPoints) pts")
                    .appFont(size: 12)
                Spacer()
                if achievementService.userAchievementLevel <= achievementService.levelThresholds.count && pointsToNextLevel > 0 {
                    Text("\(pointsToNextLevel) pts to next level")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                } else if !achievementService.levelThresholds.isEmpty && achievementService.userAchievementLevel > achievementService.levelThresholds.count - 1  {
                     Text("Max Level!")
                        .appFont(size: 12)
                        .foregroundColor(.accentPositive)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    func weeklyChallengesSection() -> some View {
        Button(action: { showingChallenges = true }) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly Challenges")
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("Keep momentum with focused goals.")
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                if !achievementService.activeChallenges.isEmpty {
                    Text("\(achievementService.activeChallenges.filter { $0.isCompleted }.count)/\(achievementService.activeChallenges.count)")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(.brandPrimary)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func dailyStats() -> some View {
         LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
              statBox(title: calorieGoalText(), subtitle: "Calorie Goal", icon: "flame.fill", color: .orange)
              statBox(title: calculateBMI(), subtitle: "BMI", icon: "scalemass.fill", color: .blue)
          }
    }
    func calorieGoalText() -> String { goalSettings.calories == nil ? "..." : "\(Int(goalSettings.calories ?? 0))" }
    func calculateBMI() -> String { let w = goalSettings.weight * 0.453592; let h = goalSettings.height / 100; guard h > 0 else { return "N/A" }; let bmi = w / (h * h); return String(format: "%.1f", bmi) }
    func statBox(title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.12), in: Circle())
            Text(title)
                .appFont(size: 28, weight: .bold)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    func achievementsSection(definitions: [AchievementDefinition], statuses: [String: UserAchievementStatus], isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Achievements")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text("\(achievementService.unlockedAchievementsCount) of \(definitions.count) unlocked")
                    .appFont(size: 13)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            if isLoading {
                HStack { Spacer(); ProgressView().tint(.brandPrimary); Spacer() }
                    .padding(.vertical, 24)
                    .asCard()
            }
            else if definitions.isEmpty {
                Text("No achievements defined yet.")
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .appFont(size: 15)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            else {
                 let sortedDefinitions = definitions.sorted { d1, d2 in
                    let s1 = statuses[d1.id]
                    let s2 = statuses[d2.id]
                    let u1 = s1?.isUnlocked ?? false
                    let u2 = s2?.isUnlocked ?? false
                    if u1 != u2 { return u1 }
                    if u1 {
                        return (s1?.unlockedDate ?? Date.distantPast) > (s2?.unlockedDate ?? Date.distantPast)
                    }
                    let p1 = s1?.currentProgress ?? 0.0
                    let p2 = s2?.currentProgress ?? 0.0
                    if p1 != p2 { return p1 > p2 }
                    if d1.pointsValue != d2.pointsValue {
                        return d1.pointsValue > d2.pointsValue
                    }
                    return d1.title < d2.title
                }
                 LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 15) {
                     ForEach(sortedDefinitions) { definition in
                        AchievementCardView(
                            definition: definition,
                            status: statuses[definition.id]
                        )
                    }
                 }
            }
        }
        .padding(.top)
    }
}

struct AchievementCardView: View {
    let definition: AchievementDefinition
    let status: UserAchievementStatus?
    var isUnlocked: Bool { status?.isUnlocked ?? false }
    var progress: Double { status?.currentProgress ?? 0.0 }
    var progressFraction: Double { guard definition.criteriaValue > 0 else { return isUnlocked ? 1.0 : 0.0 }; return min(max(0, progress / definition.criteriaValue), 1.0) }
    var progressText: String { if definition.criteriaValue <= 1 && isUnlocked { return "Complete!" } else if definition.criteriaValue <= 1 { return "Not Yet"} else { return "\(Int(progress.rounded())) / \(Int(definition.criteriaValue.rounded()))" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isUnlocked ? definition.iconName : "lock.fill")
                    .font(.title2)
                    .foregroundColor(isUnlocked ? .white : Color(UIColor.secondaryLabel))
                    .frame(width: 38, height: 38)
                    .background((isUnlocked ? Color.brandPrimary : Color(UIColor.secondaryLabel)).opacity(0.8), in: Circle())
                    .shadow(color: isUnlocked ? .brandPrimary.opacity(0.5) : .clear, radius: 4, x: 0, y: 2)
                    
                Text(definition.title)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(isUnlocked ? .textPrimary : Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                Spacer()
                Text("\(definition.pointsValue) pts")
                    .appFont(size: 10, weight: .bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background((isUnlocked ? Color.brandPrimary.opacity(0.2) : Color(UIColor.secondaryLabel).opacity(0.2)))
                    .cornerRadius(5)
                    .foregroundColor(isUnlocked ? .brandPrimary : Color(UIColor.secondaryLabel))
            }
            
            Text(definition.description)
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(minHeight: 35 ,alignment: .top)
                .fixedSize(horizontal: false, vertical: true)

            if !isUnlocked && definition.criteriaValue > 0 && definition.criteriaType != .featureUsed {
                VStack(spacing: 4) {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(LinearProgressViewStyle(tint: .brandPrimary))
                        .frame(height: 6)
                    
                    if definition.criteriaValue > 1 || (definition.criteriaValue == 1 && progress > 0 && progress < 1 && definition.criteriaType != .featureUsed) {
                        Text(progressText)
                            .appFont(size: 11, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(.top, 6)
             } else if isUnlocked {
                 HStack {
                     Image(systemName: "checkmark.seal.fill")
                     Text("Unlocked")
                     if let date = status?.unlockedDate {
                         Text(date, style: .date)
                     }

                     Spacer()

                     ShareLink(
                        item: "I just unlocked the '\(definition.title)' achievement on MyFitPlate! 🏆",
                        subject: Text("Achievement Unlocked!"),
                        message: Text("I just unlocked the '\(definition.title)' achievement on MyFitPlate! 🏆")
                     ) {
                         Image(systemName: "square.and.arrow.up")
                             .foregroundColor(.brandPrimary)
                             .font(.system(size: 16, weight: .bold))
                             .padding(8)
                             .background(Color.brandPrimary.opacity(0.15))
                             .clipShape(Circle())
                     }
                 }
                 .appFont(size: 12, weight: .bold)
                 .foregroundColor(.brandPrimary)
                 .padding(.top, 8)
            } else {
                 Spacer().frame(height: 12)
            }
             Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 130)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isUnlocked ? Color.brandPrimary.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .opacity(isUnlocked ? 1.0 : (definition.secret && !isUnlocked ? 0.35 : 0.8))
        .overlay(
            Group {
                if definition.secret && !isUnlocked {
                    VStack{
                        Spacer()
                        HStack{
                            Spacer()
                            Image(systemName: "questionmark.diamond.fill")
                                .font(.system(size: 50))
                                .foregroundColor(Color(UIColor.secondaryLabel).opacity(0.2))
                                .padding()
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        )
    }
}

struct ErrorMessage: Identifiable { let id = UUID(); let text: String; init(_ text: String) { self.text = text } }
