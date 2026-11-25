import Foundation

/// A deliberately route-free, account-free CSV. Values retain canonical units and
/// disclose the distinction between saved active time and elapsed wall-clock time.
public enum RunSummaryExport {
    public static func csv(run: Run) -> String {
        let timestamp = ISO8601DateFormatter()
        var rows: [[String]] = [["Metric", "Value", "Unit", "Provenance"]]
        func add(_ name: String, _ value: String, _ unit: String, _ provenance: String) {
            rows.append([name, value, unit, provenance])
        }
        func quantity(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            return String(value)
        }
        let manualTiming = run.isIndoor && run.source == .recorded && run.pauseTimeline == nil
        add("Started", timestamp.string(from: run.startDate), "ISO 8601 UTC", "Saved timestamp")
        add("Ended", timestamp.string(from: run.endDate), "ISO 8601 UTC", manualTiming ? "Derived from entered active duration; elapsed time was not recorded" : "Saved timestamp")
        add("Distance", quantity(run.distanceMeters), "meters", run.reviewAnnotation != nil ? "Reviewed manual correction in MyFitPlate" : run.isIndoor ? "Indoor saved distance; not a GPS route" : "Saved workout distance")
        add("Active time", quantity(run.movingSeconds), "seconds", run.reviewAnnotation == nil ? "Saved active workout duration" : "Reviewed manual correction in MyFitPlate")
        add("Elapsed time", manualTiming ? "" : quantity(run.endDate.timeIntervalSince(run.startDate)), "seconds", manualTiming ? "Not recorded for manual treadmill entry" : "End minus start; not active duration")
        add("Average pace", quantity(run.averagePaceSecondsPerKm), "seconds/km", "Whole-run average; not a measured best segment")
        add("Active energy", quantity(run.activeCalories), "kcal", "Saved energy estimate when available")
        add("Average heart rate", quantity(run.averageHeartRate), "bpm", "Saved workout average when available")
        add("Setting", run.isIndoor ? "Indoor" : "Outdoor", "", "Saved workout setting")
        add("Source", run.source.displayName + (run.reviewAnnotation == nil ? "" : " (manual correction in MyFitPlate; original Health evidence unchanged)"), "", "Writing app")
        if let timeline = run.pauseTimeline, let summary = timeline.summary(startDate: run.startDate, endDate: run.endDate, activeSeconds: run.movingSeconds) {
            add("Pause evidence", summary.completeness.rawValue, "", "Known event intervals only")
            add("Explicit pause time", quantity(summary.explicitPauseSeconds), "seconds", "Known explicit pause events")
            add("Recovery gap time", quantity(summary.recoveryGapSeconds), "seconds", "Known interruptions excluded from active time")
        } else {
            add("Pause evidence", "Unknown", "", "Exact pause events cannot be reconstructed from elapsed minus active time")
        }
        if let correction = run.reviewAnnotation {
            add("Original distance", quantity(correction.originalDistanceMeters), "meters", "Original evidence retained; Apple Health unchanged")
            add("Original active time", quantity(correction.originalMovingSeconds), "seconds", "Original evidence retained; Apple Health unchanged")
        }
        for (index, lap) in (run.manualLaps ?? []).enumerated() {
            let previous = index == 0 ? nil : run.manualLaps?[index - 1]
            add("Manual lap \(lap.index) active time", quantity(lap.activeElapsedSeconds - (previous?.activeElapsedSeconds ?? 0)), "seconds", "Deliberate boundary; pauses and recovery time excluded")
            add("Manual lap \(lap.index) distance", quantity(lap.distanceMeters - (previous?.distanceMeters ?? 0)), "meters", "Accepted distance between boundaries; GPS gaps are not reconstructed")
        }
        add("Route coordinates", "Not included", "", "This summary does not disclose locations or Health/account identifiers")
        return rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvCell(_ original: String) -> String {
        // A source label is text, never a spreadsheet formula.
        let value = original.first.map { "=+@-".contains($0) } == true ? "'" + original : original
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
