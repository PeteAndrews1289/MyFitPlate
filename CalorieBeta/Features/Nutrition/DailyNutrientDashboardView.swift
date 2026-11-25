import MyFitPlateCore
import SwiftUI

struct DailyNutrientDashboardView: View {
    @EnvironmentObject private var goalSettings: GoalSettings
    @EnvironmentObject private var dailyLogService: DailyLogService
    @State private var date: Date
    @State private var log: DailyLog?
    @State private var pins: [MicronutrientKey] = []
    @State private var selectedKey: MicronutrientKey?
    @State private var error: String?
    @State private var pinError: String?
    @State private var confirmingResetPins = false
    @State private var loading = false
    @State private var requestID = UUID()
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    init(date: Date = Date(), initialLog: DailyLog? = nil) {
        _date = State(initialValue: Calendar.current.startOfDay(for: date)); _log = State(initialValue: initialLog)
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                DatePicker("Nutrition day", selection: $date, in: ...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("daily_nutrients_date")
                Text("Amounts come from foods recorded on this day. Targets use your current settings; other nutrients show the shared label reference, not a new personal goal.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                if let error {
                    Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    Button("Retry day") { Task { await load() } }.frame(minHeight: 44)
                }
                if let pinError {
                    Text(pinError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    Button("Reset only this device's nutrient pins") { confirmingResetPins = true }.frame(minHeight: 44)
                }
                if loading { ProgressView("Loading this day's nutrients") }
                if let log {
                    if !pins.isEmpty {
                        AppSectionHeader(title: "Pinned nutrients", subtitle: "Pins are kept on this device for your account.")
                        ForEach(pins, id: \.self) { key in nutrientRow(key, log: log) }
                    }
                    ForEach(MicronutrientCategory.allCases, id: \.rawValue) { category in
                        AppSectionHeader(title: category.displayName)
                        ForEach(MicronutrientKey.allCases.filter { $0.category == category && !pins.contains($0) }, id: \.self) { key in
                            nutrientRow(key, log: log)
                        }
                    }
                } else if !loading && error == nil { Text("No foods recorded for this day.").foregroundStyle(.secondary) }
            }.padding(AppSpacing.screenHorizontal)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("daily_nutrient_dashboard")
        .background(AppPalette.canvas).navigationTitle("Daily nutrients").navigationBarTitleDisplayMode(.inline)
        .task {
            do { pins = try NutrientDashboardPinStore(userID: ownerID).pins() } catch { pinError = "Your saved nutrient pins could not be opened. Their file is kept. " + error.localizedDescription }
            await load()
        }
        .onChange(of: date) { _, _ in Task { await load() } }
        .refreshable { await load() }
        .confirmationDialog("Reset local nutrient pins?", isPresented: $confirmingResetPins, titleVisibility: .visible) {
            Button("Reset nutrient pins") {
                do {
                    let store = NutrientDashboardPinStore(userID: ownerID); try store.reset(); pins = try store.pins(); pinError = nil
                } catch { pinError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only this device's pinned-nutrient preference resets. Your nutrition goals and food logs stay intact.") }
        .sheet(item: Binding(get: { selectedKey.map(NutrientDashboardSelection.init) }, set: { selectedKey = $0?.key })) { selection in
            if let log {
                NutrientContributorsView(evidence: DailyNutrientDashboardRules.evidence(for: selection.key, log: log), log: log,
                    onChanged: { Task { await load() } })
            }
        }
    }
    private func nutrientRow(_ key: MicronutrientKey, log: DailyLog) -> some View {
        let evidence = DailyNutrientDashboardRules.evidence(for: key, log: log)
        let personal = personalTarget(key)
        let target = personal ?? key.dailyValue
        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .top) {
                Button { selectedKey = key } label: {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(key.displayName).appTextRole(.control)
                        Text(evidence.amount.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) \(key.unit)" } ?? "Not reported")
                            .appTextRole(.sectionTitle).foregroundStyle(evidence.exceedsLimit(target) ? AppPalette.caution : AppPalette.text)
                        Text("\(personal == nil ? "Label reference" : evidence.isUpperLimit ? "Current upper limit" : "Current target"): \(target.formatted()) \(key.unit)")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                        Text(evidence.coverageDescription).appTextRole(.caption).foregroundStyle(.secondary)
                        if evidence.exceedsLimit(target) { Text("Above the \(personal == nil ? "label reference" : "current upper limit")").appTextRole(.caption).foregroundStyle(AppPalette.caution) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("daily_nutrient_\(key.rawValue)")
                Button { togglePin(key) } label: { Image(systemName: pins.contains(key) ? "pin.fill" : "pin") }
                    .buttonStyle(AppIconButtonStyle(.plain)).accessibilityLabel("\(pins.contains(key) ? "Unpin" : "Pin") \(key.displayName)")
            }
        }.appSurface(.quiet)
    }
    private func personalTarget(_ key: MicronutrientKey) -> Double? {
        let target: Double?
        switch key {
        case .calcium: target = goalSettings.calciumGoal
        case .iron: target = goalSettings.ironGoal
        case .potassium: target = goalSettings.potassiumGoal
        case .sodium: target = goalSettings.sodiumGoal
        case .vitaminA: target = goalSettings.vitaminAGoal
        case .vitaminC: target = goalSettings.vitaminCGoal
        case .vitaminD: target = goalSettings.vitaminDGoal
        case .vitaminB12: target = goalSettings.vitaminB12Goal
        case .folate: target = goalSettings.folateGoal
        default: target = nil
        }
        return target.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
    private func togglePin(_ key: MicronutrientKey) {
        var proposed = pins
        if let index = proposed.firstIndex(of: key) { proposed.remove(at: index) } else { proposed.append(key) }
        do { try NutrientDashboardPinStore(userID: ownerID).save(proposed); pins = proposed } catch { pinError = error.localizedDescription }
    }
    @MainActor private func load() async {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { error = LibraryMutationError.accountChanged.localizedDescription; return }
        let selected = date, operationID = UUID(); requestID = operationID; loading = true
        if let log, !Calendar.current.isDate(log.date, inSameDayAs: selected) { self.log = nil }
        defer { if requestID == operationID { loading = false } }
        guard let day = DiaryDayContext(userID: ownerID, date: selected) else { error = "This diary date could not be resolved."; return }
        let result: Result<DailyLog, Error> = await withCheckedContinuation { continuation in
            DIContainer.shared.nutritionRepository.fetchLogInternal(userID: ownerID, day: day) { continuation.resume(returning: $0) }
        }
        guard requestID == operationID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        switch result {
        case .success(let loaded): log = loaded; error = nil
        case .failure(let failure): error = "Couldn't load this day's nutrient data. " + failure.localizedDescription
        }
    }
}

private struct NutrientDashboardSelection: Identifiable {
    let key: MicronutrientKey
    var id: String { key.rawValue }
}

private struct NutrientContributorsView: View {
    let evidence: DailyNutrientEvidence
    let log: DailyLog
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: DailyNutrientContribution?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(log.date.formatted(date: .complete, time: .omitted))
                    Text(evidence.coverageDescription).foregroundStyle(.secondary)
                    Text("Missing nutrient values are unknown. Open a food to inspect the exact snapshot recorded on this day.").foregroundStyle(.secondary)
                }
                ForEach(evidence.contributions) { item in
                    Button { selected = item } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(item.food.name).appTextRole(.control)
                            Text("\(item.mealName) · \(item.food.servingSize)").foregroundStyle(.secondary)
                            Text(item.amount.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) \(evidence.key.unit)" } ?? "Not reported")
                            if let note = item.reportingNote { Text(note).appTextRole(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("nutrient_contributor_\(item.id)")
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle(evidence.key.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $selected) { item in
                NavigationStack {
                    FoodDetailView(initialFoodItem: item.food, dailyLog: .constant(log), date: log.date,
                        source: "log_nutrient_contributor", targetMealName: item.mealName, isPresentedModally: true,
                        onLogUpdated: onChanged)
                }
            }
        }
    }
}
