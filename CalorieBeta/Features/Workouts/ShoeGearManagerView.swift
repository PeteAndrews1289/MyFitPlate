import MyFitPlateCore
import SwiftUI

public struct ShoeGearManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shoeStore = RunningShoeStore()
    @State private var showingAddShoeModal: Bool
    @State private var lifetimeRuns: [Run]?
    @State private var lifetimeError: String?
    @State private var lifetimeLoadedAt: Date?
    @State private var lifetimeScopeNote: String?
    @State private var editingShoe: RunningShoe?
    @State private var reviewingShoe: RunningShoe?
    @State private var removingShoe: RunningShoe?
    @State private var showingBatchAssignment = false
    @State private var comparisonEnvironment = 1
    @State private var comparisonDays = 90
    @State private var gearError: String?
    @State private var inspectedComparison: [Run]?
    @State private var comparisonScheduledOnly = false
    let runs: [Run]
    let onShoeSelected: ((RunningShoe) -> Void)?

    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us

    public init(
        runs: [Run] = [],
        lifetimeRuns: [Run]? = nil,
        onShoeSelected: ((RunningShoe) -> Void)? = nil,
        initiallyShowsAddShoe: Bool = false
    ) {
        self.runs = runs
        self.onShoeSelected = onShoeSelected
        _showingAddShoeModal = State(initialValue: initiallyShowsAddShoe)
        _lifetimeRuns = State(initialValue: lifetimeRuns)
        #if DEBUG
        if lifetimeRuns == nil { _lifetimeRuns = State(initialValue: ScreenshotDemoMode.isEnabled ? runs : nil) }
        #endif
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Button {
                        HapticManager.instance.feedback(.light)
                        showingAddShoeModal = true
                    } label: {
                        Label("Add shoe", systemImage: "plus")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .padding(.horizontal, AppSpacing.screenHorizontal)

                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        if let lifetimeError {
                            Text(lifetimeError).appTextRole(.secondary)
                            Button("Retry lifetime mileage", action: loadLifetimeRuns)
                        } else if lifetimeRuns == nil {
                            ProgressView("Loading lifetime mileage")
                        }
                        Text("New recordings: \(shoeStore.defaultShoe()?.displayName ?? "no default shoe")")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        DisclosureGroup {
                        Text("Mileage includes available Apple Health runs and saved recordings, independently of the recent-run filter. Health access can limit imported coverage.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        Text("Mileage reminders track distance, not the physical condition of a shoe.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        if let lifetimeLoadedAt {
                            Text("Reconciled \(lifetimeLoadedAt.formatted(date: .abbreviated, time: .shortened))")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Reconcile mileage", action: loadLifetimeRuns)
                                .accessibilityIdentifier("shoe_reconcile_mileage")
                            Spacer()
                            Button("Assign past runs") { showingBatchAssignment = true }
                                .disabled(lifetimeRuns == nil)
                                .accessibilityIdentifier("shoe_batch_assignment")
                        }
                        if shoeStore.defaultShoe() != nil {
                            Button("Leave new recordings unassigned") { shoeStore.setDefaultShoe(id: "") }
                        }
                        } label: {
                            Text("Mileage & assignments").accessibilityIdentifier("shoe_mileage_tools")
                        }
                        .tint(AppPalette.text)
                        Text("Available Health and saved runs · Health access can limit mileage coverage.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        if let lifetimeScopeNote { Text(lifetimeScopeNote).appTextRole(.caption).foregroundStyle(.secondary) }
                        if let receipt = shoeStore.latestUndoableAssignment {
                            Button("Undo last assignment (\(receipt.after.count) \(receipt.after.count == 1 ? "run" : "runs"))") {
                                do { try shoeStore.undoAssignment(receipt) } catch { gearError = error.localizedDescription }
                            }.accessibilityIdentifier("shoe_assignment_undo")
                        }
                        if let error = gearError ?? shoeStore.lastError {
                            Text(error).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)

                    if shoeStore.shoes.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(shoeStore.shoes.filter { !$0.isRetired }) { shoe in shoeCard(for: shoe) }
                            if shoeStore.shoes.contains(where: \.isRetired) {
                                AppSectionHeader(title: "Retired shoes", subtitle: "Their assignments and mileage stay in your history.")
                                ForEach(shoeStore.shoes.filter(\.isRetired)) { shoe in shoeCard(for: shoe) }
                            }
                        }
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        if !(lifetimeRuns ?? []).isEmpty { leaderboardSection }
                    }
                }
                .padding(.vertical, AppSpacing.group)
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Shoes")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("shoe_gear_screen")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .appTextRole(.control)
                }
            }
            .sheet(isPresented: $showingAddShoeModal) {
                AddShoeModal(shoeStore: shoeStore)
            }
            .sheet(item: $editingShoe) { shoe in AddShoeModal(shoeStore: shoeStore, initialShoe: shoe) }
            .sheet(item: $reviewingShoe) { shoe in
                ShoeContributionView(shoe: shoe, runs: inspectedComparison ?? lifetimeRuns ?? [], store: shoeStore, metric: useMetric, isLifetime: inspectedComparison == nil)
            }
            .sheet(isPresented: $showingBatchAssignment) {
                RunShoeBatchAssignmentView(runs: lifetimeRuns ?? [], store: shoeStore, metric: useMetric)
            }
            .confirmationDialog("Remove unused shoe?", isPresented: Binding(get: { removingShoe != nil }, set: { if !$0 { removingShoe = nil } })) {
                Button("Remove shoe", role: .destructive) {
                    if let shoe = removingShoe, let ownerID = DIContainer.shared.authService.currentUserID {
                        do { try shoeStore.removeUnusedShoe(shoe, across: lifetimeRuns ?? [], userID: ownerID) } catch { gearError = error.localizedDescription }
                    }
                    removingShoe = nil
                }
            } message: { Text("Only unused inventory can be removed. Shoes with assignments must be retired so their history stays intact.") }
            .onAppear { if lifetimeRuns == nil { loadLifetimeRuns() } }
        }
    }

    private func loadLifetimeRuns() {
        guard let ownerID = DIContainer.shared.authService.currentUserID else { return }
        lifetimeError = nil
        if lifetimeRuns == nil, let cached = try? RunHistorySnapshotStore().load(userID: ownerID) {
            lifetimeRuns = try? RunReviewStore().projecting(RunLocalHistoryRules.merging(healthRuns: cached.runs,
                localRuns: RunFallbackStore.shared.runs(since: .distantPast, for: ownerID)), userID: ownerID)
            lifetimeLoadedAt = cached.capturedAt
            lifetimeScopeNote = cached.isTruncated ? "Offline snapshot includes only the newest 10,000 runs. Refresh for complete available scope." : "Showing the last available history snapshot while refreshing."
        }
        RunImportService().fetchLifetimeRuns(userID: ownerID) { result in
            guard DIContainer.shared.authService.currentUserID == ownerID else { return }
            switch result {
            case .success(let all):
                lifetimeRuns = all
                lifetimeLoadedAt = Date()
                lifetimeScopeNote = nil
                do { try RunHistorySnapshotStore().save(all, userID: ownerID) } catch { lifetimeScopeNote = "Mileage refreshed; its offline snapshot could not be updated." }
            case .failure:
                if lifetimeRuns == nil { lifetimeRuns = RunFallbackStore.shared.runs(since: .distantPast, for: ownerID) }
                lifetimeError = "Lifetime mileage could not refresh. Previously available runs and local saves are kept; imported coverage may be incomplete."

            }
        }
    }

    private var comparisonRuns: [Run] {
        let cutoff = comparisonDays == 0 ? Date.distantPast : Date().addingTimeInterval(Double(-comparisonDays) * 86_400)
        return (lifetimeRuns ?? []).filter { run in
            run.startDate >= cutoff && run.distanceMeters >= 500 && run.averagePaceSecondsPerKm != nil
                && (comparisonEnvironment == 0 || (comparisonEnvironment == 1 ? !run.isIndoor : run.isIndoor))
                && (!comparisonScheduledOnly || run.scheduledContext != nil)
        }
    }

    private var leaderboardSection: some View {
        DisclosureGroup("Compare recorded use") {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Picker("Setting", selection: $comparisonEnvironment) {
                    Text("Outdoor").tag(1); Text("Indoor").tag(2); Text("All").tag(0)
                }.pickerStyle(.segmented)
                Picker("Period", selection: $comparisonDays) {
                    Text("30 days").tag(30); Text("90 days").tag(90); Text("All available").tag(0)
                }.pickerStyle(.segmented)
                Toggle("Scheduled sessions only", isOn: $comparisonScheduledOnly)
                Text("Runs of at least 500 m. Pace is weighted by distance. Routes, weather and workout intensity are not matched; these observations do not show that one shoe makes you faster.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                ForEach(shoeStore.shoes.sorted { $0.displayName < $1.displayName }) { shoe in
                    let included = shoeStore.contributingRuns(for: shoe.id, across: comparisonRuns)
                    if !included.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(shoe.displayName).appTextRole(.control)
                            Text("\(included.count) runs · \(RunFormat.distanceText(meters: included.reduce(0) { $0 + $1.distanceMeters }, metric: useMetric))")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            if let pace = shoeStore.averagePaceSecondsPerKm(for: shoe.id, across: included) {
                                Text("Typical recorded pace \(RunFormat.paceText(secondsPerKm: pace, metric: useMetric) ?? "—")")
                                    .appTextRole(.secondary)
                            }
                            if let recent = included.max(by: { $0.startDate < $1.startDate }) {
                                LabeledContent("Most recent", value: recent.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .appTextRole(.caption)
                            }
                            if let longest = included.map(\.distanceMeters).max() {
                                LabeledContent("Longest", value: RunFormat.distanceText(meters: longest, metric: useMetric)).appTextRole(.caption)
                            }
                            let easy = RunComparisonRules.easyRuns(included)
                            LabeledContent("Explicit easy sessions", value: "\(easy.count)").appTextRole(.caption)
                            if let pace = shoeStore.averagePaceSecondsPerKm(for: shoe.id, across: easy) {
                                LabeledContent("Easy-session pace", value: RunFormat.paceText(secondsPerKm: pace, metric: useMetric) ?? "—").appTextRole(.caption)
                            }
                            Button("Inspect supporting runs") { inspectedComparison = comparisonRuns; reviewingShoe = shoe }
                        }
                        Divider()
                    }
                }
                if !shoeStore.shoes.contains(where: { shoeStore.runCount(for: $0.id, across: comparisonRuns) > 0 }) {
                    Text("No assigned runs in this selection. Broaden the setting or date range.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                Text("Comparison filters do not change lifetime mileage.").appTextRole(.caption).foregroundStyle(.secondary)
                Text("Easy-session comparisons require recorded workout steps with an explicit easy cue. Open runs and imports are not guessed to be easy from pace alone.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }.padding(.top, AppSpacing.row)
        }.appSurface(.quiet).padding(.horizontal, AppSpacing.screenHorizontal)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(UIColor.tertiaryLabel))
            Text("No shoes added yet")
                .appTextRole(.sectionTitle)
                .foregroundColor(AppPalette.text)
            Text("Add the pairs you own, choose a mileage reminder, and assign them to your runs.")
                .appTextRole(.body)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .appSurface(.emphasized)
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    private func shoeCard(for shoe: RunningShoe) -> some View {
        let totalMeters = shoeStore.totalMeters(for: shoe.id, across: lifetimeRuns ?? [])
        let wear = lifetimeRuns == nil ? 0 : shoeStore.wearPercentage(for: shoe.id, across: lifetimeRuns ?? [])
        let isWornOut = lifetimeRuns != nil && shoeStore.isWornOut(shoeID: shoe.id, across: lifetimeRuns ?? [])

        let distanceString = RunFormat.distanceText(meters: totalMeters, metric: useMetric)
        let maxDistanceString = RunFormat.distanceText(meters: shoe.maxMeters, metric: useMetric)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "shoeprints.fill")
                    .appTextRole(.sectionTitle)
                    .foregroundColor(shoe.isRetired ? Color(UIColor.tertiaryLabel) : AppPalette.effort)
                    .frame(width: 42, height: 42)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(shoe.displayName)
                            .appTextRole(.control)
                            .foregroundColor(shoe.isRetired ? Color(UIColor.secondaryLabel) : AppPalette.text)

                        if shoeStore.defaultShoe()?.id == shoe.id {
                            Text("Default")
                                .appTextRole(.caption)
                                .foregroundColor(AppPalette.brandText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppPalette.brand.opacity(0.12), in: Capsule())
                        }

                        if shoe.isRetired {
                            Text("Retired")
                                .appTextRole(.caption)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                        }
                    }

                    if shoe.isUnconfirmedPlaceholder {
                        Text("Unconfirmed placeholder — edit to identify your actual shoe.")
                            .appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    }
                    if let acquired = shoe.acquiredDate {
                        Text("Acquired \(acquired.formatted(date: .abbreviated, time: .omitted))").appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    Text(lifetimeRuns == nil ? "Lifetime mileage pending" : "\(distanceString) of \(maxDistanceString)")
                        .accessibilityIdentifier("shoe_lifetime_distance_\(shoe.id)")
                        .appTextRole(.secondary)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .monospacedDigit()
                    if lifetimeRuns != nil {
                        Text("Initial \(RunFormat.distanceText(meters: shoe.initialMeters, metric: useMetric)) · Tracked \(RunFormat.distanceText(meters: max(0, totalMeters - shoe.initialMeters), metric: useMetric))")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button("Edit shoe", systemImage: "pencil") { editingShoe = shoe }
                    Button("Review mileage", systemImage: "list.bullet") { inspectedComparison = nil; reviewingShoe = shoe }
                    if !shoe.isDefault && !shoe.isRetired && !shoe.isUnconfirmedPlaceholder {
                        Button {
                            HapticManager.instance.feedback(.light)
                            shoeStore.setDefaultShoe(id: shoe.id)
                        } label: {
                            Label("Set as Default", systemImage: "star.fill")
                        }
                    }

                    if !shoe.isRetired {
                        Button(role: .destructive) {
                            HapticManager.instance.feedback(.medium)
                            shoeStore.retireShoe(id: shoe.id)
                        } label: {
                            Label("Retire Shoe", systemImage: "archivebox")
                        }
                    } else {
                        Button {
                            HapticManager.instance.feedback(.light)
                            var reactivated = shoe
                            reactivated.isRetired = false
                            shoeStore.updateShoe(reactivated)
                        } label: {
                            Label("Reactivate Shoe", systemImage: "arrow.uturn.backward")
                        }
                    }

                    if lifetimeRuns != nil, shoeStore.contributingRuns(for: shoe.id, across: lifetimeRuns ?? []).isEmpty {
                        Button("Remove unused shoe", systemImage: "trash", role: .destructive) { removingShoe = shoe }
                    }
                    if let onShoeSelected = onShoeSelected {
                        Button {
                            onShoeSelected(shoe)
                            dismiss()
                        } label: {
                            Label("Select for Run", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .appTextRole(.sectionTitle)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 36, height: 36)
                }
            }

            Button("Review contributing runs") { inspectedComparison = nil; reviewingShoe = shoe }
                .accessibilityIdentifier("shoe_contributions_\(shoe.id)")

            // Mileage Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(height: 8)

                        Capsule()
                            .fill(isWornOut ? AppPalette.caution : (shoe.isRetired ? Color(UIColor.secondaryLabel) : AppPalette.brand))
                            .frame(width: min(geometry.size.width * CGFloat(wear), geometry.size.width), height: 8)
                    }
                }
                .frame(height: 8)

                if isWornOut && !shoe.isRetired {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .appTextRole(.caption)
                            .foregroundColor(AppPalette.caution)
                        Text("Reminder threshold reached. Review the shoe's condition.")
                            .appTextRole(.caption)
                            .foregroundColor(AppPalette.caution)
                    }
                    .padding(.top, 2)
                }

                let count = shoeStore.runCount(for: shoe.id, across: lifetimeRuns ?? [])
                if count > 0 {
                    HStack {
                        if let pace = shoeStore.averagePaceSecondsPerKm(for: shoe.id, across: lifetimeRuns ?? []),
                           let paceStr = RunFormat.paceText(secondsPerKm: pace, metric: useMetric) {
                            Label("Avg Pace: \(paceStr)", systemImage: "timer")
                        }
                        Spacer()
                        if let longest = shoeStore.longestRunDistance(for: shoe.id, across: lifetimeRuns ?? []) {
                            Label("Longest: \(RunFormat.distanceText(meters: longest, metric: useMetric))", systemImage: "arrow.left.and.right")
                        }
                    }
                    .appTextRole(.caption)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .padding(.top, 4)
                }
            }
        }
        .appSurface(.quiet)
        .contentShape(Rectangle())
        .onTapGesture {
            if let onShoeSelected = onShoeSelected {
                onShoeSelected(shoe)
                dismiss()
            }
        }
    }
}

