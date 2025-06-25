import SwiftUI
import DGCharts

struct WeightChartView: UIViewRepresentable {
    var weightHistory: [(date: Date, weight: Double)] // ✅ Updated to use weight tracking

    func makeUIView(context: Context) -> DGCharts.LineChartView {
        let chartView = DGCharts.LineChartView()
        chartView.rightAxis.enabled = false
        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.drawGridLinesEnabled = false
        chartView.leftAxis.drawGridLinesEnabled = false
        chartView.leftAxis.axisMinimum = 0
        chartView.legend.form = .line
        chartView.xAxis.valueFormatter = DateValueFormatter() // ✅ Formats X-axis as dates
        return chartView
    }

    func updateUIView(_ uiView: DGCharts.LineChartView, context: Context) {
        setChartData(for: uiView)
    }

    private func setChartData(for chartView: DGCharts.LineChartView) {
        guard !weightHistory.isEmpty else {
            chartView.data = nil // Clear the chart if there is no data
            return
        }

        var dataEntries: [ChartDataEntry] = []

        // ✅ Loop through weight history and add entries
        for record in weightHistory {
            let dateValue = record.date.timeIntervalSince1970
            let weightValue = record.weight
            let dataEntry = ChartDataEntry(x: dateValue, y: weightValue)
            dataEntries.append(dataEntry)
        }

        let lineDataSet = LineChartDataSet(entries: dataEntries, label: "Weight Over Time")
        lineDataSet.colors = [NSUIColor.blue]
        lineDataSet.circleColors = [NSUIColor.red]
        lineDataSet.circleRadius = 4
        lineDataSet.lineWidth = 2
        lineDataSet.valueFont = .systemFont(ofSize: 12)
        lineDataSet.mode = .cubicBezier

        let lineData = LineChartData(dataSet: lineDataSet)
        chartView.data = lineData

        chartView.animate(xAxisDuration: 1.5, yAxisDuration: 1.5, easingOption: .easeInOutQuad)
    }
}

// ✅ Custom formatter to convert timestamps into readable dates
class DateValueFormatter: AxisValueFormatter {
    private let dateFormatter: DateFormatter

    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short // Shows short date format (e.g., MM/dd)
    }

    func stringForValue(_ value: Double, axis: AxisBase?) -> String {
        let date = Date(timeIntervalSince1970: value)
        return dateFormatter.string(from: date)
    }
}
