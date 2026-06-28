import SwiftUI

struct SettingsPreferencesSection: View {
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel
    @Binding var includeActiveCaloriesInGoal: Bool
    @Binding var hydrationRemindersEnabled: Bool
    @Binding var weighInReminderEnabled: Bool
    @Binding var notificationTimeBinding: Date

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
                            Text(healthKitViewModel.isAuthorized ? "Review Health Access & Sync" : "Connect to Apple Health")
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
                            title: "Include Active Calories",
                            subtitle: "Add exercise calories burned to your daily food allowance.",
                            color: .orange
                        )
                    }
                    .tint(.brandPrimary)
                    .padding(16)
                }
            }

            SettingsSectionCard(title: "Notifications") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsLabel(
                        icon: "bell.fill",
                        title: "Daily Log Reminder",
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
                            title: "Hydration Reminders",
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
                            title: "Weigh-In Reminder",
                            subtitle: "A morning nudge to log your weight.",
                            color: .accentPositive
                        )
                    }
                    .onChange(of: weighInReminderEnabled) { _, enabled in
                        NotificationManager.shared.setWeighInReminder(enabled: enabled)
                    }
                }
                .padding(16)
            }
        }
    }
}
