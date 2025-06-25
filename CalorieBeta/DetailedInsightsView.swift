import SwiftUI

struct DetailedInsightsView: View {
    @ObservedObject var insightsService: InsightsService
    @Environment(\.colorScheme) var colorScheme
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
                    Text("No specific insights to show for this period based on your logs. Keep logging consistently for more personalized feedback!")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    Text("Your Weekly Insights")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)

                    ForEach(insightsService.currentInsights) { insight in
                        InsightDetailCard(insight: insight)
                    }
                }
                
                Spacer()
                
                Text("Insights are generated based on your logged data and general health guidelines. They are not a substitute for professional medical advice. Always consult a healthcare provider for personalized guidance.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
            .padding()
        }
        .navigationTitle("Weekly Insights Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportToPDF) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: iconForCategory(insight.category))
                    .font(.title2)
                    .foregroundColor(colorForCategory(insight.category))
                    .frame(width: 30, alignment: .top)
                
                VStack(alignment: .leading) {
                    Text(insight.title)
                        .font(.headline)
                    if let relatedData = insight.relatedData {
                        ForEach(relatedData.keys.sorted(), id: \.self) { key in
                            if key != "sourceName" && key != "sourceURL" {
                                HStack {
                                    Text("\(key.capitalized):")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(relatedData[key] ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            
            Text(insight.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 5)
            
            if let sourceName = insight.relatedData?["sourceName"],
               let sourceURLString = insight.relatedData?["sourceURL"],
               let url = URL(string: sourceURLString) {
                
                Divider().padding(.vertical, 4)
                Link(destination: url) {
                    HStack {
                        Text("Source: \(sourceName)")
                            .font(.caption)
                        Image(systemName: "link.circle.fill")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func iconForCategory(_ category: UserInsight.InsightCategory) -> String {
        switch category {
        case .sleep: return "bed.double.fill"
        case .hydration: return "drop.fill"
        case .microNutrient, .fiberIntake, .saturatedFat: return "leaf.fill"
        case .macroBalance: return "chart.pie.fill"
        case .nutritionGeneral: return "figure.mind.and.body"
        case .consistency, .mealTiming: return "checkmark.seal.fill"
        case .postWorkout: return "figure.walk"
        case .foodVariety: return "fork.knife"
        case .positiveReinforcement: return "star.fill"
        case .sugarAwareness: return "bubbles.and.sparkles"
        default: return "lightbulb.fill"
        }
    }

    private func colorForCategory(_ category: UserInsight.InsightCategory) -> Color {
        switch category {
        case .sleep: return .indigo
        case .hydration: return .blue
        case .microNutrient, .fiberIntake: return .green
        case .saturatedFat: return .pink
        case .macroBalance: return .orange
        case .nutritionGeneral: return .purple
        case .consistency, .mealTiming: return .teal
        case .postWorkout: return .cyan
        case .foodVariety: return .brown
        case .positiveReinforcement: return .yellow
        case .sugarAwareness: return .red
        default: return .gray
        }
    }
}
