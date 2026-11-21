import Foundation

/// A manual diary destination is a civil day, not a timestamp that follows the device
/// through timezones. Existing document keys and stored date anchors remain authoritative.
public struct DiaryDayContext: Codable, Equatable, Sendable {
    public let userID: String
    public let dayKey: String
    public let timeZoneIdentifier: String
    public let originalDate: Date

    public init?(userID: String, date: Date, timeZone: TimeZone = .current, dayKey: String? = nil) {
        guard !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              date.timeIntervalSinceReferenceDate.isFinite,
              let key = dayKey ?? Self.dayKey(for: date, timeZone: timeZone),
              Self.components(for: key) != nil else { return nil }
        self.userID = userID
        self.dayKey = key
        timeZoneIdentifier = timeZone.identifier
        originalDate = date
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)! }

    public var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "en_US_POSIX")
        result.timeZone = timeZone
        return result
    }

    /// Noon avoids ordinary daylight-saving transitions at midnight. The captured key
    /// remains authoritative even for a historical timezone that skipped an entire day.
    public var displayDate: Date {
        guard var components = Self.components(for: dayKey) else { return originalDate }
        components.hour = 12
        return calendar.date(from: components) ?? originalDate
    }

    /// Used only when creating a new empty day. Existing stored date anchors are never rewritten.
    public var startOfDay: Date { calendar.startOfDay(for: displayDate) }

    public func isOwned(by currentUserID: String?) -> Bool { currentUserID == userID }

    public func isToday(now: Date = Date()) -> Bool {
        Self.dayKey(for: now, timeZone: timeZone) == dayKey
    }

    public func isFuture(now: Date = Date()) -> Bool {
        guard let today = Self.dayKey(for: now, timeZone: timeZone) else { return true }
        return dayKey > today
    }

    public func adding(days: Int) -> DiaryDayContext? {
        guard let next = calendar.date(byAdding: .day, value: days, to: displayDate) else { return nil }
        return DiaryDayContext(userID: userID, date: calendar.startOfDay(for: next), timeZone: timeZone)
    }

    public static func dayKey(for date: Date, timeZone: TimeZone = .current) -> String? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard values.era == 1, let year = values.year, (1...9_999).contains(year),
              let month = values.month, let day = values.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func components(for key: String) -> DateComponents? {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(key.prefix(4)), year > 0,
              let month = Int(key.dropFirst(5).prefix(2)),
              let day = Int(key.suffix(2)) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard resolved.era == 1, resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    private enum CodingKeys: String, CodingKey { case userID, dayKey, timeZoneIdentifier, originalDate }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let userID = try values.decode(String.self, forKey: .userID)
        let key = try values.decode(String.self, forKey: .dayKey)
        let identifier = try values.decode(String.self, forKey: .timeZoneIdentifier)
        let date = try values.decode(Date.self, forKey: .originalDate)
        guard let timeZone = TimeZone(identifier: identifier),
              let context = Self(userID: userID, date: date, timeZone: timeZone, dayKey: key) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "The captured diary day is invalid."))
        }
        self = context
    }
}
