import SwiftUI

struct DetailedInsightsView: View {
    @ObservedObject var insightsService: InsightsService
    @State private var showShareSheet = false
    @State private var pdfURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if insightsService.isLoadingInsights {
                    ProgressView("Loading Detailed Insights...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                } else if insightsService.currentInsights.isEmpty {
                    Text("No specific insights to show for this period based on your logs. Log consistently for a few more days to unlock your personalized weekly insights!")
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding()
                } else {
                    Text("Your Weekly Insights")
                        .appFont(size: 22, weight: .bold)
                        .padding(.bottom, 10)

                    ForEach(insightsService.currentInsights) { insight in
                        InsightDetailCard(insight: insight)
                    }
                }
                
                Spacer()
                
                Text("Insights are generated based on your logged data and general health guidelines. They are not a substitute for professional medical advice. Always consult a healthcare provider for personalized guidance.")
                    .appFont(size: 12)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
            .padding()
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("Weekly Insights Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportToPDF) {
                    Image(systemName: "square.and.arrow.up")
                }
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
        
        renderer.render { size, context in
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            
            guard var pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: iconForCategory(insight.category))
                    .font(.title2)
                    .foregroundColor(colorForCategory(insight.category))
                    .frame(width: 30, alignment: .top)
                
                VStack(alignment: .leading) {
                    Text(insight.title)
                        .appFont(size: 17, weight: .semibold)
                }
                Spacer()
            }
            
            Text(insight.message)
                .appFont(size: 15)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .padding(.top, 5)

            // NEW: "Show me why" button and data display
            if let sourceData = insight.sourceData, !sourceData.isEmpty {
                Button(action: {
                    withAnimation(.spring()) {
                        showSourceData.toggle()
                    }
                }) {
                    Text(showSourceData ? "Hide Data" : "Show me why...")
                        .appFont(size: 12, weight: .bold)
                        .tint(.brandPrimary)
                }
                .padding(.top, 5)

                if showSourceData {
                    Text(sourceData)
                        .appFont(size: 12)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.backgroundSecondary)
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .asCard()
    }

    private func iconForCategory(_ category: UserInsight.InsightCategory) -> String {
        switch category {
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

    private func colorForCategory(_ category: UserInsight.InsightCategory) -> Color {
        switch category {
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
