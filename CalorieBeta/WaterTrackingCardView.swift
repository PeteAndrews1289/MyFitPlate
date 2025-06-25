import SwiftUI
import FirebaseAuth

struct WaterTrackingCardView: View {
    @EnvironmentObject var dailyLogService : DailyLogService
    @EnvironmentObject var goalSettings: GoalSettings
    
    var date: Date
    var insight: UserInsight?
    
    @State private var motivationalQuote: (text: String, author: String) = ("", "")
    private let waterIncrement: Double = 8.0
    
    private static let quotes = [
        ("The only way to do great work is to love what you do.", "Steve Jobs"),
        ("Strive for progress, not perfection.", "Unknown"),
        ("The journey of a thousand miles begins with a single step.", "Lao Tzu"),
        ("Believe you can and you're halfway there.", "Theodore Roosevelt"),
        ("Your body can stand almost anything. It’s your mind that you have to convince.", "Unknown"),
        ("The best way to predict the future is to create it.", "Peter Drucker"),
        ("Success is not final, failure is not fatal: It is the courage to continue that counts.", "Winston Churchill"),
        ("Don't watch the clock; do what it does. Keep going.", "Sam Levenson"),
        ("The pain you feel today will be the strength you feel tomorrow.", "Unknown"),
        ("Take care of your body. It’s the only place you have to live.", "Jim Rohn"),
        ("Strength does not come from physical capacity. It comes from an indomitable will.", "Mahatma Gandhi"),
        ("The secret of getting ahead is getting started.", "Mark Twain"),
        ("Well done is better than well said.", "Benjamin Franklin"),
        ("A year from now you may wish you had started today.", "Karen Lamb")
    ]
    
    private var waterIntake: Double {
        dailyLogService.currentDailyLog?.waterTracker?.totalOunces ?? 0.0
    }
    private var waterGoal: Double {
        max(1, goalSettings.waterGoal)
    }
    
    var body: some View {
        let progress = max(0, min(1, waterIntake / waterGoal))
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    if let insight = insight {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text(insight.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.accentColor)
                            }
                            Text(insight.message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(8)
                        }
                        .padding(.bottom, 8)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(motivationalQuote.text)
                            .font(.caption)
                            .italic()
                            .lineLimit(3)
                        Text("- \(motivationalQuote.author)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .center, spacing: 5) {
                    Text("Water Intake")
                        .font(.headline)
                    
                    Text("\(Int(waterIntake)) / \(Int(waterGoal)) oz")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.bottom, 2)

                    GeometryReader { geometry in
                        ZStack(alignment: .bottom){
                            Rectangle()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [.cyan, .blue.opacity(0.7)]),
                                    startPoint: .bottom, endPoint: .top ))
                                .frame(height: geometry.size.height * CGFloat(progress))
                                .animation(.easeInOut(duration: 0.5), value: progress)
                            
                            WaterBottleShape()
                                .stroke(Color.secondary, lineWidth: 1.5)
                        }
                        .mask(WaterBottleShape())
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .frame(width: 50, height: 80)
                    .padding(.bottom, 5)
                    
                    HStack(spacing: 15) {
                        Button {
                            adjustWater(by: -waterIncrement)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .disabled(waterIntake < waterIncrement && waterIntake != 0)
                        
                        Text("\(Int(waterIncrement)) oz")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Button {
                            adjustWater(by: waterIncrement)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .frame(width: 110, alignment: .top)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            .padding(.bottom, 5)
        }
        .onAppear {
            selectRandomQuote()
        }
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
    
    private func selectRandomQuote() {
        if let random = Self.quotes.randomElement() {
            self.motivationalQuote = random
        }
    }
}
