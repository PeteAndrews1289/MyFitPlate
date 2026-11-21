import SwiftUI
import MyFitPlateCore

struct SetWaterGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var waterGoalInput: String
    @State private var baseline: Double?
    @State private var baselinePreferences: HydrationPreferences?
    @State private var preferences = HydrationPreferences()
    @State private var capturedUserID: String?
    @State private var trackingOnly = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var containerName = ""
    @State private var containerAmount = ""
    @State private var containerUnit: WaterVolumeUnit = .ounces
    @FocusState private var inputIsFocused: Bool
    var onAccepted: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Track without a daily target", isOn: $trackingOnly)
                        .accessibilityIdentifier("water_tracking_only")
                    if trackingOnly {
                        Text("Record drinks without a target, progress ring or target reminders.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Display unit", selection: Binding(get: { preferences.unit }, set: { new in
                        if let value = Double(waterGoalInput) { waterGoalInput = inputText(new.amount(fromOunces: preferences.unit.ounces(from: value))) }
                        preferences.unit = new
                    })) {
                        ForEach(WaterVolumeUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    if !trackingOnly {
                        HStack {
                            Text("Daily target")
                            Spacer(minLength: AppSpacing.compact)
                            TextField("Daily amount", text: $waterGoalInput).keyboardType(.decimalPad).focused($inputIsFocused)
                                .multilineTextAlignment(.trailing).frame(maxWidth: 90)
                            Text(preferences.unit.symbol).foregroundStyle(.secondary)
                        }.accessibilityIdentifier("water_target_amount")
                    }
                    Text("Changes start today. Past targets and logs stay intact. Containers and target history are saved on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Your containers") {
                    Picker("Quick-add container", selection: Binding(get: { preferences.preferredContainer?.id }, set: { preferences.preferredContainerID = $0 })) {
                        ForEach(preferences.containers) { Text($0.label).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("water_default_container")
                    ForEach(preferences.containers) { container in
                        HStack {
                            Text(container.label)
                            Spacer()
                            Button("Remove") {
                                preferences.containers.removeAll { $0.id == container.id }
                                if preferences.preferredContainerID == container.id { preferences.preferredContainerID = preferences.containers.first?.id }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
                Section("Add a container") {
                    TextField("Container name", text: $containerName).accessibilityIdentifier("water_container_name")
                    HStack {
                        TextField("Amount", text: $containerAmount).keyboardType(.decimalPad).accessibilityIdentifier("water_container_amount")
                        Picker("Container unit", selection: $containerUnit) { ForEach(WaterVolumeUnit.allCases) { Text($0.symbol).tag($0) } }.labelsHidden().accessibilityIdentifier("water_container_unit")
                    }
                    Button("Add container") {
                        guard let amount = Double(containerAmount) else { return }
                        let container = WaterContainer(name: containerName.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount, unit: containerUnit)
                        guard container.isValid else { return }
                        preferences.containers.append(container)
                        if preferences.preferredContainerID == nil { preferences.preferredContainerID = container.id }
                        containerName = ""; containerAmount = ""
                    }.disabled(!validContainer || preferences.containers.count >= 20).accessibilityIdentifier("water_add_container")
                }
                if !preferences.targetHistory.isEmpty {
                    Section {
                        DisclosureGroup("Target history · \(preferences.targetHistory.count)") {
                            ForEach(preferences.targetHistory.reversed()) { period in
                                LabeledContent(period.effectiveDay.formatted(date: .abbreviated, time: .omitted),
                                    value: period.targetOunces.map { "\(preferences.unit.amount(fromOunces: $0).formatted(.number.precision(.fractionLength(0...1)))) \(preferences.unit.symbol)" } ?? "Tracking only")
                            }
                        }
                    }
                }
                if let errorMessage = errorMessage ?? goalSettings.hydrationPreferenceNotice {
                    Text(errorMessage).foregroundStyle(AppPalette.critical).accessibilityIdentifier("settings_water_error")
                }
            }.appFormStyle()
            .disabled(isSaving)
            .navigationTitle("Water preferences").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputIsFocused = false } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(isSaving ? "Saving…" : "Save preferences", action: save)
                    .buttonStyle(AppActionButtonStyle(.primary)).disabled(!hasValidGoal || isSaving)
                    .padding().background(AppPalette.canvas).accessibilityIdentifier("settings_water_save")
            }
        }.interactiveDismissDisabled(isSaving).accessibilityIdentifier("settings_water_screen")
            .onAppear {
                guard baseline == nil else { return }
                baseline = goalSettings.waterGoal; baselinePreferences = goalSettings.hydrationPreferences
                preferences = goalSettings.hydrationPreferences; trackingOnly = preferences.isTrackingOnly
                waterGoalInput = inputText(preferences.unit.amount(fromOunces: goalSettings.waterGoal))
                capturedUserID = DIContainer.shared.authService.currentUserID
            }
    }
    private func inputText(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...2)))
    }
    private var validContainer: Bool {
        guard let amount = Double(containerAmount) else { return false }
        return WaterContainer(name: containerName, amount: amount, unit: containerUnit).isValid
    }
    private var hasValidGoal: Bool {
        trackingOnly || Double(waterGoalInput).map { (1...512).contains(preferences.unit.ounces(from: $0)) } == true
    }
    private func save() {
        inputIsFocused = false
        guard hasValidGoal, !isSaving, let baseline, let baselinePreferences, let capturedUserID else { return }
        do { try preferences.acceptTarget(trackingOnly ? nil : Double(waterGoalInput).map { preferences.unit.ounces(from: $0) }) } catch { errorMessage = error.localizedDescription; return }
        isSaving = true; errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await goalSettings.saveHydrationPreferences(preferences, baseline: baselinePreferences, baselineGoal: baseline, userID: capturedUserID)
                onAccepted()
            } catch {
                self.baseline = goalSettings.waterGoal
                errorMessage = error.localizedDescription
            }
        }
    }
}
