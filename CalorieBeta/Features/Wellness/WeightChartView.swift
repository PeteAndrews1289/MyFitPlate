import SwiftUI
import Charts

struct WeightChartView: View {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    var currentWeight: Double
    var onEntrySelected: ((_ entryId: String) -> Void)? = nil
    
    @State private var selectedDate: Date?

    var body: some View {
        let sortedHistory = weightHistory.sorted { $0.date < $1.date }
        let weightsInHistory = sortedHistory.map { $0.weight }
        let minWeight = weightsInHistory.min() ?? currentWeight
        let maxWeight = weightsInHistory.max() ?? currentWeight
        // Tight padding so the area hugs the data instead of leaving a huge empty slab below it.
        let padding = max(2.0, (maxWeight - minWeight) * 0.25)
        // Clamp the x-axis to the actual data so the line/area doesn't trail off past the last point.
        let firstDate = sortedHistory.first?.date ?? Date()
        let lastRaw = sortedHistory.last?.date ?? Date()
        let lastDate = lastRaw > firstDate ? lastRaw : (Calendar.current.date(byAdding: .day, value: 1, to: firstDate) ?? firstDate)

        Chart {
            ForEach(sortedHistory, id: \.id) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Weight", item.weight)
                )
                .foregroundStyle(LinearGradient(colors: [Color.brandPrimary, Color.teal], startPoint: .leading, endPoint: .trailing))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 3))

                PointMark(
                    x: .value("Date", item.date),
                    y: .value("Weight", item.weight)
                )
                .foregroundStyle(Color.brandPrimary)
                
                AreaMark(
                    x: .value("Date", item.date),
                    y: .value("Weight", item.weight)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.brandPrimary.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: max(0, minWeight - padding)...(maxWeight + padding))
        .chartXScale(domain: firstDate...lastDate)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.month().day())
                            .appFont(size: 11)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text("\(Int(val))")
                            .appFont(size: 11)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let date: Date = proxy.value(atX: location.x) else { return }
                        if let closest = sortedHistory.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
                            if abs(closest.date.timeIntervalSince(date)) < 86400 * 3 {
                                onEntrySelected?(closest.id)
                            }
                        }
                    }
            }
        }
    }
}
