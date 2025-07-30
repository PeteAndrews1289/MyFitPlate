import SwiftUI
import DGCharts

struct WeightChartView: UIViewRepresentable {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    var currentWeight: Double
    var onEntrySelected: ((_ entryId: String) -> Void)? = nil

    class Coordinator: NSObject, ChartViewDelegate {
        var parent: WeightChartView

        init(parent: WeightChartView) {
            self.parent = parent
        }

        func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
            let selectedTimestamp = entry.x
            let tolerance = 1.0

            if let matchedEntry = parent.weightHistory.first(where: { abs($0.date.timeIntervalSince1970 - selectedTimestamp) < tolerance }) {
                parent.onEntrySelected?(matchedEntry.id)
            }
            chartView.highlightValue(nil)
        }

         func chartValueNothingSelected(_ chartView: ChartViewBase) {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> DGCharts.LineChartView {
        let chartView = DGCharts.LineChartView()
        chartView.delegate = context.coordinator
        
        chartView.rightAxis.enabled = false
        chartView.legend.enabled = false
        chartView.animate(xAxisDuration: 0.5)
        chartView.drawGridBackgroundEnabled = false
        chartView.highlightPerTapEnabled = true
        chartView.highlightPerDragEnabled = false
        
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawGridLinesEnabled = false
        xAxis.valueFormatter = DateValueFormatter()
        xAxis.granularityEnabled = true
        xAxis.labelCount = 6
        xAxis.forceLabelsEnabled = true
        
        let yAxis = chartView.leftAxis
        yAxis.drawGridLinesEnabled = true
        yAxis.gridColor = UIColor.systemGray4.withAlphaComponent(0.5)
        yAxis.gridLineDashLengths = [4, 4]
        
        return chartView
    }

    func updateUIView(_ uiView: DGCharts.LineChartView, context: Context) {
        setChartData(for: uiView)

        guard !weightHistory.isEmpty else {
            uiView.leftAxis.resetCustomAxisMin()
            uiView.leftAxis.resetCustomAxisMax()
            uiView.notifyDataSetChanged()
            return
        }

        let weightsInHistory = weightHistory.map { $0.weight }
        let minWeight = weightsInHistory.min() ?? currentWeight
        let maxWeight = weightsInHistory.max() ?? currentWeight
        let padding = max(5.0, (maxWeight - minWeight) * 0.2)
        
        uiView.leftAxis.axisMinimum = max(0, minWeight - padding)
        uiView.leftAxis.axisMaximum = maxWeight + padding
        uiView.notifyDataSetChanged()
    }

    private func setChartData(for chartView: DGCharts.LineChartView) {
        guard !weightHistory.isEmpty else {
            chartView.data = nil
            chartView.notifyDataSetChanged()
            return
        }

        let sortedHistory = weightHistory.sorted { $0.date < $1.date }

        let dataEntries = sortedHistory.map { record -> ChartDataEntry in
            let dateValue = record.date.timeIntervalSince1970
            let weightValue = record.weight
            return ChartDataEntry(x: dateValue, y: weightValue, data: record.id as Any?)
        }

        let lineDataSet = LineChartDataSet(entries: dataEntries, label: "Weight")
        let brandColor = UIColor(Color.brandPrimary)
        
        lineDataSet.mode = .cubicBezier
        lineDataSet.lineWidth = 2.5
        lineDataSet.colors = [brandColor]
        
        lineDataSet.drawCirclesEnabled = true
        lineDataSet.circleRadius = 4
        lineDataSet.circleColors = [brandColor]
        lineDataSet.circleHoleColor = UIColor(Color.backgroundSecondary)
        lineDataSet.circleHoleRadius = 2
        
        lineDataSet.drawFilledEnabled = true
        let gradientColors = [brandColor.withAlphaComponent(0.3).cgColor, UIColor.clear.cgColor]
        if let gradient = CGGradient(colorsSpace: nil, colors: gradientColors as CFArray, locations: nil) {
            lineDataSet.fill = LinearGradientFill(gradient: gradient, angle: 90.0)
        }
        
        lineDataSet.drawValuesEnabled = false
        
        let lineData = LineChartData(dataSet: lineDataSet)
        chartView.data = lineData
    }
}

class DateValueFormatter: AxisValueFormatter {
    private let dateFormatter: DateFormatter
    init() { dateFormatter = DateFormatter(); dateFormatter.dateFormat = "MMM d" }
    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let date = Date(timeIntervalSince1970: value)
        return dateFormatter.string(from: date)
    }
}
