import SwiftUI
import Charts
import HealthKit

struct SleepReportCard: View {
    let report: EnhancedSleepReport
    let lastNightScore: Int?
    @State private var showingDetailSheet = false

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalMinutes = Int(round(interval / 60.0))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        else { return "\(minutes)m" }
    }

    private let stageColumns: [GridItem] = [ GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8) ]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                 Text("Sleep Analysis")
                    .appFont(size: 17, weight: .semibold)
                 Text(lastNightScore != nil ? "(Last Night)" : "(Weekly Avg)") // Indicate which score is shown
                    .appFont(size: 12, weight: .regular)
                    .foregroundColor(.secondary)
                Spacer()
                Gauge(value: Double(lastNightScore ?? report.averageSleepScore), in: 0...100) {
                    Image(systemName: "moon.zzz.fill")
                } currentValueLabel: {
                    Text("\(lastNightScore ?? report.averageSleepScore)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(sleepScoreColor(lastNightScore ?? report.averageSleepScore))
                .frame(width: 50, height: 50)
            }
            .padding([.top, .horizontal])

            VStack(alignment: .leading, spacing: 8) {
                Text("Averages (\(report.dateRange))")
                     .appFont(size: 14, weight: .medium).foregroundColor(.secondary)
                 HStack(spacing: 16) {
                    sleepStatBox(value: formatDuration(report.averageTimeAsleep), label: "Time Asleep")
                    sleepStatBox(value: formatDuration(report.averageTimeInBed), label: "Time in Bed")
                    sleepStatBox(value: "\(report.sleepConsistencyScore)", label: "Consistency")
                 }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("Average Time in Stages")
                     .appFont(size: 14, weight: .medium).foregroundColor(.secondary)
                 LazyVGrid(columns: stageColumns, alignment: .leading, spacing: 8) {
                     stagePill(label: "Awake", value: report.averageTimeAwake, color: .gray)
                     stagePill(label: "REM", value: report.averageTimeInREM, color: .purple)
                     stagePill(label: "Core", value: report.averageTimeInCore, color: .blue)
                     stagePill(label: "Deep", value: report.averageTimeInDeep, color: .indigo)
                 }
            }
            .padding(.horizontal)

             VStack(alignment: .leading, spacing: 4) {
                 Text("Bedtime Consistency")
                     .appFont(size: 12, weight: .bold).foregroundColor(Color(UIColor.secondaryLabel))
                 Text(report.sleepConsistencyMessage).appFont(size: 12).lineLimit(2)
             }
             .padding(.horizontal)

            if !report.dailySleepData.isEmpty {
                Chart {
                    ForEach(report.dailySleepData) { dailyData in
                         BarMark(x: .value("Day", dailyData.weekday), y: .value("Deep", dailyData.timeDeep / 3600), stacking: .standard).foregroundStyle(by: .value("Stage", "Deep"))
                         BarMark(x: .value("Day", dailyData.weekday), y: .value("Core", dailyData.timeCore / 3600), stacking: .standard).foregroundStyle(by: .value("Stage", "Core"))
                         BarMark(x: .value("Day", dailyData.weekday), y: .value("REM", dailyData.timeREM / 3600), stacking: .standard).foregroundStyle(by: .value("Stage", "REM"))
                    }
                }
                .chartForegroundStyleScale(["Deep": Color.indigo.gradient, "Core": Color.blue.gradient, "REM": Color.purple.gradient, "Awake": Color.gray.gradient])
                 .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let h = value.as(Double.self){ Text("\(h, specifier: "%.0f")h")}}}}
                 .chartXAxis { AxisMarks(values: .automatic) { AxisValueLabel() }}
                 .chartLegend(.hidden)
                 .frame(height: 150)
                 .padding()
            } else {
                Text("Not enough sleep data for chart.").appFont(size: 12).foregroundColor(Color(UIColor.secondaryLabel)).frame(maxWidth: .infinity, minHeight: 150)
            }

             Text("Tap for weekly average score & details.").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.top, -10)

        }
        .padding(.bottom)
        .asCard()
        .contentShape(Rectangle())
        .onTapGesture { showingDetailSheet = true }
        .sheet(isPresented: $showingDetailSheet) {
             NavigationView {
                 SleepDetailView(report: report)
                     .navigationTitle("Weekly Sleep Details")
                     .navigationBarTitleDisplayMode(.inline)
                     .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingDetailSheet = false } } }
             }
        }
    }

    @ViewBuilder
    private func sleepStatBox(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).appFont(size: 18, weight: .semibold).foregroundColor(.brandPrimary)
            Text(label).appFont(size: 10).foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
    }

     @ViewBuilder
     private func stagePill(label: String, value: TimeInterval, color: Color) -> some View {
         VStack(alignment: .leading, spacing: 2) {
             Text(label).font(.caption).foregroundColor(.secondary)
             Text(formatDuration(value)).appFont(size: 14, weight: .medium)
         }
         .padding(.horizontal, 10).padding(.vertical, 5)
         .background(color.opacity(0.1)).foregroundColor(color)
         .cornerRadius(8).frame(maxWidth: .infinity, alignment: .leading)
     }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score { case 85...: return .green; case 70..<85: return .yellow; case 50..<70: return .orange; default: return .red }
    }
}

// Detail View defined within the same file for simplicity
struct SleepDetailView: View {
    let report: EnhancedSleepReport

    private func formatDuration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalMinutes = Int(round(interval / 60.0)); let hours = totalMinutes / 60; let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" } else { return "\(minutes)m" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack {
                    Text("\(report.averageSleepScore)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(sleepScoreColor(report.averageSleepScore))
                    Text("Weekly Average Score (\(report.dateRange))")
                        .font(.headline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }

                 detailRow(title: "Time Asleep", value: formatDuration(report.averageTimeAsleep))
                 detailRow(title: "Time in Bed", value: formatDuration(report.averageTimeInBed))
                 detailRow(title: "Consistency Score", value: "\(report.sleepConsistencyScore)", description: report.sleepConsistencyMessage)

                VStack(alignment: .leading, spacing: 8) {
                     Text("Average Time in Stages").font(.title2).bold()
                     stageDetailRow(label: "Awake", value: report.averageTimeAwake, color: .gray)
                     stageDetailRow(label: "REM", value: report.averageTimeInREM, color: .purple)
                     stageDetailRow(label: "Core", value: report.averageTimeInCore, color: .blue)
                     stageDetailRow(label: "Deep", value: report.averageTimeInDeep, color: .indigo)
                }
                .padding().background(Color.backgroundSecondary).cornerRadius(12)
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

     private func detailRow(title: String, value: String, description: String? = nil) -> some View {
         VStack(alignment: .leading, spacing: 8) {
             HStack { Text(title).font(.title3).bold(); Spacer(); Text(value).font(.title3).bold().foregroundColor(.secondary) }
             if let description = description { Text(description).font(.subheadline).foregroundColor(.secondary) }
         }
         .padding().background(Color.backgroundSecondary).cornerRadius(12)
     }

      @ViewBuilder
      private func stageDetailRow(label: String, value: TimeInterval, color: Color) -> some View {
          HStack { Circle().fill(color).frame(width: 10, height: 10); Text(label).font(.headline); Spacer(); Text(formatDuration(value)).foregroundColor(.secondary) }
      }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score { case 85...: return .green; case 70..<85: return .yellow; case 50..<70: return .orange; default: return .red }
    }
}
