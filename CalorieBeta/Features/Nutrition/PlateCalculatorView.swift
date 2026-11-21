import MyFitPlateCore
import SwiftUI

private struct PlateCalculatorSelection: Codable {
    let reference: StrengthGymProfileReference?
}

struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var targetFieldIsFocused: Bool

    @State private var targetWeight: String
    @State private var canonicalTarget: Double?
    @State private var renderedTarget = ""
    @State private var displayUnit: StrengthEquipment.Unit
    @State private var selectedEquipment: StrengthEquipment?
    @State private var showingGyms = false
    @State private var selectionNotice: String?
    @State private var restoredSelection = false
    private let initialEquipment: StrengthEquipment?
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    private let locksTarget: Bool

    /// Initial targets, like historical sets, are always canonical pounds.
    init(initialTargetWeight: Double? = nil, locksTarget: Bool = false, equipment: StrengthEquipment? = nil) {
        let validEquipment = equipment?.isValid == true ? equipment : nil
        let unit = validEquipment?.unit ?? .lb
        let text = initialTargetWeight.map { Self.weightText(unit.displayWeight($0)) } ?? ""
        _targetWeight = State(initialValue: text)
        _renderedTarget = State(initialValue: text)
        _canonicalTarget = State(initialValue: initialTargetWeight)
        _selectedEquipment = State(initialValue: validEquipment)
        _displayUnit = State(initialValue: unit)
        initialEquipment = validEquipment
        self.locksTarget = locksTarget
    }

    private var parsedTarget: Double? { canonicalTarget }
    private var minimumWeight: Double { selectedEquipment?.attainableLoads.first ?? PlateLoadingRules.standardBarWeight }
    private var unitLabel: String { displayUnit.rawValue }

    private var loadout: PlateLoadout? {
        guard let parsedTarget else { return nil }
        if let equipment = selectedEquipment {
            guard equipment.kind == .barbell,
                  let loaded = equipment.attainableLoads.last(where: { $0 <= parsedTarget + 0.000001 }),
                  let pairs = equipment.platePairs(for: loaded) else { return nil }
            let plates = Dictionary(grouping: pairs, by: { $0 }).map { PlateLoad(weight: $0.key, countPerSide: $0.value.count) }
                .sorted { $0.weight > $1.weight }
            return PlateLoadout(targetWeight: parsedTarget, barWeight: equipment.barWeight, loadedWeight: loaded,
                difference: max(0, parsedTarget - loaded), platesPerSide: plates)
        }
        return PlateLoadingRules.loadout(targetWeight: parsedTarget)
    }

    var body: some View {
        NavigationStack {
            AppSheetScaffold(
                title: "Plate Loading",
                subtitle: selectedEquipment?.gymProfile.map { "\($0.profileName) · \($0.implementName)" }
                    ?? selectedEquipment?.name ?? "Standard 45 lb bar preset",
                dismiss: { dismiss() }
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.section) {
                        targetSection
                        resultSection
                        equipmentSection
                        methodNote
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.vertical, AppSpacing.group)
                }
                .scrollDismissesKeyboard(.interactively)
                .dynamicTypeSize(dynamicTypeSize)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plate_calculator_content")
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { targetFieldIsFocused = false }.accessibilityIdentifier("plate_calculator_keyboard_done")
                }
            }
            .sheet(isPresented: $showingGyms) {
                StrengthGymEquipmentPickerView { equipment in chooseEquipment(equipment) }
            }
            .onAppear(perform: restoreLastSelection)
            .onChange(of: targetWeight) { _, value in
                guard value != renderedTarget else { return }
                canonicalTarget = Double(value.replacingOccurrences(of: ",", with: "."))
                    .map { displayUnit.storedWeight($0) }
                renderedTarget = value
            }
            .onChange(of: displayUnit) { _, _ in setTarget(canonicalTarget) }
            .onChange(of: DIContainer.shared.authService.currentUserID) { _, value in
                guard value != ownerID else { return }
                selectedEquipment = nil; displayUnit = .lb
                selectionNotice = "The account changed. Close this calculator and reopen it to choose that account's gym profiles."
            }
        }
        .tint(AppPalette.brand)
        .background(AppPalette.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plate_calculator_screen")
    }

    @ViewBuilder
    private var targetSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Target Weight",
                subtitle: locksTarget
                    ? "Using the weight entered for this set."
                    : selectedEquipment?.kind == .fixedWeights ? "Enter a load using this implement's displayed convention."
                        : "Enter the total weight, including the bar."
            )

            if locksTarget {
                HStack(alignment: .firstTextBaseline) {
                    Text(parsedTarget.map(displayText) ?? "--")
                        .appTextRole(.metric)
                        .monospacedDigit()
                    Text(unitLabel)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .appSurface(.emphasized)
            } else {
                HStack(spacing: AppSpacing.row) {
                    Button(action: { adjustTarget(by: -5) }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .disabled((parsedTarget ?? 0) <= minimumWeight)
                    .accessibilityLabel(selectedEquipment == nil ? "Decrease target by 5 pounds" : "Previous attainable load")

                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        TextField(displayUnit == .lb ? "225" : "100", text: $targetWeight)
                            .keyboardType(.decimalPad)
                            .appTextRole(.metric)
                            .monospacedDigit()
                            .focused($targetFieldIsFocused)
                            .accessibilityLabel("Target weight in \(unitLabel)")
                            .accessibilityIdentifier("plate_calculator_input")

                        Text(unitLabel)
                            .appTextRole(.control)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, AppSpacing.group)
                    .frame(minHeight: 52)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control)
                            .stroke(AppPalette.separator, lineWidth: 1)
                    }

                    Button(action: { adjustTarget(by: 5) }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .accessibilityLabel(selectedEquipment == nil ? "Increase target by 5 pounds" : "Next attainable load")
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if targetWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            calculatorMessage(
                icon: "circle.grid.cross",
                title: "Enter a Target",
                message: "The loadout will show the plates needed on each side."
            )
        } else if let target = parsedTarget,
                  target < minimumWeight ||
                  target > PlateLoadingRules.maximumSupportedWeight ||
                  !target.isFinite {
            calculatorMessage(
                icon: "exclamationmark.triangle.fill",
                title: "Check the Weight",
                message: "Use a load between \(displayText(minimumWeight)) and \(displayText(PlateLoadingRules.maximumSupportedWeight)) \(unitLabel)."
            )
        } else if let equipment = selectedEquipment, equipment.kind == .fixedWeights,
                  let target = parsedTarget, let loaded = equipment.attainableLoads.last(where: { $0 <= target + 0.000001 }) {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                summary(target: target, loaded: loaded, exact: abs(target - loaded) < 0.001)
                Text("\(equipment.loadingMeaning.title) · \(displayText(loaded)) \(unitLabel)")
                    .appTextRole(.control).accessibilityIdentifier("plate_calculator_fixed_load")
                Text(abs(target - loaded) < 0.001 ? "This load is listed in the selected implement."
                    : "The lower available load is shown. Review an alternative before changing your target.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                availableAlternatives(equipment, target: target)
            }
        } else if let loadout {
            loadoutContent(loadout)
        } else {
            calculatorMessage(
                icon: "exclamationmark.triangle.fill",
                title: "Check the Weight",
                message: "Enter a numeric load in \(unitLabel). The equipment selection below establishes the bar or available weights."
            )
        }
    }

    private func loadoutContent(_ loadout: PlateLoadout) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            summary(target: loadout.targetWeight, loaded: loadout.loadedWeight, exact: loadout.isExact)

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Plates Per Side",
                    subtitle: loadout.isExact
                        ? "The requested weight can be loaded exactly."
                        : "The lower supported load is shown; review the difference before changing your target."
                )
                Text("Bar · \(displayText(loadout.barWeight)) \(unitLabel)")
                    .appTextRole(.secondary).accessibilityIdentifier("plate_calculator_bar")

                if loadout.platesPerSide.isEmpty {
                    calculatorMessage(
                        icon: "minus",
                        title: "Bar Only",
                        message: "No plates are needed for a \(displayText(loadout.barWeight)) \(unitLabel) total."
                    )
                } else {
                    PlateLoadDiagram(loadout: loadout, unit: displayUnit)

                    VStack(spacing: 0) {
                        ForEach(Array(loadout.platesPerSide.enumerated()), id: \.element.id) { index, plate in
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.group) {
                                Circle()
                                    .fill(PlateLoadDiagram.color(for: plate.weight))
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)

                                Text("\(displayText(plate.weight)) \(unitLabel) plate")
                                    .appTextRole(.control)
                                    .foregroundStyle(AppPalette.text)

                                Spacer(minLength: AppSpacing.compact)

                                Text("\(plate.countPerSide.formatted()) per side")
                                    .appTextRole(.control)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, AppSpacing.group)
                            .padding(.vertical, AppSpacing.row)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(plate.countPerSide) \(displayText(plate.weight)) \(unitLabel) " +
                                "\(plate.countPerSide == 1 ? "plate" : "plates") per side"
                            )

                            if index < loadout.platesPerSide.count - 1 {
                                Divider().padding(.leading, AppSpacing.group)
                            }
                        }
                    }
                    .appSurface(.quiet, padding: 0)
                    .accessibilityIdentifier("plate_calculator_loadout")
                }
                if let equipment = selectedEquipment, !loadout.isExact {
                    availableAlternatives(equipment, target: loadout.targetWeight)
                }
            }
        }
    }

    private func summary(target: Double, loaded: Double, exact: Bool) -> some View {
        AppMetricStrip(items: [
            AppMetricItem(label: "Target", value: "\(displayText(target)) \(unitLabel)", accent: AppPalette.brand),
            AppMetricItem(label: "Loaded", value: "\(displayText(loaded)) \(unitLabel)", accent: AppPalette.effort),
            AppMetricItem(label: "Fit", value: exact ? "Exact" : "\(displayText(max(0, target - loaded))) \(unitLabel) under",
                accent: exact ? .accentPositive : AppPalette.caution)
        ])
        .appSurface(.emphasized)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plate_calculator_summary")
    }

    private func availableAlternatives(_ equipment: StrengthEquipment, target: Double) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text("Available alternatives").appTextRole(.control)
            let loads = equipment.attainableLoads
            ForEach([loads.last(where: { $0 <= target + 0.000001 }), loads.first(where: { $0 > target + 0.000001 })].compactMap { $0 }, id: \.self) { load in
                Button("Use \(displayText(load)) \(unitLabel) in calculator") { setTarget(load) }
                    .frame(minHeight: 44).buttonStyle(AppActionButtonStyle(.secondary))
            }
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Equipment", subtitle: "This selection is used only in the calculator.")
            Text(selectedEquipment.map { equipment in
                equipment.gymProfile.map { "\($0.profileName) · \($0.implementName)" } ?? equipment.name ?? equipment.kind.title
            } ?? "Standard 45 lb preset")
            .appTextRole(.control).accessibilityIdentifier("plate_calculator_equipment")
            Button("Choose saved gym or implement") { targetFieldIsFocused = false; showingGyms = true }
                .buttonStyle(AppActionButtonStyle(.secondary)).frame(minHeight: 44)
                .disabled(ownerID == nil || ownerID != DIContainer.shared.authService.currentUserID)
                .accessibilityIdentifier("plate_calculator_choose_gym")
            if selectedEquipment != nil || selectionNotice != nil {
                Button {
                    selectedEquipment = nil; selectionNotice = nil; persistSelection()
                } label: {
                    Text("Use standard 45 lb preset")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(AppPalette.brandText)
                .accessibilityIdentifier("plate_calculator_standard")
            }
            Picker("Display units", selection: $displayUnit) {
                ForEach(StrengthEquipment.Unit.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("plate_calculator_units")
            DisclosureGroup("Equipment details") {
                if let selectedEquipment {
                    Text(equipmentSummary(selectedEquipment)).appTextRole(.secondary).foregroundStyle(.secondary)
                } else {
                    Text("Assumes a 45 lb bar and standard plate sizes with unlimited matching pairs. This preset does not describe a saved gym.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
            }
            .appTextRole(.secondary)
            if let selectionNotice {
                Text(selectionNotice).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    .accessibilityIdentifier("plate_calculator_selection_notice")
            }
        }
        .appSurface(.quiet)
    }

    private func chooseEquipment(_ equipment: StrengthEquipment) {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID,
              let reference = equipment.gymProfile else { selectionNotice = "Reopen this calculator in the account that owns the gym."; return }
        do {
            guard let profile = try StrengthGymProfileStore().profiles(userID: ownerID).first(where: { $0.id == reference.profileID }),
                  profile.revisionID == reference.revisionID, profile.equipment(for: reference.implementID) == equipment else {
                throw StrengthSessionToolsError.changed
            }
            selectedEquipment = equipment; displayUnit = equipment.unit; setTarget(canonicalTarget)
            selectionNotice = nil; persistSelection()
        } catch { selectionNotice = error.localizedDescription }
    }

    private func persistSelection() {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            try EditorDraftStore().save(PlateCalculatorSelection(reference: selectedEquipment?.gymProfile),
                userID: ownerID, scope: "plate-calculator-last-equipment")
        } catch { selectionNotice = "This calculation is ready, but the equipment choice could not be kept on this device." }
    }

    private func restoreLastSelection() {
        guard !restoredSelection else { return }
        restoredSelection = true
        // A contextual set's equipment and a legacy read-only set take precedence over preferences.
        guard initialEquipment == nil, !locksTarget, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do {
            guard let selection = try EditorDraftStore().load(PlateCalculatorSelection.self, userID: ownerID,
                scope: "plate-calculator-last-equipment")?.value, let reference = selection.reference else { return }
            guard let profile = try StrengthGymProfileStore().profiles(userID: ownerID).first(where: { $0.id == reference.profileID }),
                  profile.revisionID == reference.revisionID, let equipment = profile.equipment(for: reference.implementID) else {
                selectionNotice = "Your last gym setup changed or was removed. Choose it again to review its current inventory; the standard preset is shown."
                return
            }
            selectedEquipment = equipment; displayUnit = equipment.unit; setTarget(canonicalTarget)
        } catch { selectionNotice = "Your saved calculator selection couldn't be opened. It is kept; choose equipment explicitly to continue." }
    }

    private func setTarget(_ pounds: Double?) {
        canonicalTarget = pounds
        let text = pounds.map(displayText) ?? ""
        renderedTarget = text; targetWeight = text
    }

    private func displayText(_ pounds: Double) -> String { Self.weightText(displayUnit.displayWeight(pounds)) }

    private func calculatorMessage(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(icon == "exclamationmark.triangle.fill" ? AppPalette.caution : AppPalette.brandText)
                .frame(width: 36, height: 36)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text(message)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.quiet)
    }

    private var methodNote: some View {
        Label {
            Text(selectedEquipment == nil ? "Counts are for each side of the explicit standard 45 lb preset. Collars are not included."
                : "Only the selected implement's inventory is used. Counts are per side for bars; fixed loads keep their stated convention. Collars are not included.")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func adjustTarget(by amount: Double) {
        if let equipment = selectedEquipment {
            let current = parsedTarget ?? minimumWeight
            let next = amount > 0 ? equipment.next(after: current) : equipment.previous(before: current)
            if let next { setTarget(next) } else if parsedTarget == nil { setTarget(minimumWeight) }
            return
        }
        let current = parsedTarget ?? PlateLoadingRules.standardBarWeight
        let adjusted = min(
            PlateLoadingRules.maximumSupportedWeight,
            max(PlateLoadingRules.standardBarWeight, current + amount)
        )
        setTarget(adjusted)
    }

    fileprivate static func weightText(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...3)))
    }
}

