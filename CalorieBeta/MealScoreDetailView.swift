import SwiftUI

struct MealScoreDetailView: View {
    let score: MealScore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    aiSummary
                    VStack(spacing: 20) {
                        macroSection
                        qualitySection
                    }
                    improvementSection
                }
                .padding()
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Daily Debrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack {
            Text(score.grade)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(score.color)
            
            Text(score.summary)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var aiSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text("Maia's Analysis")
                    .font(.headline)
            }
            Text(score.personalizedAISummary)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
    
    private var macroSection: some View {
        VStack(alignment: .leading) {
            Text("Macros & Calories")
                .font(.title2).bold().padding(.bottom, 5)

            Gauge(value: score.actualCalories, in: 0...score.goalCalories*1.5) {
                Text("Calories")
            } currentValueLabel: {
                Text("\(Int(score.actualCalories))")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("\(Int(score.goalCalories))")
            }
            .tint(Gradient(colors: [.green, .yellow, .red]))

            HStack(spacing: 15) {
                MacroCircleView(label: "Protein", value: score.actualProtein, goal: score.goalProtein, color: .accentProtein)
                MacroCircleView(label: "Carbs", value: score.actualCarbs, goal: score.goalCarbs, color: .accentCarbs)
                MacroCircleView(label: "Fats", value: score.actualFats, goal: score.goalFats, color: .accentFats)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
    
    private var qualitySection: some View {
        VStack(alignment: .leading) {
            Text("Food Quality")
                .font(.title2).bold().padding(.bottom, 10)
            
            VStack(spacing: 15) {
                Gauge(value: score.actualFiber, in: 0...score.goalFiber) {
                    Text("Fiber")
                } currentValueLabel: {
                    Text("\(score.actualFiber, specifier: "%.1f")g")
                } minimumValueLabel: {
                    Text("0g")
                } maximumValueLabel: {
                    Text("\(Int(score.goalFiber))g")
                }
                .tint(.orange)
                
                Gauge(value: score.actualSaturatedFat, in: 0...score.goalSaturatedFat*1.5) {
                    Text("Saturated Fat")
                } currentValueLabel: {
                    Text("\(score.actualSaturatedFat, specifier: "%.1f")g")
                } minimumValueLabel: {
                    Text("0g")
                } maximumValueLabel: {
                    Text("< \(Int(score.goalSaturatedFat))g")
                }
                .tint(score.actualSaturatedFat > score.goalSaturatedFat ? .red : .purple)

                Gauge(value: score.actualSodium, in: 0...score.goalSodium*1.5) {
                    Text("Sodium")
                } currentValueLabel: {
                    Text("\(Int(score.actualSodium))mg")
                } minimumValueLabel: {
                    Text("0mg")
                } maximumValueLabel: {
                    Text("< \(Int(score.goalSodium))mg")
                }
                .tint(score.actualSodium > score.goalSodium ? .red : .blue)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
    
    private var improvementSection: some View {
        VStack(alignment: .leading) {
            Text("What to Improve")
                .font(.title2).bold()

            ForEach(score.improvementTips) { tip in
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: tip.icon)
                        .font(.title)
                        .foregroundColor(tip.color)
                        .frame(width: 35)
                    
                    VStack(alignment: .leading) {
                        Text(tip.category)
                            .font(.headline)
                        Text(tip.advice)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
}

struct MacroCircleView: View {
    let label: String
    let value: Double
    let goal: Double
    let color: Color
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(value / goal, 1.5)
    }

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(lineWidth: 8)
                    .opacity(0.3)
                    .foregroundColor(color)
                
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .foregroundColor(color)
                    .rotationEffect(Angle(degrees: 270))
                
                Text("\(Int(value))g")
                    .font(.caption)
                    .bold()
            }
            .frame(width: 70, height: 70)
            
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
