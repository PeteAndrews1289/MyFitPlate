import Foundation

/// Human-readable and tabular alternatives to the native PDF. Explicit columns keep
/// interpretation, calculated evidence and optional source prose distinguishable.
public enum InsightReportExport {
    public enum Format: String, CaseIterable { case text, csv }
    public static func content(insights: [UserInsight], format: Format, includeEvidence: Bool, includeSourceText: Bool) throws -> String {
        guard !insights.isEmpty else { throw InsightEvidenceError.invalid }
        switch format {
        case .text:
            return insights.enumerated().map { index, insight in
                var lines = ["\(index + 1). \(insight.title)", insight.message]
                if includeEvidence {
                    if let evidence = insight.evidence {
                        lines += [evidence.sourceLabel, window(evidence), evidence.coverageDescription,
                            "Captured targets: \(number(evidence.calorieGoal)) cal/day; \(number(evidence.proteinGoal)) g protein/day",
                            "Method: \(evidence.calculationVersion)"]
                        lines += evidence.days.map { day in
                            "\(day.dayKey): \(day.status.title); " + (day.includedInIntake ? "\(number(day.calories)) cal, \(number(day.protein)) g protein" : "intake excluded") + "; \(day.workoutIDs.count) workout records"
                        }
                    } else { lines.append("No captured record evidence is available.") }
                }
                if includeSourceText, let source = insight.sourceData { lines += ["Interpretation's source explanation (may be AI-written):", source] }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n\n") + "\n\nMyFitPlate: captured inputs are not causal proof. Missing intake is not zero intake.\n"
        case .csv:
            let columns = ["row_type", "insight_number", "title", "interpretation", "origin", "window", "coverage", "day", "status", "intake_included", "calories", "protein_g", "carbs_g", "fat_g", "water_oz", "workout_count", "sleep_hours", "calorie_goal", "protein_goal_g", "method", "optional_source_explanation"]
            var rows = [columns]
            for (index, insight) in insights.enumerated() {
                var row = Array(repeating: "", count: columns.count)
                row[0] = "interpretation"; row[1] = String(index + 1); row[2] = insight.title; row[3] = insight.message
                if includeEvidence, let evidence = insight.evidence {
                    row[4] = evidence.sourceLabel; row[5] = window(evidence); row[6] = evidence.coverageDescription
                    row[17] = number(evidence.calorieGoal); row[18] = number(evidence.proteinGoal); row[19] = evidence.calculationVersion
                }
                if includeSourceText { row[20] = insight.sourceData ?? "" }
                rows.append(row)
                if includeEvidence, let evidence = insight.evidence {
                    for day in evidence.days {
                        var record = Array(repeating: "", count: columns.count)
                        record[0] = "recorded_day"; record[1] = String(index + 1); record[7] = day.dayKey
                        record[8] = day.status.title; record[9] = day.includedInIntake ? "true" : "false"
                        record[10] = number(day.calories); record[11] = number(day.protein); record[12] = number(day.carbs); record[13] = number(day.fats)
                        record[14] = number(day.waterOunces); record[15] = String(day.workoutIDs.count); rows.append(record)
                    }
                    for night in evidence.sleepNights {
                        var record = Array(repeating: "", count: columns.count)
                        record[0] = "recorded_sleep"; record[1] = String(index + 1)
                        record[7] = day(night.date, zone: evidence.timeZoneIdentifier); record[16] = number(night.hours); rows.append(record)
                    }
                }
            }
            return rows.map { $0.map(DataExporter.escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        }
    }
    public static func window(_ evidence: InsightEvidenceSnapshot) -> String {
        "\(day(evidence.windowStart, zone: evidence.timeZoneIdentifier))–\(day(evidence.windowEnd, zone: evidence.timeZoneIdentifier)) (\(evidence.timeZoneIdentifier))"
    }
    private static func day(_ value: Date, zone: String) -> String {
        DiaryDayContext.dayKey(for: value, timeZone: TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!) ?? "unknown"
    }
    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
