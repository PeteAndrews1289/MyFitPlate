import Foundation

public enum WaterVolumeUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case ounces, milliliters
    public var id: String { rawValue }
    public var symbol: String { self == .ounces ? "oz" : "mL" }
    public func ounces(from value: Double) -> Double { self == .ounces ? value : value / 29.5735295625 }
    public func amount(fromOunces value: Double) -> Double { self == .ounces ? value : value * 29.5735295625 }
}
public struct WaterContainer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Double
    public var unit: WaterVolumeUnit
    public var ounces: Double { unit.ounces(from: amount) }
    public var label: String { "\(name) · \(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)" }
    public init(id: UUID = UUID(), name: String, amount: Double, unit: WaterVolumeUnit) {
        self.id = id; self.name = name; self.amount = amount; self.unit = unit
    }
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && amount.isFinite && (0.1...128).contains(ounces) }
}
public struct WaterTargetPeriod: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let acceptedAt: Date
    public let effectiveDay: Date
    /// Nil is an explicit tracking-only choice, not an unknown/zero target.
    public let targetOunces: Double?
    public init(id: UUID = UUID(), acceptedAt: Date = Date(), effectiveDay: Date, targetOunces: Double?) {
        self.id = id; self.acceptedAt = acceptedAt; self.effectiveDay = effectiveDay; self.targetOunces = targetOunces
    }
}
public struct HydrationPreferences: Codable, Equatable, Sendable {
    public static let scope = "hydration-preferences-v1"
    public var unit: WaterVolumeUnit = .ounces
    public var containers: [WaterContainer] = [
        .init(name: "Glass", amount: 8, unit: .ounces), .init(name: "Bottle", amount: 16, unit: .ounces),
        .init(name: "Glass", amount: 250, unit: .milliliters), .init(name: "Bottle", amount: 500, unit: .milliliters)
    ]
    public var preferredContainerID: UUID?
    public var targetHistory: [WaterTargetPeriod] = []
    public init() {}
    public var preferredContainer: WaterContainer? { containers.first { $0.id == preferredContainerID } ?? containers.first }
    public var isTrackingOnly: Bool { targetHistory.last.map { $0.targetOunces == nil } ?? false }
    public func targetPeriod(for day: Date, calendar: Calendar = .current) -> WaterTargetPeriod? {
        targetHistory.last { $0.effectiveDay <= calendar.startOfDay(for: day) }
    }
    public mutating func acceptTarget(_ ounces: Double?, at now: Date = Date(), calendar: Calendar = .current) throws {
        guard now.timeIntervalSince1970.isFinite, ounces.map({ $0.isFinite && (1...512).contains($0) }) ?? true,
              targetHistory.last.map({ now >= $0.acceptedAt }) ?? true else { throw GoalEditorError.invalid }
        if targetHistory.last.map({ $0.targetOunces == ounces }) == true { return }
        targetHistory.append(.init(acceptedAt: now, effectiveDay: calendar.startOfDay(for: now), targetOunces: ounces))
    }
    public func validate() throws {
        guard containers.count <= 20, containers.allSatisfy(\.isValid), Set(containers.map(\.id)).count == containers.count,
              preferredContainerID.map({ id in containers.contains { $0.id == id } }) ?? true,
              Set(targetHistory.map(\.id)).count == targetHistory.count,
              targetHistory.allSatisfy({ $0.acceptedAt.timeIntervalSince1970.isFinite && $0.effectiveDay.timeIntervalSince1970.isFinite && ($0.targetOunces.map { $0.isFinite && (1...512).contains($0) } ?? true) }),
              zip(targetHistory, targetHistory.dropFirst()).allSatisfy({ $0.acceptedAt <= $1.acceptedAt && $0.effectiveDay <= $1.effectiveDay }) else { throw GoalEditorError.invalid }
    }
}

extension GoalSettings {
    @MainActor public var isWaterTrackingOnly: Bool { hydrationPreferences.isTrackingOnly }
    @MainActor public func hydrationTarget(for date: Date, recordedGoal: Double? = nil) -> Double? {
        // The confirmed profile target remains authoritative if writing its local
        // history failed. An explicit tracking-only choice remains separate.
        if Calendar.current.isDateInToday(date), !isWaterTrackingOnly { return waterGoal }
        if let period = hydrationPreferences.targetPeriod(for: date) { return period.targetOunces }
        return recordedGoal.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
    @MainActor public func loadHydrationPreferences(userID: String) {
        guard isActiveAccount(userID) else { return }
        do {
            var value = try EditorDraftStore().load(HydrationPreferences.self, userID: userID, scope: HydrationPreferences.scope)?.value ?? .init()
            try value.validate()
            if value.targetHistory.isEmpty || (value.targetHistory.last?.targetOunces != nil && value.targetHistory.last?.targetOunces != waterGoal) {
                // A target first observed from the account starts today. Never
                // backdate an inferred change into earlier reports.
                try value.acceptTarget(waterGoal); try EditorDraftStore().save(value, userID: userID, scope: HydrationPreferences.scope)
            }
            hydrationPreferences = value; hydrationPreferenceNotice = nil
        } catch { hydrationPreferenceNotice = "Water preferences couldn't be read. The saved file is kept; existing water logs are unchanged." }
    }
    @MainActor public func saveHydrationPreferences(_ value: HydrationPreferences, baseline: HydrationPreferences,
                                                    baselineGoal: Double, userID: String) async throws {
        guard isActiveAccount(userID) else { throw GoalEditorError.accountChanged }
        guard hydrationPreferences == baseline else { throw GoalEditorError.changed }
        try value.validate()
        let store = EditorDraftStore()
        // Verify readability before changing the cloud target. Preserve any newer local edit.
        if let saved = try store.load(HydrationPreferences.self, userID: userID, scope: HydrationPreferences.scope)?.value,
           saved != baseline { throw GoalEditorError.changed }
        if let goal = value.targetHistory.last?.targetOunces, goal != waterGoal {
            try await saveWaterGoal(goal, baseline: baselineGoal, userID: userID)
        }
        guard isActiveAccount(userID) else { throw GoalEditorError.accountChanged }
        guard hydrationPreferences == baseline else { throw GoalEditorError.changed }
        try store.save(value, userID: userID, scope: HydrationPreferences.scope)
        hydrationPreferences = value; hydrationPreferenceNotice = nil
    }
}
