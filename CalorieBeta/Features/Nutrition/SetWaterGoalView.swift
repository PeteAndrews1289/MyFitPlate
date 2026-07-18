import SwiftUI

struct SetWaterGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var waterGoalInput: String
    @FocusState private var inputIsFocused: Bool
    var onSave: () -> Void

    private let presetGoals = [64, 80, 100, 128]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Hydration",
                        title: "Daily Water Goal",
                        subtitle: "Choose a target that matches the amount you want to track each day."
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Target",
                            subtitle: "Enter fluid ounces or choose a common target."
                        )

                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                            TextField("0", text: $waterGoalInput)
                                .keyboardType(.numberPad)
                                .appTextRole(.metric)
                                .foregroundStyle(AppPalette.text)
                                .monospacedDigit()
                                .focused($inputIsFocused)

                            Text("oz")
                                .appTextRole(.control)
                                .foregroundStyle(.secondary)
                        }
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }

                        if dynamicTypeSize.isAccessibilitySize {
                            Picker("Common target", selection: presetSelection) {
                                ForEach(presetGoals, id: \.self) { preset in
                                    Text("\(preset.formatted()) oz")
                                        .tag(Optional(preset))
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Picker("Common target", selection: presetSelection) {
                                ForEach(presetGoals, id: \.self) { preset in
                                    Text(preset.formatted())
                                        .tag(Optional(preset))
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Common water target")
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Water Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputIsFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save Goal") {
                    inputIsFocused = false
                    onSave()
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(!hasValidGoal)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.row)
                .padding(.bottom, AppSpacing.compact)
                .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppPalette.separator)
                        .frame(height: 1)
                }
                .accessibilityIdentifier("settings_water_save")
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("settings_water_screen")
    }

    private var presetSelection: Binding<Int?> {
        Binding(
            get: {
                guard let value = Int(waterGoalInput), presetGoals.contains(value) else { return nil }
                return value
            },
            set: { value in
                guard let value else { return }
                waterGoalInput = "\(value)"
            }
        )
    }

    private var hasValidGoal: Bool {
        guard let value = Double(waterGoalInput) else { return false }
        return (1...512).contains(value)
    }
}
