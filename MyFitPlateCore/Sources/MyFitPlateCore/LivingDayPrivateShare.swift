import Foundation

/// Versioned, deliberately minimized export. Both renderers consume only these lines.
public struct LivingDayPrivateShare: Equatable, Sendable {
    public enum Preset: String, CaseIterable, Sendable { case publicSummary, privateCheckIn }
    public struct Options: Equatable, Sendable {
        public var budget = false
        public var path = true
        public var foodNames = false
        public var weight = false
        public var trust = false
        public var action = false
        public init(preset: Preset = .publicSummary) {
            if preset == .privateCheckIn { budget = true; action = true }
        }
    }
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: Int
        public let title: String
        public let value: String
    }
    public let templateVersion = 2
    public let title: String
    public let caption: String
    public let lines: [Line]
    public var text: String {
        ([title] + (caption.isEmpty ? [] : [caption]) + lines.map { "\($0.title): \($0.value)" }).joined(separator: "\n")
    }
    public init(snapshot: LivingDaySnapshot, options: Options, foodNames: [String] = [], weightPounds: Double? = nil,
                metric: Bool = false, dayStatus: NutritionDayStatus = .unknown, caption: String = "", calendar: Calendar = .current) {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "EEEE, yyyy-MM-dd"
        title = "My day · \(formatter.string(from: snapshot.date))"
        self.caption = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        var rows: [(String, String)] = []
        let state = dayStatus == .complete ? "Reviewed fully logged" : dayStatus == .partial ? "Partly logged" : "Open / not reviewed as fully logged"
        rows.append(("Diary", state))
        if options.budget {
            for nutrient in snapshot.budget.nutrients {
                let unit = nutrient.kind == .calories ? "kcal" : "g"
                func amount(_ value: Double?) -> String {
                    guard let value, value.isFinite else { return "unknown" }
                    return value.formatted(.number.precision(.fractionLength(0...1))) + " " + unit
                }
                rows.append((String(describing: nutrient.kind).capitalized,
                             "Eaten \(amount(nutrient.consumed)); planned \(amount(nutrient.planned)); target \(amount(nutrient.target))"))
            }
        }
        let events = WidgetPathProjection.make(from: snapshot, limit: snapshot.events.count)
        if options.path {
            let time = DateFormatter(); time.calendar = calendar; time.timeZone = calendar.timeZone; time.timeStyle = .short
            for event in events.prefix(5) {
                let state = event.state == .completed ? "completed" : event.state == .planned ? "planned" : "in progress"
                rows.append((event.kind.rawValue.capitalized, "\(event.isApproximate ? "Approx. " : "")\(time.string(from: event.startDate)) · \(state)"))
            }
            if events.count > 5 { rows.append(("Path scope", "5 of \(events.count) events shown")) }
            if events.isEmpty { rows.append(("Path", "No events in this snapshot")) }
        }
        if options.foodNames {
            let names = foodNames.map { String($0.prefix(120)) }.filter { !$0.isEmpty }
            rows.append(("Logged foods", names.isEmpty ? "No captured food names for this day" : names.prefix(8).joined(separator: ", ")))
            if names.count > 8 { rows.append(("Food scope", "8 of \(names.count) foods shown")) }
        }
        if options.weight {
            let value = weightPounds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            rows.append(("Weight on selected day", value.map { (metric ? $0 / 2.2046226218 : $0).formatted(.number.precision(.fractionLength(1))) + (metric ? " kg" : " lb") } ?? "No captured measurement"))
        }
        if options.trust { rows.append(("Data review", "\(events.filter(\.needsTrustReview).count) path review markers")) }
        if options.action {
            let actions: [DailyNextAction.Kind: String] = [.preWorkoutFuel: "Fuel before training", .recoveryMeal: "Recovery fuel", .proteinCatchUp: "Close the protein gap", .trustReview: "Review food data", .steadyDay: "Stay steady"]
            rows.append(("Next step", actions[snapshot.nextAction.kind] ?? "Review day"))
        }
        lines = rows.enumerated().map { Line(id: $0.offset, title: $0.element.0, value: $0.element.1) }
    }
}
