import Foundation

/// CSV export of the user's data — their food diary and training history, in a format any
/// spreadsheet opens. Data portability is a trust signal: the door is never locked.
public enum DataExporter {

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public static func foodLogCSV(from logs: [DailyLog]) -> String {
        var rows = ["date,meal,food,calories,protein_g,carbs_g,fats_g,serving,serving_weight_g"]

        for log in logs.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: log.date)
            for meal in log.meals {
                for item in meal.foodItems {
                    rows.append([
                        date,
                        escape(meal.name),
                        escape(item.name),
                        format(item.calories),
                        format(item.protein),
                        format(item.carbs),
                        format(item.fats),
                        escape(item.servingSize),
                        format(item.servingWeight)
                    ].joined(separator: ","))
                }
            }
        }

        return rows.joined(separator: "\n")
    }

    public static func workoutCSV(from sessions: [WorkoutSessionLog]) -> String {
        var rows = ["date,exercise,set,weight_lbs,reps,distance_miles,duration_seconds"]

        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let date = dateFormatter.string(from: session.date)
            for exercise in session.completedExercises {
                for (index, set) in exercise.sets.enumerated() {
                    rows.append([
                        date,
                        escape(exercise.exerciseName),
                        "\(index + 1)",
                        format(set.weight),
                        "\(set.reps)",
                        format(set.distance ?? 0),
                        "\(set.durationInSeconds ?? 0)"
                    ].joined(separator: ","))
                }
            }
        }

        return rows.joined(separator: "\n")
    }

    /// Neutralizes spreadsheet formulas before applying RFC 4180 quoting.
    static func escape(_ field: String) -> String {
        let formulaPrefixes: Set<Character> = ["=", "+", "-", "@"]
        let firstNonWhitespace = field.first(where: { !$0.isWhitespace })
        let startsWithControlCharacter =
            field.first == "\t" || field.first == "\r" || field.first == "\n"
        let startsWithFormula = firstNonWhitespace.map(formulaPrefixes.contains) == true
        let protectedField = startsWithControlCharacter || startsWithFormula
            ? "'\(field)"
            : field

        guard protectedField.contains(",") || protectedField.contains("\"") || protectedField.contains("\n") else {
            return protectedField
        }
        return "\"\(protectedField.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
