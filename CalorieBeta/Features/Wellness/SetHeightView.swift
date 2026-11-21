import SwiftUI
import MyFitPlateCore

private enum HeightField: Hashable {
    case centimeters
    case feet
    case inches
}

struct SetHeightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Binding var feetInput: String
    @Binding var inchesInput: String
    @State private var cmInput: String = ""
    @State private var baseline: GoalEditorDraft?
    @State private var capturedUserID: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: HeightField?
    var onAccepted: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Text("Used to estimate energy needs and body metrics.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Your height",
                            subtitle: useMetric ? "Enter centimeters." : "Enter feet and inches."
                        )

                        heightFields.disabled(isSaving)
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(AppPalette.critical)
                                .accessibilityIdentifier("settings_height_error")
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.group)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(isSaving ? "Saving…" : "Save height", action: save)
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!hasValidHeight || isSaving)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.row)
                    .padding(.bottom, AppSpacing.compact)
                    .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppPalette.separator)
                            .frame(height: 1)
                    }
                    .accessibilityIdentifier("settings_height_save")
            }
            .onAppear {
                guard baseline == nil else { return }
                baseline = goalSettings.makeGoalEditorDraft()
                capturedUserID = DIContainer.shared.authService.currentUserID
                if useMetric {
                    cmInput = String(goalSettings.height)
                }
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("settings_height_screen")
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var heightFields: some View {
        if useMetric {
            HeightInputCard(
                title: "Height",
                value: $cmInput,
                unit: "cm",
                field: .centimeters,
                focusedField: $focusedField
            )
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.row) {
                imperialFields
            }
        } else {
            HStack(spacing: AppSpacing.row) {
                imperialFields
            }
        }
    }

    @ViewBuilder
    private var imperialFields: some View {
        HeightInputCard(
            title: "Feet",
            value: $feetInput,
            unit: "ft",
            field: .feet,
            focusedField: $focusedField
        )
        HeightInputCard(
            title: "Inches",
            value: $inchesInput,
            unit: "in",
            field: .inches,
            focusedField: $focusedField
        )
    }

    private var hasValidHeight: Bool {
        if useMetric {
            guard let centimeters = Double(cmInput) else { return false }
            return (90...250).contains(centimeters)
        }

        guard let feet = Int(feetInput), let inches = Int(inchesInput) else { return false }
        return (3...8).contains(feet) && (0...11).contains(inches)
    }

    private func save() {
        focusedField = nil
        guard hasValidHeight, !isSaving, let baseline, let capturedUserID else { return }
        let centimeters: Double
        if useMetric, let value = Double(cmInput) {
            centimeters = value
        } else if let feet = Double(feetInput), let inches = Double(inchesInput) {
            centimeters = (feet * 12 + inches) * BodyUnits.cmPerInch
        } else { return }
        var proposal = baseline
        proposal.height = centimeters
        isSaving = true; errorMessage = nil
        Task { @MainActor in
            do {
                try await goalSettings.saveGoalEditorDraft(proposal, baseline: baseline, userID: capturedUserID)
                isSaving = false
                onAccepted()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct HeightInputCard: View {
    let title: String
    @Binding var value: String
    let unit: String
    let field: HeightField
    let focusedField: FocusState<HeightField?>.Binding
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(title)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .appTextRole(.metric)
                    .foregroundStyle(AppPalette.text)
                    .monospacedDigit()
                    .focused(focusedField, equals: field)
                
                Text(unit)
                    .appTextRole(.control)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.group)
        .frame(maxWidth: .infinity)
        .background(
            AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
    }
}
