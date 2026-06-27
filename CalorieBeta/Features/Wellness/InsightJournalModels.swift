import Foundation

struct UserInsight: Identifiable, Decodable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var category: InsightCategory
    var priority: Int = 0
    var sourceData: String?

    private enum CodingKeys: String, CodingKey {
        case title, message, category, priority, sourceData
    }

    enum InsightCategory: String, Codable, Equatable, CaseIterable {
        case nutritionGeneral, hydration, macroBalance, microNutrient, mealTiming, consistency, postWorkout, foodVariety, positiveReinforcement, sugarAwareness, fiberIntake, saturatedFat, smartSuggestion, sleep, calorieFluctuation, weekendTrends, exerciseSynergy
    }

    init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            message = try container.decode(String.self, forKey: .message)
            category = (try? container.decode(InsightCategory.self, forKey: .category)) ?? .nutritionGeneral
            priority = (try? container.decode(Int.self, forKey: .priority)) ?? 0
            sourceData = try container.decodeIfPresent(String.self, forKey: .sourceData)
        }

        init(title: String, message: String, category: InsightCategory, priority: Int = 0, sourceData: String? = nil) {
            self.title = title
            self.message = message
            self.category = category
            self.priority = priority
            self.sourceData = sourceData
        }
}

struct JournalEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: Date
    var text: String
    var category: String
}

enum ReportTimeframe: String, CaseIterable, Identifiable {
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case custom = "Custom Range"
    var id: String { self.rawValue }
}

enum WeightChartTimeframe: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case threeMonths = "3M"
    case year = "Y"
    case allTime = "All"
    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .week: return "Last 7 Days"
        case .month: return "Last 30 Days"
        case .threeMonths: return "Last 3 Months"
        case .year: return "Last Year"
        case .allTime: return "All Time"
        }
    }
}

struct JournalEmojiMapper {
    static func getEmoji(for category: String) -> String {
        switch category.lowercased() {
        case "recovery":
            return "🧊"
        case "mindfulness":
            return "🧘"
        case "flexibility":
            return "🙆"
        case "other":
            return "📝"
        default:
            return "📝"
        }
    }
}
