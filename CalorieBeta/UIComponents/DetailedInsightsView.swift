import SwiftUI

struct DetailedInsightsView: View {
    @ObservedObject var insightsService: InsightsService
    @State private var showShareSheet = false
    @State private var pdfURL: URL?

    private var sortedInsights: [UserInsight] {
        insightsService.currentInsights.sorted { first, second in
            if first.priority == second.priority {
                return first.title < second.title
            }
            return first.priority > second.priority
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if insightsService.isLoadingInsights {
                    InsightsLoadingState()
                } else if insightsService.currentInsights.isEmpty {
                    InsightsEmptyState()
                } else {
                    InsightsHeroCard(insights: sortedInsights)
                    InsightCategoryStrip(insights: sortedInsights)

                    ForEach(sortedInsights) { insight in
                        InsightDetailCard(insight: insight)
                    }
                }

                InsightDisclaimerCard()
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Maia Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportToPDF) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(insightsService.currentInsights.isEmpty || insightsService.isLoadingInsights)
            }
        }
        .tint(.brandPrimary)
        .sheet(isPresented: $showShareSheet) {
            if let pdfURL = pdfURL {
                PDFShareView(activityItems: [pdfURL])
            }
        }
    }

    @MainActor
    private func exportToPDF() {
        let insightsToExport = insightsService.currentInsights
        guard !insightsToExport.isEmpty else { return }

        let renderer = ImageRenderer(content: InsightsPDFLayout(insights: insightsToExport))
        
        let url = URL.documentsDirectory.appending(path: "MyFitPlate_Insights.pdf")
        
        renderer.render { _, context in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
                return
            }
            
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            
            self.pdfURL = url
            self.showShareSheet = true
        }
    }
}

private struct InsightsHeroCard: View {
    let insights: [UserInsight]

    private var topInsight: UserInsight? {
        insights.first
    }

    private var categoryCount: Int {
        Set(insights.map(\.category)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image("maia_avatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .background(Color.backgroundSecondary, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Maia's Read")
                        .appFont(size: 26, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("A weekly pattern check across nutrition, training, hydration, and recovery.")
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if let topInsight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Highest priority")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .textCase(.uppercase)

                    Text(topInsight.title)
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(topInsight.message)
                        .appFont(size: 13)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.brandPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 10) {
                InsightHeroMetric(title: "Insights", value: "\(insights.count)", color: .brandPrimary)
                InsightHeroMetric(title: "Categories", value: "\(categoryCount)", color: .blue)
                InsightHeroMetric(title: "Focus", value: topInsight?.category.displayName ?? "Ready", color: .accentPositive)
            }
        }
        .asCard()
    }
}

private struct InsightHeroMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 16, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .appFont(size: 10, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InsightCategoryStrip: View {
    let insights: [UserInsight]

    private var categories: [(category: UserInsight.InsightCategory, count: Int)] {
        Dictionary(grouping: insights, by: \.category)
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.displayName < rhs.0.displayName
                }
                return lhs.1 > rhs.1
            }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.category) { item in
                    InsightCategoryPill(category: item.category, count: item.count)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct InsightCategoryPill: View {
    let category: UserInsight.InsightCategory
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: category.iconName)
                .appFont(size: 11, weight: .bold)

            Text(category.displayName)
                .appFont(size: 12, weight: .bold)

            Text("\(count)")
                .appFont(size: 10, weight: .bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.22), in: Capsule())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(category.tintColor, in: Capsule())
    }
}

private struct InsightsLoadingState: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Maia is reading the week")
                .appFont(size: 19, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Nutrition, workouts, hydration, sleep, and journal notes are being checked for useful patterns.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 18)
        .asCard()
    }
}

