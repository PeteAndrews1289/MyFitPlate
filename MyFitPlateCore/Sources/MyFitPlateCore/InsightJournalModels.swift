import Foundation

public struct UserInsight: Identifiable, Decodable, Equatable {
    public let id = UUID()
    public var title: String
    public var message: String
    public var category: InsightCategory
    public var priority: Int = 0
    public var sourceData: String?

    private enum CodingKeys: String, CodingKey {
        case title, message, category, priority, sourceData
    }

    public enum InsightCategory: String, Codable, Equatable, CaseIterable {
        case nutritionGeneral, hydration, macroBalance, microNutrient, mealTiming, consistency, postWorkout, foodVariety, positiveReinforcement, sugarAwareness, fiberIntake, saturatedFat, smartSuggestion, sleep, calorieFluctuation, weekendTrends, exerciseSynergy
    }

    public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            message = try container.decode(String.self, forKey: .message)
            category = (try? container.decode(InsightCategory.self, forKey: .category)) ?? .nutritionGeneral
            priority = (try? container.decode(Int.self, forKey: .priority)) ?? 0
            sourceData = try container.decodeIfPresent(String.self, forKey: .sourceData)
        }

        public init(title: String, message: String, category: InsightCategory, priority: Int = 0, sourceData: String? = nil) {
            self.title = title
            self.message = message
            self.category = category
            self.priority = priority
            self.sourceData = sourceData
        }
}

public struct JournalEntry: Codable, Identifiable, Hashable {
    public var id: String = UUID().uuidString
    public var date: Date
    public var text: String
    public var category: String

    public init(id: String = UUID().uuidString, date: Date, text: String, category: String) {
        self.id = id
        self.date = date
        self.text = text
        self.category = category
    }
}

public enum ReportTimeframe: String, CaseIterable, Identifiable {
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case custom = "Custom Range"
    public var id: String { self.rawValue }
}

public enum WeightChartTimeframe: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case threeMonths = "3M"
    case year = "Y"
    case allTime = "All"
    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .week: return "Last 7 Days"
        case .month: return "Last 30 Days"
        case .threeMonths: return "Last 3 Months"
        case .year: return "Last Year"
        case .allTime: return "All Time"
        }
    }
}

public struct JournalEmojiMapper {
    public static func getEmoji(for category: String) -> String {
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
