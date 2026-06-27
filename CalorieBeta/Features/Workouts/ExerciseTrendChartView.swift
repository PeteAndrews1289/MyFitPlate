import SwiftUI
import Charts

struct ExerciseTrendChartView: View {
    let exerciseName: String
    let dataPoints: [ExerciseTrendPoint]
    let metric: String

    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map { $0.value }
        guard let minV = values.min(), let maxV = values.max() else { return 0...1 }
        let pad = Swift.max(5, (maxV - minV) * 0.3)
        return Swift.max(0, minV - pad)...(maxV + pad)
    }

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
                .chartYScale(domain: yDomain)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.month().day())
                            }
                        }
                    }
                }
            }
        }
        .padding().background(Color(UIColor.secondarySystemBackground)).cornerRadius(16)
    }
}
