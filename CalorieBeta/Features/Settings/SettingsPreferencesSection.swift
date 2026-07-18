import SwiftUI
import MyFitPlateCore

struct SettingsPreferencesSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var includeActiveCaloriesInGoal: Bool
    @Binding var hydrationRemindersEnabled: Bool
    @Binding var weighInReminderEnabled: Bool
    @Binding var notificationTimeBinding: Date
    @Binding var preSessionFuelRemindersEnabled: Bool
    @Binding var recoveryFuelRemindersEnabled: Bool
    @Binding var eveningProteinRemindersEnabled: Bool
    @Binding var quietStartBinding: Date
    @Binding var quietEndBinding: Date
    @Binding var eveningProteinTimeBinding: Date

    @AppStorage("liftingEffortMetric") private var liftingEffortMetric: String = "rpe"
    @StateObject private var ttsManager = TTSManager.shared

    var body: some View {
        VStack(spacing: AppSpacing.section) {
            SettingsSectionCard(title: "Integrations") {
                Button(action: {
                    healthKitViewModel.requestAuthorization()
                }) {
                    HStack {
                        Image("Apple_Health")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthKitViewModel.isAuthorized ? "Review Health access" : "Connect Apple Health")
                                .appTextRole(.control)
                            Text(healthKitViewModel.isAuthorized ? "Refresh workouts, sleep, and recovery permissions." : "Import workouts and sleep where available.")
                                .appTextRole(.secondary)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        if healthKitViewModel.isSyncing {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else if healthKitViewModel.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentPositive)
                        }
                    }
                }
                .foregroundColor(.textPrimary)
                .disabled(healthKitViewModel.isSyncing)
                .opacity(healthKitViewModel.isSyncing ? 0.55 : 1.0)
                .padding(16)
                
                if healthKitViewModel.isAuthorized {
                    Divider().padding(.leading, 50)
                    Toggle(isOn: $includeActiveCaloriesInGoal) {
                        SettingsLabel(
                            icon: "flame.fill",
                            title: "Include active calories",
                            subtitle: "Add exercise calories burned to your daily food allowance."
                        )
                    }
                    .padding(AppSpacing.group)
                }
            }
            .accessibilityIdentifier("settings_integrations")

            SettingsSectionCard(title: "Notifications") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(
                        icon: "bell.fill",
                        title: "Daily log reminder",
                        subtitle: "Nightly check-in to log your meals."
                    )
                    DatePicker("", selection: $notificationTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: notificationTimeBinding) { _, _ in
                            NotificationManager.shared.scheduleDailyLogReminderIfAuthorized()
                        }

                    Divider()

                    Toggle(isOn: $hydrationRemindersEnabled) {
                        SettingsLabel(
                            icon: "drop.fill",
                            title: "Hydration reminders",
                            subtitle: "Gentle nudges to drink water through the day."
                        )
                    }
                    .onChange(of: hydrationRemindersEnabled) { _, enabled in
                        NotificationManager.shared.setHydrationReminders(enabled: enabled)
                    }

                    Divider()

                    Toggle(isOn: $weighInReminderEnabled) {
                        SettingsLabel(
                            icon: "scalemass.fill",
                            title: "Weigh-in reminder",
                            subtitle: "A morning nudge to log your weight."
                        )
                    }
                    .onChange(of: weighInReminderEnabled) { _, enabled in
                        NotificationManager.shared.setWeighInReminder(enabled: enabled)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsLabel(
                            icon: "bolt.fill",
                            title: "Training & Fuel",
                            subtitle: "Choose only the moments when a reminder would help."
                        )

                        Toggle("Before training", isOn: $preSessionFuelRemindersEnabled)
                            .onChange(of: preSessionFuelRemindersEnabled) { _, enabled in
                                trainingFuelPreferenceChanged(requestPermission: enabled)
                            }
                        Toggle("Recovery target", isOn: $recoveryFuelRemindersEnabled)
                            .onChange(of: recoveryFuelRemindersEnabled) { _, enabled in
                                trainingFuelPreferenceChanged(requestPermission: enabled)
                            }
                        Toggle("Evening protein catch-up", isOn: $eveningProteinRemindersEnabled)
                            .onChange(of: eveningProteinRemindersEnabled) { _, enabled in
                                trainingFuelPreferenceChanged(requestPermission: enabled)
                            }

                        if trainingFuelRemindersEnabled {
                            Divider()
                            quietHoursControls
                            .onChange(of: quietStartBinding) { _, _ in
                                if quietHoursAreValid { postTrainingFuelPreferenceChange() }
                            }
                            .onChange(of: quietEndBinding) { _, _ in
                                if quietHoursAreValid { postTrainingFuelPreferenceChange() }
                            }

                            Label(quietHoursStatusText, systemImage: quietHoursAreValid ? "moon.zzz" : "exclamationmark.triangle")
                                .appTextRole(.caption)
                                .foregroundStyle(quietHoursAreValid ? Color.secondary : AppPalette.caution)
                                .fixedSize(horizontal: false, vertical: true)

                            if eveningProteinRemindersEnabled {
                                eveningReminderControl
                                .onChange(of: eveningProteinTimeBinding) { _, _ in postTrainingFuelPreferenceChange() }
                            }
                        }
                    }
                }
                .padding(AppSpacing.group)
            }
            .accessibilityIdentifier("settings_notifications")

            SettingsSectionCard(title: "Training") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLabel(
                        icon: "figure.strengthtraining.traditional",
                        title: "Set effort metric",
                        subtitle: "Choose RPE for effort from 6 to 10, or RIR for reps left in the tank."
                    )
                    effortPicker
                }
                .padding(AppSpacing.group)
            }
            .accessibilityIdentifier("settings_training")

            SettingsSectionCard(title: "Maia") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLabel(
                        icon: "sparkles",
                        title: "Assistant tone",
                        subtitle: "Choose Balanced, motivating Coach, or data-first Analyst."
                    )
                    tonePicker
                    .onChange(of: goalSettings.maiaTone) { _, _ in
                        guard let userID = DIContainer.shared.authService.currentUserID else { return }
                        goalSettings.saveUserGoals(userID: userID)
                    }

                    Divider()

                    SettingsLabel(
                        icon: "waveform",
                        title: "Spoken voice",
                        subtitle: spokenVoiceSubtitle
                    )

                    if !ttsManager.availableVoices.isEmpty {
                        Picker(
                            "Spoken voice",
                            selection: Binding(
                                get: { ttsManager.selectedVoiceIdentifier },
                                set: { ttsManager.selectVoice(identifier: $0) }
                            )
                        ) {
                            ForEach(ttsManager.availableVoices) { voice in
                                Text(voice.pickerLabel)
                                    .tag(voice.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            if ttsManager.isSpeaking {
                                ttsManager.stopSpeaking()
                            } else {
                                ttsManager.previewSelectedVoice()
                            }
                        } label: {
                            Label(
                                ttsManager.isSpeaking ? "Stop Preview" : "Preview Voice",
                                systemImage: ttsManager.isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                            )
                        }
                        .buttonStyle(AppActionButtonStyle(.secondary))
                    }
                }
                .padding(AppSpacing.group)
            }
            .accessibilityIdentifier("settings_maia")
        }
        .tint(AppPalette.brand)
        .onAppear {
            ttsManager.refreshAvailableVoices()
        }
        .onDisappear {
            ttsManager.stopSpeaking()
        }
    }

    private var spokenVoiceSubtitle: String {
        guard let voice = ttsManager.selectedVoiceOption else {
            return "Uses the best natural voice currently installed on this iPhone."
        }
        if voice.isOnline {
            return "AI-generated online voice with a local iPhone voice fallback when unavailable."
        }
        if ttsManager.hasNaturalQualityVoice {
            return "\(voice.name) · \(voice.accentLabel) · downloaded \(voice.quality.label.lowercased()) quality."
        }
        return "\(voice.name) · \(voice.accentLabel). Download an Enhanced or Premium voice in Accessibility > Spoken Content for a more natural result."
    }

    @ViewBuilder
    private var quietHoursControls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Text("Quiet hours")
                    .appTextRole(.control)
                DatePicker("Starts", selection: $quietStartBinding, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $quietEndBinding, displayedComponents: .hourAndMinute)
            }
        } else {
            HStack(spacing: AppSpacing.compact) {
                Text("Quiet hours")
                    .appTextRole(.control)
                Spacer(minLength: AppSpacing.compact)
                DatePicker("Start", selection: $quietStartBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("to")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                DatePicker("End", selection: $quietEndBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var eveningReminderControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            DatePicker(
                "Evening reminder",
                selection: $eveningProteinTimeBinding,
                displayedComponents: .hourAndMinute
            )
        } else {
            HStack {
                Text("Evening reminder")
                    .appTextRole(.control)
                Spacer()
                DatePicker(
                    "Evening reminder",
                    selection: $eveningProteinTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var effortPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Effort metric", selection: $liftingEffortMetric) {
                Text("RPE").tag("rpe")
                Text("RIR").tag("rir")
            }
            .pickerStyle(.menu)
        } else {
            Picker("Effort metric", selection: $liftingEffortMetric) {
                Text("RPE").tag("rpe")
                Text("RIR").tag("rir")
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var tonePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Assistant tone", selection: $goalSettings.maiaTone) {
                Text("Balanced").tag("Balanced")
                Text("Coach").tag("Coach")
                Text("Analyst").tag("Analyst")
            }
            .pickerStyle(.menu)
        } else {
            Picker("Assistant tone", selection: $goalSettings.maiaTone) {
                Text("Balanced").tag("Balanced")
                Text("Coach").tag("Coach")
                Text("Analyst").tag("Analyst")
            }
            .pickerStyle(.segmented)
        }
    }

    private var trainingFuelRemindersEnabled: Bool {
        preSessionFuelRemindersEnabled || recoveryFuelRemindersEnabled || eveningProteinRemindersEnabled
    }

    private var quietHoursAreValid: Bool {
        minuteOfDay(quietStartBinding) != minuteOfDay(quietEndBinding)
    }

    private var quietHoursStatusText: String {
        guard quietHoursAreValid else {
            return "Choose different start and end times so quiet hours can take effect."
        }
        let start = quietStartBinding.formatted(date: .omitted, time: .shortened)
        let end = quietEndBinding.formatted(date: .omitted, time: .shortened)
        return "Training reminders stay quiet from \(start) to \(end), including overnight."
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func trainingFuelPreferenceChanged(requestPermission: Bool) {
        guard requestPermission else {
            postTrainingFuelPreferenceChange()
            return
        }
        NotificationManager.shared.requestAuthorization { _ in
            postTrainingFuelPreferenceChange()
        }
    }

    private func postTrainingFuelPreferenceChange() {
        NotificationManager.shared.cancelTrainingFuelNotifications()
        NotificationCenter.default.post(name: .trainingFuelNotificationPreferencesChanged, object: nil)
    }
}
