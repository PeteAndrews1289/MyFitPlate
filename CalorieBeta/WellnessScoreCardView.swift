import SwiftUI

struct WellnessScoreCardView: View {
    let wellnessScore: WellnessScore
    let mealScore: MealScore?
    let sleepReport: EnhancedSleepReport?
    
    @State private var showDetail = false
    @State private var animatedScore: Double = 0

    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Wellness Score")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(wellnessScore.summary)
                        .appFont(size: 22, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Nutrition, sleep, and recovery in one read.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(wellnessScore.color.opacity(0.16), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(animatedScore / 100, 0), 1)))
                        .stroke(wellnessScore.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(wellnessScore.overallScore)")
                            .appFont(size: 24, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Text("score")
                            .appFont(size: 10, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
                .frame(width: 86, height: 86)
            }
            
            HStack(spacing: 16) {
                ScoreComponentView(
                    icon: "fork.knife",
                    color: .accentColor,
                    title: "Nutrition",
                    score: wellnessScore.nutritionScore
                )
                ScoreComponentView(
                    icon: "bed.double.fill",
                    color: .blue,
                    title: "Sleep",
                    score: wellnessScore.sleepScore
                )
                ScoreComponentView(
                    icon: "waveform.path.ecg",
                    color: .purple,
                    title: "Recovery",
                    score: wellnessScore.recoveryScore
                )
            }
        }
        .glassCard()
        }
        .buttonStyle(AnimatedCardButtonStyle())
        .sheet(isPresented: $showDetail) {
            WellnessScoreDetailView(
                wellnessScore: wellnessScore,
                mealScore: mealScore,
                sleepReport: sleepReport
            )
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 15).delay(0.2)) {
                animatedScore = Double(wellnessScore.overallScore)
            }
        }
        .onChange(of: wellnessScore.overallScore) { _, newValue in
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 15)) {
                animatedScore = Double(newValue)
            }
        }
    }
}

struct ScoreComponentView: View {
    let icon: String
    let color: Color
    let title: String
    let score: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.18), in: Circle())
            
            VStack(alignment: .leading) {
                Text(score.map { "\($0)" } ?? "--")
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)
                Text(title)
                    .appFont(size: 11, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}