private struct PlateLoadDiagram: View {
    let loadout: PlateLoadout
    let unit: StrengthEquipment.Unit

    private var renderedPlates: [Double] {
        Array(loadout.platesPerSide.flatMap { plate in
            Array(repeating: plate.weight, count: plate.countPerSide)
        }.prefix(8))
    }

    private var hiddenPlateCount: Int {
        max(0, loadout.platesPerSide.reduce(0) { $0 + $1.countPerSide } - renderedPlates.count)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(UIColor.systemGray3))
                    .frame(width: 48, height: 18)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(UIColor.systemGray2))
                    .frame(width: 10, height: 42)

                ForEach(Array(renderedPlates.enumerated()), id: \.offset) { _, weight in
                    PlateGlyph(weight: weight)
                }

                if hiddenPlateCount > 0 {
                    Text("+\(hiddenPlateCount)")
                        .appTextRole(.control)
                        .foregroundStyle(.secondary)
                        .padding(.leading, AppSpacing.compact)
                }
            }
            .padding(.horizontal, AppSpacing.group)
            .frame(minHeight: 122)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            loadout.platesPerSide.map {
                "\($0.countPerSide) \(PlateCalculatorView.weightText(unit.displayWeight($0.weight))) \(unit.rawValue) per side"
            }.joined(separator: ", ")
        )
    }

    static func color(for weight: Double) -> Color {
        switch weight {
        case 45: .blue
        case 35: .yellow
        case 25: .green
        case 10: .gray
        case 5: .orange
        case 2.5: .red
        default: .gray
        }
    }
}

private struct PlateGlyph: View {
    let weight: Double

    private var height: CGFloat {
        switch weight {
        case 45: 104
        case 35: 92
        case 25: 80
        case 10: 66
        case 5: 54
        case 2.5: 46
        default: 60
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(PlateLoadDiagram.color(for: weight))
            .frame(width: max(14, min(24, height / 4.5)), height: height)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
            }
    }
}
