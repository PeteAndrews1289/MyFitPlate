import SwiftUI
import Charts
import HealthKit

struct WeeklySleepReport {
    let averageTimeInBed: String
    let averageTimeAsleep: String
    let sleepConsistency: String
    let dailySleep: [DailySleep]
    
    struct DailySleep: Identifiable {
        let id = UUID()
        let date: Date
        let timeAsleep: TimeInterval
        var weekday: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
    }
}

struct SleepReportCard: View {
    let report: WeeklySleepReport
    @Environment(\.colorScheme) var colorScheme

    private var cardBackground: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Sleep Analysis")
                .font(.headline)
                .padding([.top, .leading, .trailing])
            
            HStack(spacing: 16) {
                sleepStatBox(value: report.averageTimeAsleep, label: "Avg. Asleep")
                sleepStatBox(value: report.averageTimeInBed, label: "Avg. In Bed")
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text("Bedtime Consistency")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text(report.sleepConsistency)
                    .font(.caption)
            }
            .padding(.horizontal)
            
            if !report.dailySleep.isEmpty {
                Chart(report.dailySleep) { dailyData in
                    BarMark(
                        x: .value("Day", dailyData.weekday),
                        y: .value("Hours", dailyData.timeAsleep / 3600)
                    )
                    // --- FIX: Changed color to use the app's accent color ---
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(hours, specifier: "%.0f")h")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) {
                        AxisValueLabel()
                    }
                }
                .frame(height: 150)
                .padding()
            } else {
                Text("Not enough sleep data for a weekly chart.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .padding(.bottom)
        .background(cardBackground)
        .cornerRadius(15)
        .shadow(radius: 1)
    }
    
    @ViewBuilder
    private func sleepStatBox(value: String, label: String) -> some View {
        VStack {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor) // Changed from .blue to accentColor
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
