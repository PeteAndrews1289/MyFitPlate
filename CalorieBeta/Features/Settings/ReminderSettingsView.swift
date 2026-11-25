import SwiftUI
import MyFitPlateCore
import UserNotifications

struct ReminderSettingsView: View {
    @ObservedObject private var reminders = AccountReminderCoordinator.shared
    @State private var selection: ReminderKind?
    @State private var reviewingLegacy = false
    @State private var showingHistory = false
    @State private var didPresentScreenshotDestination = false

    var body: some View {
        SettingsSectionCard(title: "Reminders") {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                Text("A reminder for the moments that matter to you.")
                    .appTextRole(.secondary).foregroundStyle(.secondary).accessibilityIdentifier("settings_notifications")
                permissionStatus
                ForEach(ReminderKind.allCases) { kind in
                    Button { selection = kind } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.title).appTextRole(.control)
                                Text(summary(kind)).appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("reminder_settings_\(kind.rawValue)")
                    if kind != ReminderKind.allCases.last { Divider() }
                }
                Stepper("Daily limit: \(reminders.preferences.maximumPerDay.formatted()) reminders", value: Binding(
                    get: { reminders.preferences.maximumPerDay }, set: { count in
                        var value = reminders.preferences; value.maximumPerDay = count; _ = reminders.savePreferences(value)
                    }), in: 1...8)
                    .appTextRole(.secondary).accessibilityIdentifier("reminder_daily_budget")

                if reminders.hasLegacyPreferences {
                    Button("Review previous device settings") { reviewingLegacy = true }
                        .accessibilityIdentifier("reminder_review_legacy")
                    Text("Previous schedules have no verified account owner. Nothing is turned on until you review them here.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Button { showingHistory = true } label: {
                    HStack {
                        Label("Reminder history", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }.appTextRole(.control).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminder_history")
                if let error = reminders.errorMessage {
                    Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    Button("Retry refresh") { reminders.retry() }
                }
                DisclosureGroup("How reminders work") {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Text("Completed actions and pending local saves are checked when the app refreshes.")
                        Text("Training and fuel use at most two of the daily limit. Snoozes count too. Reservations remain counted for the day, even after a schedule changes.")
                        Text("Schedules cover the next seven days and refresh when the app is used. iOS controls delivery; Focus, permissions and changes while the app is closed can delay or suppress a reminder.")
                    }
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .padding(.top, AppSpacing.compact)
                }
                .appTextRole(.secondary)
            }.padding(AppSpacing.group)
        }
        .onAppear {
            reminders.activateAccount(DIContainer.shared.authService.currentUserID)
            reminders.refreshAuthorization()
            #if DEBUG
            if ScreenshotDemoMode.isEnabled, !didPresentScreenshotDestination {
                didPresentScreenshotDestination = true
                if ScreenshotDemoData.requestedScreen == "settings-reminder-editor" { selection = .dailyLog }
                if ScreenshotDemoData.requestedScreen == "settings-reminder-history" { showingHistory = true }
            }
            #endif
        }
        .sheet(item: $selection) { ReminderScheduleEditor(kind: $0, reminders: reminders) }
        .sheet(isPresented: $reviewingLegacy) { LegacyReminderReview(reminders: reminders) }
        .sheet(isPresented: $showingHistory) { ReminderHistoryView(reminders: reminders) }
    }