private struct InsightsEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.text.clipboard")
                .appFont(size: 30, weight: .semibold)
                .foregroundColor(.brandPrimary)
                .frame(width: 62, height: 62)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            Text("Not enough signal yet")
                .appFont(size: 20, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("A few logged meals, water entries, and workouts give Maia enough context to produce a better weekly read.")
                .appFont(size: 13)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 18)
        .asCard()
    }
}

private struct InsightDisclaimerCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .appFont(size: 15, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.top, 1)

            Text("Insights are generated from logged data and general health guidelines. They are not medical advice.")
                .appFont(size: 12)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct InsightsPDFLayout: View {
    let insights: [UserInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("MyFitPlate: Weekly Insights")
                .font(.largeTitle.bold())
            Text("Report generated on: \(Date().formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            ForEach(insights) { insight in
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.title)
                        .font(.title2.bold())
                    Text(insight.message)
                        .font(.body)
                }
                .padding(.bottom)
            }
        }
        .padding(40)
        .frame(width: 612)
    }
}

struct InsightDetailCard: View {
    let insight: UserInsight
    @State private var showSourceData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.category.iconName)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(insight.category.tintColor)
                    .frame(width: 40, height: 40)
                    .background(insight.category.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(insight.category.displayName)
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(insight.category.tintColor)
                        .textCase(.uppercase)

                    Text(insight.title)
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if insight.priority > 0 {
                    Text("\(insight.priority)")
                        .appFont(size: 11, weight: .bold)
                        .foregroundColor(.brandPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.brandPrimary.opacity(0.10), in: Capsule())
                }
            }
            
            Text(insight.message)
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let sourceData = insight.sourceData, !sourceData.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSourceData.toggle()
                    }
                }) {
                    Label(showSourceData ? "Hide source data" : "Show source data", systemImage: showSourceData ? "chevron.up" : "chevron.down")
                        .appFont(size: 12, weight: .bold)
                        .foregroundColor(.brandPrimary)
                }
                .buttonStyle(.plain)

                if showSourceData {
                    Text(sourceData)
                        .appFont(size: 12)
                        .foregroundColor(.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .asCard()
    }
}

private extension UserInsight.InsightCategory {
    var displayName: String {
        switch self {
        case .nutritionGeneral: return "Nutrition"
        case .hydration: return "Hydration"
        case .macroBalance: return "Macros"
        case .microNutrient: return "Micros"
        case .mealTiming: return "Meal Timing"
        case .consistency: return "Consistency"
        case .postWorkout: return "Post Workout"
        case .foodVariety: return "Variety"
        case .positiveReinforcement: return "Win"
        case .sugarAwareness: return "Sugar"
        case .fiberIntake: return "Fiber"
        case .saturatedFat: return "Fats"
        case .smartSuggestion: return "Suggestion"
        case .sleep: return "Sleep"
        case .calorieFluctuation: return "Calories"
        case .weekendTrends: return "Weekend"
        case .exerciseSynergy: return "Training"
        }
    }

    var iconName: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .hydration: return "drop.fill"
        case .microNutrient, .fiberIntake, .saturatedFat: return "leaf.fill"
        case .macroBalance: return "chart.pie.fill"
        case .nutritionGeneral, .foodVariety: return "fork.knife"
        case .consistency, .mealTiming, .weekendTrends: return "calendar.badge.clock"
        case .postWorkout, .exerciseSynergy: return "flame.fill"
        case .positiveReinforcement: return "star.fill"
        case .sugarAwareness: return "bubbles.and.sparkles"
        default: return "lightbulb.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .sleep: return .indigo
        case .hydration: return .blue
        case .microNutrient, .fiberIntake, .foodVariety: return .accentPositive
        case .saturatedFat: return .pink
        case .macroBalance: return .accentCarbs
        case .nutritionGeneral: return .purple
        case .consistency, .mealTiming, .weekendTrends: return .teal
        case .postWorkout, .exerciseSynergy: return .orange
        case .positiveReinforcement: return .yellow
        case .sugarAwareness: return .red
        default: return .gray
        }
    }
}
