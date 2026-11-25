import MyFitPlateCore
import SwiftUI

/// Optional consistency settings and dated evidence; never changes a diary entry.
struct LoggingHabitView: View {
    var onSaved: (LoggingHabitPreferences) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dailyLogService: DailyLogService
    @State private var ownerID: String?
    @State private var original = LoggingHabitPreferences()
    @State private var preferences = LoggingHabitPreferences()
    @State private var logs: [DailyLog] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var hasHistory = false
    private let start = Calendar.current.date(byAdding: .day, value: -45, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    private var summary: LoggingHabitSummary {
        var preview = preferences; preview.reviewed = true
        return LoggingHabitRules.make(logs: logs, preferences: preview, from: start)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Choose a habit") {
                    Picker("Count days with", selection: $preferences.rule) {
                        Text("Any food entry").tag(LoggingHabitPreferences.Rule.anyEntry)
                        Text("A fully logged review").tag(LoggingHabitPreferences.Rule.reviewedComplete)
                    }.accessibilityIdentifier("logging_habit_rule")
                    Text("An entry and a fully logged day are different. Neither depends on calories, weight or exercise.")
                    Toggle("Pause consistency display", isOn: $preferences.paused)
                    Toggle("Hide consistency on Home", isOn: $preferences.hidden)
                }
                Section("Your consistency") {
                    if !original.reviewed {
                        Text("Home keeps your existing entry-based definition until you save this review.")
                    }
                    if hasHistory {
                        Text(preferences.paused ? "Display paused. Your diary stays intact." : "\(summary.count) qualifying days\(summary.reachedHistoryBoundary ? " or more" : "") in the loaded history")
                            .accessibilityIdentifier("logging_habit_count")
                    }
                    DisclosureGroup("How days are counted") {
                        Text("Today stays open until it qualifies. The current streak allows one missed day; a second miss ends it, even if separated. Grace days never add to the total. Resuming recalculates from your diary; pausing adds no entries or credits.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }
                Section("Recent calendar · last 46 days") {
                    Text("Loaded dates only. Imports and repeated entries count once per date. A partial or unreviewed day does not qualify for the fully logged rule.")
                    if hasHistory {
                        ForEach(summary.days.reversed()) { day in
                            HStack {
                                Text(day.date, format: .dateTime.month(.abbreviated).day())
                                Spacer()
                                Text(calendarLabel(day)).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    } else if error == nil { ProgressView() }
                }
                if let error { Section { Text(error).foregroundStyle(AppPalette.caution) } }
            }
            .appFormStyle()
            .navigationTitle("Logging consistency").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!loaded) }
            }
            .task { await load() }
        }
    }
    private func calendarLabel(_ day: LoggingHabitDay) -> String {
        let state = title(day.state)
        if day.isGraceDay { return day.state == .grace ? state : state + " · grace, not counted" }
        return state + (day.qualifiesForRule ? " · qualifies" : " · does not qualify")
    }
    private func title(_ state: LoggingHabitDay.State) -> String {
        switch state {
        case .entry: "Has an entry · not reviewed"
        case .complete: "Reviewed fully logged"
        case .partial: "Partly logged"
        case .open: "Still open"
        case .grace: "Grace day · not counted"
        case .noEntry: "No food entry in loaded diary"
        }
    }
    @MainActor private func load() async {
        guard let owner = DIContainer.shared.authService.currentUserID else { dismiss(); return }
        ownerID = owner
        do {
            original = try LoggingHabitStore().load(userID: owner); preferences = original; loaded = true
            let result = await dailyLogService.fetchDailyHistory(for: owner, startDate: start, endDate: Date())
            guard DIContainer.shared.authService.currentUserID == owner else { dismiss(); return }
            switch result {
            case .success(let values):
                logs = values
                if dailyLogService.isActiveAccount(owner), let current = dailyLogService.currentDailyLog {
                    logs.removeAll { Calendar.current.isDate($0.date, inSameDayAs: current.date) }; logs.append(current)
                }
                hasHistory = true
            case .failure(let failure): error = "History is unavailable. \(failure.localizedDescription)"
            }
        } catch { self.error = "Your saved preference could not be read and has been kept. \(error.localizedDescription)" }
    }
    private func save() {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { dismiss(); return }
        do {
            preferences.reviewed = true
            try LoggingHabitStore().save(preferences, expected: original, userID: ownerID)
            onSaved(preferences); dismiss()
        } catch { self.error = "This preference was not saved. \(error.localizedDescription)" }
    }
}
