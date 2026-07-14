import MyFitPlateCore

import SwiftUI

struct WellnessScoreCardView: View {
    let wellnessScore: WellnessScore
    let mealScore: MealScore?
    let sleepReport: EnhancedSleepReport?
    
    @State private var showDetail: Bool
    @State private var animatedScore: Double = 0

    init(
        wellnessScore: WellnessScore,
        mealScore: MealScore?,
        sleepReport: EnhancedSleepReport?,
        initiallyShowsDetail: Bool = false
    ) {
        self.wellnessScore = wellnessScore
        self.mealScore = mealScore
        self.sleepReport = sleepReport
        _showDetail = State(initialValue: initiallyShowsDetail)
    }

    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(
                    title: wellnessScore.displayTitle,
                    subtitle: wellnessScore.scopeDescription
                ) {
                    ZStack {
                        Circle()
                            .stroke(wellnessScore.color.opacity(0.16), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(animatedScore / 100, 0), 1)))
                            .stroke(wellnessScore.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 0) {
                            Text("\(wellnessScore.overallScore)")
                                .appTextRole(.sectionTitle)
                                .foregroundStyle(AppPalette.text)
                            Text("score")
                                .appTextRole(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 78, height: 78)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Score \(wellnessScore.overallScore) out of 100")
                }

                Text(wellnessScore.summary)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Nutrition",
                        value: wellnessScore.nutritionScore.formatted(),
                        accent: AppPalette.brand
                    ),
                    AppMetricItem(
                        label: "Sleep",
                        value: wellnessScore.sleepScore.map(String.init) ?? "--",
                        accent: .blue
                    ),
                    AppMetricItem(
                        label: "Recovery",
                        value: wellnessScore.recoveryScore.map(String.init) ?? "--",
                        accent: .purple
                    )
                ])
            }
            .appSurface(.quiet)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wellness_score_card")
        .sheet(isPresented: $showDetail) {
            WellnessScoreDetailView(
                wellnessScore: wellnessScore,
                mealScore: mealScore,
                sleepReport: sleepReport
            )
        }
        .onAppear {
            withAnimation(AppMotion.standard.delay(0.2)) {
                animatedScore = Double(wellnessScore.overallScore)
            }
        }
        .onChange(of: wellnessScore.overallScore) { _, newValue in
            withAnimation(AppMotion.standard) {
                animatedScore = Double(newValue)
            }
        }
    }
}
