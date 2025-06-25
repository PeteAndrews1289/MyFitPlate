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
              Image(systemName: "person.crop.circle").resizable().frame(width: 80, height: 80).foregroundColor(.gray)
              Text(goalSettings.gender == "Male" ? "Fitness Journey" : "Wellness Path")
                  .font(.title2).fontWeight(.bold)
              Text(Auth.auth().currentUser?.email ?? "MyFitPlate User")
                  .foregroundColor(.gray).font(.caption)
          }
    }

    func userLevelAndPointsSection() -> some View {
        VStack(spacing: 5) {
            Text(userLevelDisplay)
                .font(.title3.bold())
                .foregroundColor(.accentColor)
            ProgressView(value: progressToNextLevel, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .scaleEffect(x:1, y:1.5, anchor: .center)
            
            HStack {
                Text("\(achievementService.userTotalAchievementPoints) pts")
                    .font(.caption)
                Spacer()
                if achievementService.userAchievementLevel <= achievementService.levelThresholds.count && pointsToNextLevel > 0 {
                    Text("\(pointsToNextLevel) pts to next level")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else if !achievementService.levelThresholds.isEmpty && achievementService.userAchievementLevel > achievementService.levelThresholds.count - 1  {
                     Text("Max Level!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    func weeklyChallengesSection() -> some View {
        Button(action: { showingChallenges = true }) {
            HStack {
                Image(systemName: "flame.fill")
                Text("Weekly Challenges")
                    .font(.headline)
                Spacer()
                if !achievementService.activeChallenges.isEmpty {
                    Text("\(achievementService.activeChallenges.filter { $0.isCompleted }.count)/\(achievementService.activeChallenges.count)")
                        .font(.body.weight(.semibold))
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .foregroundColor(.accentColor)
            .padding()
            .background(Color(.secondarySystemBackground))
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
    func statBox(title: String, subtitle: String) -> some View { VStack { Text(title).font(.title).fontWeight(.bold); Text(subtitle).font(.caption).foregroundColor(.gray) }.frame(maxWidth: .infinity) }

    func achievementsSection(definitions: [AchievementDefinition], statuses: [String: UserAchievementStatus], isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Achievements (\(achievementService.unlockedAchievementsCount)/\(definitions.count))")
                .font(.headline).padding(.bottom, 4)
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical) }
            else if definitions.isEmpty { Text("No achievements defined yet.").foregroundColor(.gray).font(.subheadline) }
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
    @Environment(\.colorScheme) var colorScheme
    var isUnlocked: Bool { status?.isUnlocked ?? false }
    var progress: Double { status?.currentProgress ?? 0.0 }
    var progressFraction: Double { guard definition.criteriaValue > 0 else { return isUnlocked ? 1.0 : 0.0 }; return min(max(0, progress / definition.criteriaValue), 1.0) }
    var progressText: String { if definition.criteriaValue <= 1 && isUnlocked { return "Complete!" } else if definition.criteriaValue <= 1 { return "Not Yet"} else { return "\(Int(progress.rounded())) / \(Int(definition.criteriaValue.rounded()))" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: definition.iconName).font(.title2).foregroundColor(isUnlocked ? .yellow : .gray).frame(width: 30)
                Text(definition.title).font(.headline).foregroundColor(isUnlocked ? .primary : .secondary).lineLimit(1)
                Spacer()
                Text("\(definition.pointsValue) pts")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background((isUnlocked ? Color.yellow.opacity(0.7) : Color.gray.opacity(0.3)).opacity(colorScheme == .dark ? 0.5 : 1))
                    .cornerRadius(5)
                    .foregroundColor(isUnlocked ? (colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7)) : .secondary)
            }
            Text(definition.description).font(.caption).foregroundColor(.secondary).frame(minHeight: 30 ,alignment: .top).fixedSize(horizontal: false, vertical: true)
            
            if !isUnlocked && definition.criteriaValue > 0 && definition.criteriaType != .featureUsed {
                VStack(spacing: 2) {
                    ProgressView(value: progressFraction)
                        .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                        .frame(height: 6)
                    if definition.criteriaValue > 1 || (definition.criteriaValue == 1 && progress > 0 && progress < 1 && definition.criteriaType != .featureUsed) {
                        Text(progressText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(.top, 4)
             } else if isUnlocked {
                 HStack {
                     Text("Unlocked!")
                     if let date = status?.unlockedDate { Text(date, style: .date) }
                 }
                 .font(.caption.bold())
                 .foregroundColor(.green)
                 .padding(.top, 4)
            } else {
                 Spacer().frame(height: 12)
            }
             Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 120)
        .background(colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
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
                                .foregroundColor(.gray.opacity(0.2))
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
