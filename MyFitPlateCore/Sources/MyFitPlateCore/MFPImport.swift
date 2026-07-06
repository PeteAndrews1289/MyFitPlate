import Foundation

/// Importer for MyFitnessPal data exports — the single biggest switching cost for the
/// users MyFitPlate wants to win is losing their history, so this removes it.
///
/// MFP exports arrive in two shapes and this parser tolerates both:
/// - Food-level rows (Date, Meal, Food, Calories, ...) → real diary lines per item.
/// - Per-meal aggregates (Date, Meal, Calories, ...) with no food column → one synthetic
///   entry per meal row ("MyFitnessPal import — Lunch") carrying the aggregate macros,
///   which rebuilds daily totals, trends, and TDEE history perfectly.
/// Headers are matched case-insensitively by name (column order and extras don't matter),
/// dates parse across MFP's known formats, and malformed rows are skipped and counted —
/// never fatal.
public enum MFPImport {

    public struct ParsedDiary: Equatable {
        public let dailyLogs: [DailyLog]
        public let skippedRows: Int
        public var totalFoodEntries: Int {
            dailyLogs.reduce(0) { $0 + $1.meals.reduce(0) { $0 + $1.foodItems.count } }
        }
        public var dateRange: ClosedRange<Date>? {
            let dates = dailyLogs.map(\.date).sorted()
            guard let first = dates.first, let last = dates.last else { return nil }
            return first...last
        }
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case emptyFile
        case missingRequiredColumns(String)

