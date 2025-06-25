import SwiftUI
import DGCharts // Make sure DGCharts is imported

// This view represents a line chart for displaying weight history over time, bridging SwiftUI
// with a UIKit-based DGCharts (Charts) LineChartView for advanced charting capabilities.
struct WeightChartView: UIViewRepresentable {
    var weightHistory: [(id: String, date: Date, weight: Double)]
    var currentWeight: Double

    // *** Add callback for when a chart entry is selected ***
    var onEntrySelected: ((_ entryId: String) -> Void)? = nil

    // MARK: - Coordinator
    // *** Coordinator now conforms to ChartViewDelegate ***
    class Coordinator: NSObject, ChartViewDelegate {
        var parent: WeightChartView

        init(parent: WeightChartView) {
            self.parent = parent
        }

        // *** Delegate method called when a value is tapped ***
        func chartValueSelected(_ chartView: ChartViewBase, entry: ChartDataEntry, highlight: Highlight) {
            print("Chart value selected: x=\(entry.x), y=\(entry.y)")
            // Find the corresponding entry in our data source using the timestamp (entry.x)
            // Allow for a small tolerance due to floating point conversion
            let selectedTimestamp = entry.x
            let tolerance = 1.0 // Allow 1 second difference

            if let matchedEntry = parent.weightHistory.first(where: { abs($0.date.timeIntervalSince1970 - selectedTimestamp) < tolerance }) {
                print("Matched entry: ID=\(matchedEntry.id), Date=\(matchedEntry.date), Weight=\(matchedEntry.weight)")
                // Call the callback closure with the ID of the matched entry
                parent.onEntrySelected?(matchedEntry.id)
            } else {
                print("⚠️ Could not find matching entry for timestamp: \(selectedTimestamp)")
            }

            // Deselect the value immediately after handling if desired
            chartView.highlightValue(nil)
        }

         // Optional: Handle deselection if needed
         func chartValueNothingSelected(_ chartView: ChartViewBase) {
             print("Chart value deselected.")
         }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - UIViewRepresentable Methods
    func makeUIView(context: Context) -> DGCharts.LineChartView {
        let chartView = DGCharts.LineChartView()
        // *** Set the delegate ***
        chartView.delegate = context.coordinator

        chartView.rightAxis.enabled = false
        chartView.xAxis.labelPosition = .bottom
        chartView.xAxis.drawGridLinesEnabled = false
        chartView.leftAxis.drawGridLinesEnabled = true
        chartView.leftAxis.gridColor = UIColor.systemGray4
        chartView.legend.form = .line
        chartView.xAxis.valueFormatter = DateValueFormatter()
        chartView.animate(xAxisDuration: 0.5)

        // Configure selection interaction
        chartView.highlightPerTapEnabled = true // Enable tap highlighting
        chartView.highlightPerDragEnabled = false // Disable drag highlighting if not needed

        return chartView
    }

    func updateUIView(_ uiView: DGCharts.LineChartView, context: Context) {
        setChartData(for: uiView) // Update chart data first

        guard !weightHistory.isEmpty else {
            uiView.leftAxis.resetCustomAxisMin()
            uiView.leftAxis.resetCustomAxisMax()
            uiView.notifyDataSetChanged()
            return
        }

        let weightsInHistory = weightHistory.map { $0.weight }
        let minWeight = weightsInHistory.min() ?? currentWeight
        let maxWeight = weightsInHistory.max() ?? currentWeight
        let padding = max(5.0, (maxWeight - minWeight) * 0.1)
        let yAxisMinimum = max(0, minWeight - padding)
        let yAxisMaximum = maxWeight + padding

        if abs(uiView.leftAxis.axisMinimum - yAxisMinimum) > 0.1 || abs(uiView.leftAxis.axisMaximum - yAxisMaximum) > 0.1 {
            uiView.leftAxis.axisMinimum = yAxisMinimum
            uiView.leftAxis.axisMaximum = yAxisMaximum
            // Don't animate here, let setChartData handle notifications
        }
        // Ensure data set notification happens after potential axis change
         uiView.notifyDataSetChanged()
    }

    // Configures the chart data and appearance based on the weight history.
    private func setChartData(for chartView: DGCharts.LineChartView) {
        guard !weightHistory.isEmpty else {
            chartView.data = nil
            // Need to notify even when clearing data
            chartView.notifyDataSetChanged()
            return
        }

        var dataEntries: [ChartDataEntry] = []
        for record in weightHistory.sorted(by: { $0.date < $1.date }) {
            let dateValue = record.date.timeIntervalSince1970
            let weightValue = record.weight
            // *** Store the ID in the data property of ChartDataEntry ***
            // Note: DGCharts' data property is Any? so we store the ID string.
            let dataEntry = ChartDataEntry(x: dateValue, y: weightValue, data: record.id as Any?)
            dataEntries.append(dataEntry)
        }

        let lineDataSet = LineChartDataSet(entries: dataEntries, label: "Weight")
        // ... (styling remains the same as previous version) ...
        lineDataSet.colors = [NSUIColor(red: 67/255, green: 173/255, blue: 111/255, alpha: 1)]
        lineDataSet.circleColors = [NSUIColor(red: 67/255, green: 173/255, blue: 111/255, alpha: 1)]
        lineDataSet.circleHoleColor = NSUIColor(red: 67/255, green: 173/255, blue: 111/255, alpha: 1) // Match hole color
        lineDataSet.circleRadius = 4 // Slightly larger circles for easier tapping
        lineDataSet.lineWidth = 2
        lineDataSet.valueFont = .systemFont(ofSize: 9)
        lineDataSet.valueTextColor = NSUIColor.systemGray
        lineDataSet.mode = .cubicBezier
        lineDataSet.drawValuesEnabled = false
        lineDataSet.drawCirclesEnabled = true
        lineDataSet.drawFilledEnabled = true
        let gradientColors = [NSUIColor(red: 67/255, green: 173/255, blue: 111/255, alpha: 0.5).cgColor,
                              NSUIColor(red: 67/255, green: 173/255, blue: 111/255, alpha: 0.0).cgColor]
        if let gradient = CGGradient(colorsSpace: nil, colors: gradientColors as CFArray, locations: nil) {
            lineDataSet.fill = LinearGradientFill(gradient: gradient, angle: 90.0)
        }
        // Make the highlights more visible
        lineDataSet.highlightColor = NSUIColor.systemRed
        lineDataSet.highlightLineWidth = 1.5
        lineDataSet.drawHorizontalHighlightIndicatorEnabled = false // Disable horizontal line if desired
        lineDataSet.highlightLineDashLengths = [4, 2] // Dashed vertical highlight line

        let lineData = LineChartData(dataSet: lineDataSet)
        chartView.data = lineData
        // Notify chart data has changed - moved to updateUIView to ensure axis are set first
        // chartView.notifyDataSetChanged()
    }
}

// DateValueFormatter class remains the same
class DateValueFormatter: AxisValueFormatter {
    private let dateFormatter: DateFormatter
    init() { dateFormatter = DateFormatter(); dateFormatter.dateStyle = .short }
    func stringForValue(_ value: Double, axis: AxisBase?) -> String { let date = Date(timeIntervalSince1970: value); return dateFormatter.string(from: date) }
}