    @ViewBuilder private var permissionStatus: some View {
        switch reminders.authorization {
        case .denied:
            Label("Notifications are off in iOS Settings", systemImage: "bell.slash").appTextRole(.secondary)
            Button("Open iOS Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                .accessibilityIdentifier("reminder_permission_repair")
        case .notDetermined:
            Text("Your preferences are saved separately from notification permission.").appTextRole(.caption).foregroundStyle(.secondary)
            Button("Allow notifications") { reminders.requestPermission() }.accessibilityIdentifier("reminder_request_permission")
        default: Label("Notification permission enabled", systemImage: "bell").appTextRole(.caption).foregroundStyle(.secondary)
        }
    }
    private func summary(_ kind: ReminderKind) -> String {
        let value = reminders.preferences[kind]
        guard value.enabled else { return "Off" }
        if value.minutes.isEmpty { return "Session timing · \(value.weekdays.count) days each week" }
        return value.minutes.map { minute in
            (Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()).formatted(date: .omitted, time: .shortened)
        }.joined(separator: ", ")
    }
}

struct ReminderScheduleEditor: View {
    let kind: ReminderKind
    @ObservedObject var reminders: AccountReminderCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ReminderPreferences
    @State private var ownerID: String?
    init(kind: ReminderKind, reminders: AccountReminderCoordinator) {
        self.kind = kind; self.reminders = reminders
        _draft = State(initialValue: reminders.preferences); _ownerID = State(initialValue: reminders.ownerID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable \(kind.title.lowercased())", isOn: Binding(get: { draft[kind].enabled }, set: { draft[kind].enabled = $0 }))
                        .accessibilityIdentifier("reminder_enabled")
                    if kind == .dailyLog {
                        Picker("Remind me until", selection: $draft.diaryRule) {
                            Text("Any food is logged").tag(ReminderPreferences.DiaryRule.anyFood)
                            Text("The day is reviewed complete").tag(ReminderPreferences.DiaryRule.completeDay)
                        }.accessibilityIdentifier("reminder_diary_rule")
                    }
                    if kind == .experimentCheckIn {
                        Text("Offers one check-in after an exact, recorded comparison workout, while its trial is still unanswered and less than two days old. This is optional; nothing is enabled by starting a comparison.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if kind == .beforeTraining || kind == .recovery {
                        Text(kind == .beforeTraining ? "Uses the timing of your reviewed, current fuel plan." : "Only after recorded session completion and a current recovery target.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    ForEach(draft[kind].minutes.indices, id: \.self) { index in
                        DatePicker("Time \(index + 1)", selection: minuteBinding(index), displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("reminder_time_\(index)")
                    }
                }
                Section("Days") {
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { day in
                            let selected = draft[kind].weekdays.contains(day)
                            Button {
                                if selected { draft[kind].weekdays.remove(day) } else { draft[kind].weekdays.insert(day) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .appTextRole(.control)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? AppPalette.brandText : AppPalette.text)
                                    .background(selected ? AppPalette.brand.opacity(0.12) : AppPalette.surface,
                                                in: RoundedRectangle(cornerRadius: AppRadius.control))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: AppRadius.control)
                                            .strokeBorder(selected ? AppPalette.brand.opacity(0.4) : Color.clear)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                            .accessibilityIdentifier("reminder_weekday_\(day)")
                        }
                    }
                    Text(draft[kind].weekdays.count == 7 ? "Every day" : "\(draft[kind].weekdays.count) days selected")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Quiet hours") {
                    DatePicker("Start", selection: quietBinding(start: true), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("reminder_quiet_start")
                    DatePicker("End", selection: quietBinding(start: false), displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("reminder_quiet_end")
                    Text("Matching start and end times disables quiet hours. Reminders inside quiet hours are suppressed, not moved.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
                Section("Preview") {
                    Text(kind.title).appTextRole(.control)
                    Text("Opens the relevant day or reviewed session. Mark handled stops this task without inventing a log; snooze is checked against the current window and daily limit.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    if let error = reminders.errorMessage { Text(error).foregroundStyle(AppPalette.caution) }
                }
            }
            .appFormStyle()
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard ownerID == reminders.ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
                        if reminders.savePreferences(draft) { dismiss() }
                    }.disabled(!draft.isValid).accessibilityIdentifier("reminder_save")
                }
            }
        }
    }
    private func minuteBinding(_ index: Int) -> Binding<Date> {
        Binding(get: { date(draft[kind].minutes[index]) }, set: { draft[kind].minutes[index] = minute($0) })
    }
    private func quietBinding(start: Bool) -> Binding<Date> {
        Binding(get: { date(start ? draft[kind].quietStart : draft[kind].quietEnd) }, set: {
            if start { draft[kind].quietStart = minute($0) } else { draft[kind].quietEnd = minute($0) }
        })
    }
    private func date(_ minute: Int) -> Date { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() }
    private func minute(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) }
}

private struct LegacyReminderReview: View {
    @ObservedObject var reminders: AccountReminderCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("These are previous device preferences with no verified account owner. Apply only if you want them for the account signed in now.")
                if let previous = reminders.legacyPreferences() {
                    ForEach(ReminderKind.allCases) { kind in LabeledContent(kind.title, value: previous[kind].enabled ? "On" : "Off") }
                    Button("Use these settings") {
                        var value = previous; value.legacyReviewCompleted = true
                        if reminders.savePreferences(value) { dismiss() }
                    }.accessibilityIdentifier("reminder_adopt_legacy")
                }
                Button("Keep current settings") {
                    var value = reminders.preferences; value.legacyReviewCompleted = true
                    if reminders.savePreferences(value) { dismiss() }
                }
            }.appFormStyle().navigationTitle("Review previous settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct ReminderHistoryView: View {
    @ObservedObject var reminders: AccountReminderCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("Local scheduling decisions for this account. Scheduled does not mean delivered; delivery is shown only when iOS reports it in Notification Center.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                if reminders.decisions.isEmpty {
                    ContentUnavailableView("No reminder history yet", systemImage: "bell.badge",
                        description: Text("Choose a reminder schedule to see its next review here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(reminders.decisions.prefix(100)) { decision in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(decision.candidate.title).appTextRole(.control)
                        Text(decision.candidate.fireDate.formatted(date: .abbreviated, time: .shortened)).appTextRole(.caption)
                        Text(decision.state.label).appTextRole(.secondary)
                        Text(decision.reason).appTextRole(.caption).foregroundStyle(.secondary)
                        if decision.candidate.target.expiresAt > Date(), decision.state == .scheduled {
                            HStack {
                                Button("Snooze 20 min") { respond(decision, action: AccountReminderCoordinator.snoozeAction) }
                                Button("Mark handled") { respond(decision, action: AccountReminderCoordinator.handledAction) }
                            }.buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 4)
                }
            }.appFormStyle().navigationTitle("Reminder history").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.accessibilityIdentifier("reminder_history_screen")
    }
    private func respond(_ value: ReminderDecision, action: String) {
        Task { _ = await reminders.respond(identifier: value.id, fingerprint: value.candidate.fingerprint, action: action) }
    }
}

struct FuelReminderPlanControls: View {
    let plan: TrainingFuelConfirmedPlan
    let ownerID: String?
    @EnvironmentObject private var fuelStore: TrainingFuelPlanStore
    @ObservedObject private var reminders = AccountReminderCoordinator.shared
    @State private var showingSettings = false
    var body: some View {
        Button { showingSettings = true } label: {
            Label("Review reminders", systemImage: "bell").appTextRole(.secondary).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityIdentifier("fuel_plan_reminders")
            .disabled(ownerID != DIContainer.shared.authService.currentUserID || plan.ownerID != ownerID
                || fuelStore.conflictingPlanIDs.contains(plan.id)
                || !fuelStore.history.contains(where: { $0.plan.id == plan.id && $0.id == plan.revisionID && $0.archivedAt == nil }))
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    ScrollView { ReminderSettingsView().padding(AppSpacing.group) }
                        .navigationTitle("Training reminders").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } }
                }
            }
    }
}
