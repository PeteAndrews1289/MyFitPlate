import SwiftUI
import Charts
import MyFitPlateCore

struct WeightChartView: View {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    var currentWeight: Double
    var onEntrySelected: ((_ entryId: String) -> Void)?
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    var body: some View {
        let raw = weightHistory.filter { $0.weight.isFinite && $0.weight > 0 && $0.date <= Date() }.sorted { $0.date < $1.date }
        let trend = WeightTrendRules.project(raw.map { .init(id: $0.id, date: $0.date, pounds: $0.weight) })
        let measured = raw.map { (id: $0.id, date: $0.date, weight: display($0.weight)) }
        let weights = measured.map(\.weight) + trend.points.map { display($0.pounds) }
        let minWeight = weights.min() ?? display(currentWeight)
        let maxWeight = weights.max() ?? display(currentWeight)
        let padding = max(useMetric ? 1 : 2, (maxWeight - minWeight) * 0.25)
        let firstDate = raw.first?.date ?? Date()
        let lastRaw = raw.last?.date ?? Date()
        let lastDate = lastRaw > firstDate ? lastRaw : (Calendar.current.date(byAdding: .day, value: 1, to: firstDate) ?? firstDate)

        Chart {
            ForEach(measured, id: \.id) { item in
                PointMark(x: .value("Date", item.date), y: .value("Measured weight", item.weight))
                    .foregroundStyle(AppPalette.brand.opacity(0.55))
                    .symbolSize(30)
            }
            ForEach(trend.points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Estimated trend", display(point.pounds)),
                    series: .value("Observed interval", point.segment))
                    .foregroundStyle(AppPalette.brand)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartYScale(domain: max(0, minWeight - padding)...(maxWeight + padding))
        .chartXScale(domain: Calendar.current.startOfDay(for: firstDate)...lastDate)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 5)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(date, format: .dateTime.month().day()).appFont(size: 11)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.precision(.fractionLength(0))))
                            .appFont(size: 11).foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let plot = geometry[plotFrame]
                        guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else { return }
                        if let closest = raw.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                           abs(closest.date.timeIntervalSince(date)) < 86_400 * 3 {
                            onEntrySelected?(closest.id)
                        }
                    }
            }
        }
        .clipped()
    }

    private func display(_ pounds: Double) -> Double { BodyUnits.weightDisplayValue(lbs: pounds, metric: useMetric) }
}