private struct AddShoeModal: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var shoeStore: RunningShoeStore
    private let ownerID: String?
    private let metric: Bool
    @State private var original: RunningShoe?
    @State private var shoeID: String
    @State private var operationID = UUID().uuidString
    @State private var addedDate: Date
    @State private var brand: String
    @State private var name: String
    @State private var nickname: String
    @State private var initialMileage: String
    @State private var maxMileage: String
    @State private var isDefault: Bool
    @State private var recordsAcquisition: Bool
    @State private var acquisition: Date
    @State private var error: String?

    init(shoeStore: RunningShoeStore, initialShoe: RunningShoe? = nil) {
        self.shoeStore = shoeStore
        ownerID = DIContainer.shared.authService.currentUserID
        let units = UserDefaults.standard.object(forKey: "useMetricBodyUnits") as? Bool ?? (Locale.current.measurementSystem != .us)
        metric = units
        let divisor = units ? 1000.0 : RunFormat.metersPerMile
        _original = State(initialValue: initialShoe)
        _addedDate = State(initialValue: initialShoe?.addedDate ?? Date())
        _shoeID = State(initialValue: initialShoe?.id ?? UUID().uuidString)
        _brand = State(initialValue: initialShoe?.brand ?? "")
        _name = State(initialValue: initialShoe?.name ?? "")
        _nickname = State(initialValue: initialShoe?.nickname ?? "")
        _initialMileage = State(initialValue: initialShoe.map { String(format: "%.2f", $0.initialMeters / divisor) } ?? "0")
        _maxMileage = State(initialValue: initialShoe.map { String(format: "%.2f", $0.maxMeters / divisor) } ?? (units ? "560" : "350"))
        _isDefault = State(initialValue: initialShoe?.isDefault ?? (shoeStore.defaultShoe() == nil))
        _recordsAcquisition = State(initialValue: initialShoe?.acquiredDate != nil)
        _acquisition = State(initialValue: initialShoe?.acquiredDate ?? Date())
    }

    private func number(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
    private var validation: String? {
        if brand.trimmed.isEmpty || name.trimmed.isEmpty { return "Enter the shoe's brand and model." }
        guard let initial = number(initialMileage), initial >= 0 else { return "Initial distance must be a nonnegative number." }
        guard let limit = number(maxMileage), limit * (metric ? 1000 : RunFormat.metersPerMile) >= 1000 else { return "Choose a reminder threshold of at least 1 km (0.63 mi)." }
        if recordsAcquisition && acquisition > Date() { return "Acquisition date cannot be in the future." }
        return nil
    }

    var body: some View {
        AppEditorScaffold(title: original == nil ? "Add a shoe" : "Edit shoe", subtitle: "Track mileage for each pair you run in.", dismiss: { dismiss() }) {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Shoe details")
                    TextField("Brand", text: $brand).textFieldStyle(.roundedBorder).accessibilityIdentifier("add_shoe_brand")
                    TextField("Model", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("add_shoe_name")
                    TextField("Nickname (optional)", text: $nickname).textFieldStyle(.roundedBorder).accessibilityIdentifier("shoe_edit_nickname")
                    Toggle("Record acquisition date", isOn: $recordsAcquisition)
                    if recordsAcquisition { DatePicker("Acquired", selection: $acquisition, in: ...Date(), displayedComponents: .date) }
                }.appTextRole(.body).appSurface(.quiet)
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    AppSectionHeader(title: "Mileage", subtitle: "Include distance you ran before tracking this pair.")
                    HStack(spacing: AppSpacing.row) {
                        Text("Initial distance (\(metric ? "km" : "mi"))")
                        Spacer(minLength: AppSpacing.compact)
                        TextField("0", text: $initialMileage).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("Initial distance (\(metric ? "km" : "mi"))")
                            .textFieldStyle(.roundedBorder).frame(width: 88)
                            .accessibilityIdentifier("shoe_edit_initial_distance")
                    }
                    HStack(spacing: AppSpacing.row) {
                        Text("Reminder (\(metric ? "km" : "mi"))")
                        Spacer(minLength: AppSpacing.compact)
                        TextField("Reminder", text: $maxMileage).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .accessibilityLabel("Mileage reminder (\(metric ? "km" : "mi"))")
                            .textFieldStyle(.roundedBorder).frame(width: 88)
                            .accessibilityIdentifier("shoe_edit_reminder")
                    }
                    Text("A distance reminder, not a measure of physical wear.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }.appTextRole(.body).appSurface(.quiet)
                Toggle("Use for new recordings by default", isOn: $isDefault)
                    .disabled(original?.isRetired == true)
                    .appSurface(.quiet)
                Text("Saved for this account on this device. Previous mileage and run assignments stay in your history.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        } actions: {
            if let message = error ?? validation {
                Text(message).appTextRole(.caption).foregroundStyle(AppPalette.caution)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("shoe_edit_validation")
            }
            Button("Save shoe", action: saveShoe).buttonStyle(AppActionButtonStyle(.primary))
                .disabled(validation != nil).accessibilityIdentifier("add_shoe_save")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("add_shoe_screen")
    }

    private func saveShoe() {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { error = "Your account changed. Reopen this editor in the correct account."; return }
        guard validation == nil, let initial = number(initialMileage), let maximum = number(maxMileage) else { return }
        let factor = metric ? 1000.0 : RunFormat.metersPerMile
        // Untouched displayed decimals must not round a precise historical balance.
        let originalInitial = original.map { String(format: "%.2f", $0.initialMeters / factor) }
        let originalMaximum = original.map { String(format: "%.2f", $0.maxMeters / factor) }
        let accepted = RunningShoe(id: shoeID, name: name.trimmed, brand: brand.trimmed,
            initialMeters: initialMileage == originalInitial ? original!.initialMeters : initial * factor,
            maxMeters: maxMileage == originalMaximum ? original!.maxMeters : maximum * factor,
            isRetired: original?.isRetired ?? false, isDefault: isDefault,
            addedDate: addedDate, nickname: nickname.trimmed.isEmpty ? nil : nickname.trimmed,
            acquiredDate: recordsAcquisition ? acquisition : nil)
        do {
            _ = try shoeStore.saveReviewed(accepted, replacing: original, operationID: operationID, userID: ownerID)
            HapticManager.instance.notification(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ShoeSetupField<Content: View>: View {
    let title: String
    let icon: String
    private let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Label(title, systemImage: icon)
                .appFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)

            content
                .appFont(size: 16)
                .foregroundStyle(AppPalette.text)
                .padding(.horizontal, AppSpacing.row)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(
                    AppPalette.canvas,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShoeSetupSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appFont(size: 18, weight: .bold)
                .foregroundStyle(AppPalette.text)

            Text(subtitle)
                .appFont(size: 13, weight: .medium)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShoeContributionView: View {
    @Environment(\.dismiss) private var dismiss
    let shoe: RunningShoe
    let runs: [Run]
    @ObservedObject var store: RunningShoeStore
    let metric: Bool
    let isLifetime: Bool

    var body: some View {
        let current = store.shoe(for: shoe.id) ?? shoe
        let contributions = store.contributingRuns(for: shoe.id, across: runs)
        NavigationStack {
            List {
                Section(isLifetime ? "Lifetime mileage reconciliation" : "Selected comparison") {
                    if isLifetime { LabeledContent("Initial distance", value: RunFormat.distanceText(meters: current.initialMeters, metric: metric)) }
                    LabeledContent("Tracked (\(contributions.count) runs)", value: RunFormat.distanceText(meters: contributions.reduce(0) { $0 + $1.distanceMeters }, metric: metric))
                    if isLifetime {
                        LabeledContent("Total", value: RunFormat.distanceText(meters: store.totalMeters(for: shoe.id, across: runs), metric: metric))
                    } else if let pace = store.averagePaceSecondsPerKm(for: shoe.id, across: runs) {
                        LabeledContent("Distance-weighted pace", value: RunFormat.paceText(secondsPerKm: pace, metric: metric) ?? "—")
                    }
                    Text(isLifetime ? "Available Health and saved recordings. Each recording contributes once, including its Health alias. Missing Health access can limit coverage." : "These are the exact runs behind the selected comparison filters. Lifetime mileage is unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Contributing runs") {
                    ForEach(contributions) { run in
                        NavigationLink {
                            RunDetailView(run: run)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                                Text("\(RunFormat.distanceText(meters: run.distanceMeters, metric: metric)) · \(run.isIndoor ? "Indoor" : "Outdoor")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                let corrections = isLifetime ? store.revisions(for: shoe.id).filter { $0.before != nil && $0.before?.initialMeters != $0.after?.initialMeters } : []
                if !corrections.isEmpty {
                    Section("Initial-distance corrections") {
                        ForEach(corrections) { revision in
                            if let after = revision.after {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(revision.changedAt.formatted(date: .abbreviated, time: .shortened))
                                    Text("\(RunFormat.distanceText(meters: revision.before?.initialMeters ?? 0, metric: metric)) → \(RunFormat.distanceText(meters: after.initialMeters, metric: metric))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .appFormStyle()
            .navigationTitle(current.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct RunShoeBatchAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    let runs: [Run]
    @ObservedObject var store: RunningShoeStore
    let metric: Bool
    private let ownerID = DIContainer.shared.authService.currentUserID
    @State private var selected: Set<String> = []
    @State private var shoeID: String?
    @State private var review: RunShoeAssignmentReview?
    @State private var receipt: RunShoeAssignmentReceipt?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let receipt {
                    Section("Assignment saved") {
                        Text("\(receipt.after.count) recordings updated. Their distances and workout history are unchanged.")
                        Button("Undo this assignment") {
                            do { try store.undoAssignment(receipt); self.receipt = nil; review = nil } catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("shoe_batch_undo")
                    }
                } else if let review {
                    Section("Review assignment") {
                        LabeledContent("Selected recordings", value: review.expected.count.formatted())
                        LabeledContent("Assign to", value: review.targetShoeID.flatMap { store.shoe(for: $0)?.displayName } ?? "Unassigned")
                        Text("Only the selected recordings change. Current defaults and every other run stay as they are. Retired shoes can be used for historical assignments.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(review.runs) { run in
                            LabeledContent(run.startDate.formatted(date: .abbreviated, time: .omitted), value: RunFormat.distanceText(meters: run.distanceMeters, metric: metric))
                        }
                        Button("Confirm assignment") {
                            do { receipt = try store.commitAssignment(review) } catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("shoe_batch_confirm")
                        Button("Change selection") { self.review = nil }
                    }
                } else {
                    Section("Shoe for selected runs") {
                        Picker("Assign to", selection: $shoeID) {
                            Text("Unassigned").tag(String?.none)
                            ForEach(store.shoes) { shoe in Text(shoe.displayName + (shoe.isRetired ? " (retired)" : "")).tag(Optional(shoe.id)) }
                        }
                        Text("Select individual recordings, then review the change before saving.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Available history") {
                        ForEach(runs) { run in
                            Button {
                                if selected.contains(run.id) { selected.remove(run.id) } else { selected.insert(run.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(run.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                                        Text("\(RunFormat.distanceText(meters: run.distanceMeters, metric: metric)) · \(store.explicitShoeID(for: run).flatMap { store.shoe(for: $0)?.displayName } ?? "Unassigned")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.accessibilityIdentifier("shoe_batch_run_\(run.id)")
                        }
                    }
                    Section {
                        Button("Review \(selected.count) selected runs") {
                            guard let ownerID else { return }
                            do { review = try store.reviewAssignment(runs: runs.filter { selected.contains($0.id) }, shoeID: shoeID, userID: ownerID) } catch { self.error = error.localizedDescription }
                        }.disabled(selected.isEmpty).accessibilityIdentifier("shoe_batch_review")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(AppPalette.caution) } }
            }
            .appFormStyle()
            .navigationTitle("Assign past runs").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .accessibilityIdentifier("shoe_batch_screen")
        }
    }
}
