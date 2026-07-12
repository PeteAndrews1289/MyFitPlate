import SwiftUI
import MyFitPlateCore

struct SettingsPreferencesSection: View {
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
        VStack(spacing: 24) {
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
                                .appFont(size: 15, weight: .semibold)
                            Text(healthKitViewModel.isAuthorized ? "Refresh workouts, sleep, and recovery permissions." : "Import workouts and sleep where available.")
                                .appFont(size: 12)
                                .foregroundColor(Color(UIColor.secondaryLabel))
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
                            subtitle: "Add exercise calories burned to your daily food allowance.",
                            color: .orange
                        )
                    }
                    .tint(.blue)
                    .padding(16)
                }
            }

            SettingsSectionCard(title: "Notifications") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(
                        icon: "bell.fill",
                        title: "Daily log reminder",
                        subtitle: "Nightly check-in to log your meals.",
                        color: .orange
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
                            subtitle: "Gentle nudges to drink water through the day.",
                            color: .blue
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
                            subtitle: "A morning nudge to log your weight.",
                            color: .blue
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
                            subtitle: "Choose only the moments when a reminder would help.",
                            color: .orange
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
                            HStack {
                                Text("Quiet hours")
                                    .appFont(size: 14, weight: .semibold)
                                Spacer()
                                DatePicker("Start", selection: $quietStartBinding, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Text("to")
                                    .foregroundStyle(.secondary)
                                DatePicker("End", selection: $quietEndBinding, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            .onChange(of: quietStartBinding) { _, _ in postTrainingFuelPreferenceChange() }
                            .onChange(of: quietEndBinding) { _, _ in postTrainingFuelPreferenceChange() }

                            if eveningProteinRemindersEnabled {
                                HStack {
                                    Text("Evening reminder")
                                        .appFont(size: 14, weight: .semibold)
                                    Spacer()
                                    DatePicker(
                                        "Evening reminder",
                                        selection: $eveningProteinTimeBinding,
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }
                                .onChange(of: eveningProteinTimeBinding) { _, _ in postTrainingFuelPreferenceChange() }
                            }
                        }
                    }
                }
                .padding(16)
            }

            SettingsSectionCard(title: "Training") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLabel(
                        icon: "figure.strengthtraining.traditional",
                        title: "Set effort metric",
                        subtitle: "How you rate each set — RPE (how hard, 6–10) or RIR (reps left in the tank).",
                        color: .brandPrimary
                    )
                    Picker("Effort metric", selection: $liftingEffortMetric) {
                        Text("RPE").tag("rpe")
                        Text("RIR").tag("rir")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
            }

            SettingsSectionCard(title: "Maia") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsLabel(
                        icon: "sparkles",
                        title: "Assistant tone",
                        subtitle: "How Maia talks to you — Balanced, Coach (motivating), or Analyst (data-first).",
                        color: .brandPrimary
                    )
                    Picker("Assistant tone", selection: $goalSettings.maiaTone) {
                        Text("Balanced").tag("Balanced")
                        Text("Coach").tag("Coach")
                        Text("Analyst").tag("Analyst")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: goalSettings.maiaTone) { _, _ in
                        guard let userID = DIContainer.shared.authService.currentUserID else { return }
                        goalSettings.saveUserGoals(userID: userID)
                    }

                    Divider()

                    SettingsLabel(
                        icon: "waveform",
                        title: "Spoken voice",
                        subtitle: spokenVoiceSubtitle,
                        color: .blue
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
                                Text("\(voice.name) (\(voice.quality.label))")
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
                            .appFont(size: 14, weight: .semibold)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.brandPrimary)
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            ttsManager.refreshAvailableVoices()
        }
        .onDisappear {
            ttsManager.stopSpeaking()
        }
    }

    private var spokenVoiceSubtitle: String {
        guard let voice = ttsManager.selectedVoiceOption else {
            return "Uses the best English voice available on this iPhone."
        }
        if ttsManager.hasNaturalQualityVoice {
            return "\(voice.name) is a downloaded \(voice.quality.label.lowercased()) voice."
        }
        return "\(voice.name) is a standard system voice. Enhanced and Premium voices sound more natural."
    }

    private var trainingFuelRemindersEnabled: Bool {
        preSessionFuelRemindersEnabled || recoveryFuelRemindersEnabled || eveningProteinRemindersEnabled
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
