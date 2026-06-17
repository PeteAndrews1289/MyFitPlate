import SwiftUI
import Charts

struct ExerciseTrendChartView: View {
    let exerciseName: String
    let dataPoints: [ExerciseTrendPoint]
    let metric: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(exerciseName).font(.headline).foregroundColor(.primary)
                    Text("Progressive Overload (\(metric))").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                
                if let first = dataPoints.first, let last = dataPoints.last, dataPoints.count > 1 {
                    let diff = last.value - first.value
                    let isPositive = diff >= 0
                    Text("\(isPositive ? "+" : "")\(Int(diff))").font(.subheadline).fontWeight(.bold).foregroundColor(isPositive ? .accentPositive : .red).padding(.horizontal, 8).padding(.vertical, 4).background(isPositive ? Color.accentPositive.opacity(0.1) : Color.red.opacity(0.1)).cornerRadius(8)
                }
            }

            if dataPoints.count < 2 {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundColor(.secondary.opacity(0.5))
                        Text("Log more to see progress!").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                Chart(dataPoints) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric, point.value))
                        .interpolationMethod(.catmullRom).foregroundStyle(Color.brandPrimary)
                        .symbol { Circle().fill(Color.brandPrimary).frame(width: 8, height: 8) }
                    AreaMark(x: .value("Date", point.date), y: .value(metric, point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [Color.brandPrimary.opacity(0.3), Color.brandPrimary.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                }
                .frame(height: 180)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { value in if let _ = value.as(Date.self) { AxisValueLabel(format: .dateTime.day().month()) } } }
            }
        }
        .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(16)
    }
}
