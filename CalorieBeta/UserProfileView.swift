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
        ScrollView {
            VStack(spacing: 20) {
                profileHeader()
                userLevelAndPointsSection()
                
                NavigationLink(destination: ChallengesView(), isActive: $showingChallenges) { EmptyView() }
                
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
        .background(Color.backgroundPrimary)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    func profileHeader() -> some View {
         VStack(spacing: 8) {
              Image(systemName: "person.crop.circle").resizable().frame(width: 80, height: 80).foregroundColor(Color(UIColor.secondaryLabel))
              Text(goalSettings.gender == "Male" ? "Fitness Journey" : "Wellness Path")
                  .appFont(size: 22, weight: .bold)
              Text(Auth.auth().currentUser?.email ?? "MyFitPlate User")
                  .foregroundColor(Color(UIColor.secondaryLabel)).appFont(size: 12)
          }
    }

    func userLevelAndPointsSection() -> some View {
        VStack(spacing: 5) {
            Text(userLevelDisplay)
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.brandPrimary)
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
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(10)
    }
    
    func weeklyChallengesSection() -> some View {
        Button(action: { showingChallenges = true }) {
            HStack {
                Image(systemName: "flame.fill")
                Text("Weekly Challenges")
                    .appFont(size: 17, weight: .semibold)
                Spacer()
                if !achievementService.activeChallenges.isEmpty {
                    Text("\(achievementService.activeChallenges.filter { $0.isCompleted }.count)/\(achievementService.activeChallenges.count)")
                        .appFont(size: 17, weight: .semibold)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
            .foregroundColor(.brandPrimary)
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(10)
        }
    }

    func dailyStats() -> some View {
         HStack(spacing: 16) {
              statBox(title: calorieGoalText(), subtitle: "Calorie Goal"); Divider().frame(height: 40); statBox(title: calculateBMI(), subtitle: "BMI")
          }.padding(.vertical)
    }
    func calorieGoalText() -> String { goalSettings.calories == nil ? "..." : "\(Int(goalSettings.calories ?? 0))" }
    func calculateBMI() -> String { let w = goalSettings.weight * 0.453592; let h = goalSettings.height / 100; guard h > 0 else { return "N/A" }; let bmi = w / (h * h); return String(format: "%.1f", bmi) }
    func statBox(title: String, subtitle: String) -> some View { VStack { Text(title).appFont(size: 28, weight: .bold); Text(subtitle).appFont(size: 12).foregroundColor(Color(UIColor.secondaryLabel)) }.frame(maxWidth: .infinity) }

    func achievementsSection(definitions: [AchievementDefinition], statuses: [String: UserAchievementStatus], isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements (\(achievementService.unlockedAchievementsCount)/\(definitions.count))")
                .appFont(size: 17, weight: .semibold).padding(.bottom, 4)
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical) }
            else if definitions.isEmpty { Text("No achievements defined yet.").foregroundColor(Color(UIColor.secondaryLabel)).appFont(size: 15) }
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
        }.padding(.top)
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
                Image(systemName: definition.iconName).font(.title2).foregroundColor(isUnlocked ? .yellow : Color(UIColor.secondaryLabel)).frame(width: 30)
                Text(definition.title).appFont(size: 15, weight: .semibold).foregroundColor(isUnlocked ? .textPrimary : Color(UIColor.secondaryLabel)).lineLimit(1)
                Spacer()
                Text("\(definition.pointsValue) pts")
                    .appFont(size: 10, weight: .bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background((isUnlocked ? Color.yellow.opacity(0.7) : Color(UIColor.secondaryLabel).opacity(0.3)))
                    .cornerRadius(5)
                    .foregroundColor(isUnlocked ? .black.opacity(0.7) : Color(UIColor.secondaryLabel))
            }
            Text(definition.description).appFont(size: 12).foregroundColor(Color(UIColor.secondaryLabel)).frame(minHeight: 30 ,alignment: .top).fixedSize(horizontal: false, vertical: true)
            
            if !isUnlocked && definition.criteriaValue > 0 && definition.criteriaType != .featureUsed {
                VStack(spacing: 2) {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(LinearProgressViewStyle(tint: .brandPrimary))
                        .frame(height: 6)
                    if definition.criteriaValue > 1 || (definition.criteriaValue == 1 && progress > 0 && progress < 1 && definition.criteriaType != .featureUsed) {
                        Text(progressText)
                            .appFont(size: 10)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(.top, 4)
             } else if isUnlocked {
                 HStack {
                     Text("Unlocked!")
                     if let date = status?.unlockedDate { Text(date, style: .date) }
                 }
                 .appFont(size: 12, weight: .bold)
                 .foregroundColor(.accentPositive)
                 .padding(.top, 4)
            } else {
                 Spacer().frame(height: 12)
            }
             Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 120)
        .background(Color.backgroundSecondary)
        .cornerRadius(10)
        .opacity(isUnlocked ? 1.0 : (definition.secret && !isUnlocked ? 0.35 : 0.7))
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
