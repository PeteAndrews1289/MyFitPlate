import SwiftUI

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
    @FocusState private var focusedField: HeightField?
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    AppScreenHeader(
                        eyebrow: "Personal Details",
                        title: "Height",
                        subtitle: "Height helps calculate energy needs and keeps body metrics consistent."
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        AppSectionHeader(
                            title: "Current Height",
                            subtitle: useMetric ? "Enter centimeters." : "Enter feet and inches."
                        )

                        heightFields
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
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save Height", action: save)
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!hasValidHeight)
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
                if useMetric {
                    cmInput = String(Int(goalSettings.height.rounded()))
                }
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityIdentifier("settings_height_screen")
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
        if useMetric, let centimeters = Double(cmInput) {
            let totalInches = Int((centimeters / BodyUnits.cmPerInch).rounded())
            feetInput = String(totalInches / 12)
            inchesInput = String(totalInches % 12)
        }
        onSave()
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