        public var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "That file is empty."
            case .missingRequiredColumns(let details):
                return "This doesn't look like a MyFitnessPal export — missing \(details)."
            }
        }
    }

    // MARK: - Diary

    public static func parseDiary(csv: String, calendar: Calendar = .current) throws -> ParsedDiary {
        let table = CSVTable(csv)
        guard !table.rows.isEmpty else { throw ImportError.emptyFile }

        guard let dateColumn = table.columnIndex(named: "date") else {
            throw ImportError.missingRequiredColumns("a Date column")
        }
        guard let caloriesColumn = table.columnIndex(named: "calories") else {
            throw ImportError.missingRequiredColumns("a Calories column")
        }

        let mealColumn = table.columnIndex(named: "meal")
        let foodColumn = table.columnIndex(named: "food", "food name", "item", "food_name")
        let proteinColumn = table.columnIndex(named: "protein", "protein (g)")
        let carbsColumn = table.columnIndex(named: "carbohydrates", "carbohydrates (g)", "carbs", "carbs (g)")
        let fatColumn = table.columnIndex(named: "fat", "fat (g)", "fats", "fats (g)")
        let fiberColumn = table.columnIndex(named: "fiber", "fiber (g)")
        let sodiumColumn = table.columnIndex(named: "sodium", "sodium (mg)")

        var skipped = 0
        // date → mealName → items, preserving encounter order via arrays.
        var byDay: [Date: [(meal: String, item: FoodItem)]] = [:]

        for row in table.rows {
            guard let rawDate = row[safe: dateColumn], let date = parseDate(rawDate, calendar: calendar) else {
                skipped += 1
                continue
            }
            guard let calories = row[safe: caloriesColumn].flatMap(parseNumber), calories >= 0 else {
                skipped += 1
                continue
            }

            let mealName = normalizedMealName(mealColumn.flatMap { row[safe: $0] })
            let foodName = foodColumn.flatMap { row[safe: $0] }?.trimmingCharacters(in: .whitespaces)

            let item = FoodItem(
                name: foodName?.isEmpty == false ? foodName! : "MyFitnessPal import — \(mealName)",
                calories: calories,
                protein: proteinColumn.flatMap { row[safe: $0] }.flatMap(parseNumber) ?? 0,
                carbs: carbsColumn.flatMap { row[safe: $0] }.flatMap(parseNumber) ?? 0,
                fats: fatColumn.flatMap { row[safe: $0] }.flatMap(parseNumber) ?? 0,
                fiber: fiberColumn.flatMap { row[safe: $0] }.flatMap(parseNumber),
                servingSize: "1 serving",
                timestamp: date,
                sourceMetadata: .userEntered(sourceName: "MyFitnessPal"),
                sodium: sodiumColumn.flatMap { row[safe: $0] }.flatMap(parseNumber)
            )
            byDay[calendar.startOfDay(for: date), default: []].append((mealName, item))
        }

        let logs = byDay
            .map { day, entries -> DailyLog in
                var meals: [Meal] = []
                for (mealName, item) in entries {
                    if let index = meals.firstIndex(where: { $0.name == mealName }) {
                        meals[index].foodItems.append(item)
                    } else {
                        meals.append(Meal(name: mealName, foodItems: [item]))
                    }
                }
                return DailyLog(date: day, meals: meals)
            }
            .sorted { $0.date < $1.date }

        return ParsedDiary(dailyLogs: logs, skippedRows: skipped)
    }

    // MARK: - Weight measurements

    /// Parses MFP's Measurement export (Date, Weight). Detects kg via the header
    /// ("Weight (kg)") or a Unit column; stores lbs internally like everything else.
    public static func parseMeasurements(csv: String, calendar: Calendar = .current) -> [(date: Date, weightLbs: Double)] {
        let table = CSVTable(csv)
        guard let dateColumn = table.columnIndex(named: "date"),
              let weightColumn = table.columnIndex(named: "weight", "weight (lbs)", "weight (kg)", "body weight") else {
            return []
        }

        let headerIsKg = table.headers[weightColumn].lowercased().contains("kg")
        let unitColumn = table.columnIndex(named: "unit", "units")

        var seen = Set<Date>()
        var results: [(date: Date, weightLbs: Double)] = []
        for row in table.rows {
            guard let date = row[safe: dateColumn].flatMap({ parseDate($0, calendar: calendar) }),
                  let value = row[safe: weightColumn].flatMap(parseNumber), value > 0 else { continue }

            let rowIsKg = headerIsKg || (unitColumn.flatMap { row[safe: $0] }?.lowercased().contains("kg") ?? false)
            let lbs = rowIsKg ? value / 0.45359237 : value

            // Physiological sanity: 50–1,000 lbs. Outside that is a unit mixup or typo.
            guard (50...1000).contains(lbs) else { continue }

            let day = calendar.startOfDay(for: date)
            guard !seen.contains(day) else { continue }
            seen.insert(day)
            results.append((day, lbs))
        }
        return results.sorted { $0.date < $1.date }
    }

    // MARK: - Merge policy

    /// Days the user has already logged in MyFitPlate always win — an import must never
    /// overwrite or duplicate into real entries. Returns what's safe to write plus the
    /// count of conflicting days skipped (surfaced in the preview).
    public static func mergePlan(imported: [DailyLog], existingLoggedDays: Set<Date>, calendar: Calendar = .current) -> (toImport: [DailyLog], skippedConflicts: Int) {
        let normalizedExisting = Set(existingLoggedDays.map { calendar.startOfDay(for: $0) })
        let safe = imported.filter { !normalizedExisting.contains(calendar.startOfDay(for: $0.date)) }
        return (safe, imported.count - safe.count)
    }

    // MARK: - Field parsing

    static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        for formatter in Self.dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "MMMM d, yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\"", with: "")
        guard !cleaned.isEmpty, cleaned != "--" else { return nil }
        return Double(cleaned)
    }

    static func normalizedMealName(_ raw: String?) -> String {
        let cleaned = raw?.trimmingCharacters(in: .whitespaces).capitalized ?? ""
        switch cleaned.lowercased() {
        case "breakfast": return "Breakfast"
        case "lunch": return "Lunch"
        case "dinner": return "Dinner"
        case "snack", "snacks": return "Snacks"
        case "": return "Imported"
        default: return cleaned
        }
    }
}

/// Minimal tolerant CSV reader: RFC 4180 quoting (embedded commas, escaped quotes),
/// CRLF or LF line endings, blank lines skipped, header row required.
struct CSVTable {
    let headers: [String]
    let rows: [[String]]

    init(_ text: String) {
        var records: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            record.append(field)
            field = ""
        }
        func endRecord() {
            endField()
            if !(record.count == 1 && record[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                records.append(record)
            }
            record = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"" where field.isEmpty:
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    break
                case "\n":
                    endRecord()
                default:
                    field.append(char)
                }
            }
        }
        if !field.isEmpty || !record.isEmpty {
            endRecord()
        }

        self.headers = records.first?.map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        self.rows = Array(records.dropFirst())
    }

    /// First matching header, case-insensitive, by preference order.
    func columnIndex(named candidates: String...) -> Int? {
        let lowered = headers.map { $0.lowercased() }
        for candidate in candidates {
            if let index = lowered.firstIndex(of: candidate.lowercased()) {
                return index
            }
        }
        return nil
    }
}

extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
