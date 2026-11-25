import MyFitPlateCore
import SwiftUI

struct TrainingFuelHistoryView: View {
    @EnvironmentObject private var store: TrainingFuelPlanStore
    @EnvironmentObject private var diary: DailyLogService
    @Environment(\.dismiss) private var dismiss
    private let ownerID = DIContainer.shared.authService.currentUserID
    @State private var error: String?
    @State private var linkingPlan: TrainingFuelConfirmedPlan?
    @State private var selectedFoodIDs = Set<String>()
    @State private var phase: TrainingFuelAllocation.Phase = .beforeTraining

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(store.syncMessage ?? (store.hasCloudSync ? "Checking sync…" : "Saved on this device."))
                        .foregroundStyle(.secondary)
                    if let error = error ?? store.errorMessage { Text(error).foregroundStyle(AppPalette.critical) }
                    if store.pendingFoodLinkCount > 0 {
                        Button("Retry \(store.pendingFoodLinkCount) saved food links") {
                            guard let ownerID else { return }; store.retryFoodLinks(for: ownerID)
                        }
                    }
                    if store.hasCloudSync { Button("Sync now") { Task { await store.synchronize() } }.disabled(store.isSyncing) }
                }
                ForEach(store.conflictingPlanIDs, id: \.self) { planID in
                    Section("Review conflicting versions") {
                        Text("Both devices' changes are kept. Choose the version to use; the alternatives remain in history.")
                        ForEach(store.revisions(planID: planID)) { revision in
                            Button { perform { try store.resolve(planID: planID, choosing: revision.id, for: $0) } } label: {
                                VStack(alignment: .leading) {
                                    Text(revision.plan.draft.sessionTitle)
                                    Text("\(revision.plan.draft.scheduledAt.formatted()) · \(revision.plan.outcome?.status.rawValue ?? "planned") · \(revision.plan.foodLinks?.count ?? 0) links")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(store.history) { revision in
                    Section {
                        DisclosureGroup {
                            details(revision)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(revision.plan.draft.sessionTitle).appTextRole(.control)
                                Text(revision.plan.draft.scheduledAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                Text(revision.archivedAt != nil ? "Closed · history kept" : revision.plan.outcome?.status.rawValue.capitalized ?? "Planned")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("fuel_history_plan_\(revision.plan.id)")
                        }
                    }
                }
                if store.history.isEmpty && store.conflictingPlanIDs.isEmpty {
                    ContentUnavailableView("Your session plans", systemImage: "bolt.heart", description: Text("Confirmed plans and linked foods will appear here."))
                }
            }
            .appFormStyle()
            .navigationTitle("Fuel history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $linkingPlan) { plan in linkReview(plan) }
        }
    }

    @ViewBuilder private func details(_ revision: TrainingFuelRevision) -> some View {
        let plan = revision.plan
        ForEach(plan.allocations, id: \.phase) { allocation in
            LabeledContent("Planned " + allocation.phase.shortTitle.lowercased(),
                value: "\(allocation.proteinGrams)g protein · \(allocation.carbGrams)g carbs")
        }
        Text(plan.calculation?.provisional == true ? "Provisional session: review live goals on its day before choosing food." : "\(plan.calculation?.ruleset ?? "Original unversioned estimate") · bounded inside reviewed daily goals")
            .font(.caption).foregroundStyle(.secondary)
        if let estimate = plan.calculation?.individualEstimate {
            Text("Saved individual reference · one protein serving reference; chosen amount split across this plan.").font(.caption)
            if let range = estimate.bodyMassProteinReference {
                Text("Weight-based reference: \(range.lower.formatted(.number.precision(.fractionLength(0...1))))–\(range.upper.formatted(.number.precision(.fractionLength(0...1)))) g. Common reference: 20–40 g.").font(.caption)
            }
            if let rate = estimate.inputs.duringCarbsPerHour {
                Text("Reviewed practiced strategy: \(rate.formatted()) g carbohydrate per hour.").font(.caption)
            }
        }
        if let outcome = plan.outcome {
            Text("\(outcome.source.rawValue.replacingOccurrences(of: "_", with: " ")) · \(outcome.recordedAt.formatted())")
                .font(.caption).foregroundStyle(.secondary)
            if plan.requiresRecoveryDiaryRefresh() { Text("Waiting for the applicable day's diary before recovery can be calculated.").font(.caption) }
            if outcome.source == .manualConfirmation {
                Button("Undo manual \(outcome.status.rawValue)") {
                    perform { try store.undoManualOutcome(planID: plan.id, revisionID: revision.id, for: $0) }
                }.accessibilityIdentifier("fuel_undo_manual")
            }
        }
        if (plan.foodLinks ?? []).isEmpty {
            Text("No foods explicitly linked. Other diary foods still use your daily budget.").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(plan.foodLinks ?? []) { link in
            HStack {
                VStack(alignment: .leading) {
                    Text(link.name)
                    Text("\(link.phase.shortTitle) · \(link.protein.formatted(.number.precision(.fractionLength(0))))g protein · \(link.carbs.formatted(.number.precision(.fractionLength(0))))g carbs when linked")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Unlink") { perform { try store.unlinkFood(planID: plan.id, linkID: link.id, for: $0) } }.font(.caption)
            }
        }
        Button("Link food already in today's diary") { selectedFoodIDs = []; phase = .beforeTraining; linkingPlan = plan }
        if revision.archivedAt == nil {
            Button("Review this session") {
                perform { try store.select(planID: plan.id, for: $0); dismiss() }
            }
        }
        if plan.outcome != nil {
            NavigationLink("Energy, comfort and practicality") { TrainingFuelFeedbackView(plan: plan, ownerID: ownerID) }
        }
    }

    private func linkReview(_ plan: TrainingFuelConfirmedPlan) -> some View {
        NavigationStack {
            List {
                Text("Only the foods you select will count toward this phase. Their diary amounts stay unchanged.")
                Picker("Phase", selection: $phase) {
                    Text("Before").tag(TrainingFuelAllocation.Phase.beforeTraining)
                    Text("After").tag(TrainingFuelAllocation.Phase.afterTraining)
                    if plan.allocations.contains(where: { $0.phase == .duringTraining }) { Text("During").tag(TrainingFuelAllocation.Phase.duringTraining) }
                }.pickerStyle(.segmented)
                ForEach(diary.currentDailyLog?.meals.flatMap(\.foodItems) ?? []) { food in
                    Toggle(food.name, isOn: Binding(get: { selectedFoodIDs.contains(food.id) }, set: { selected in
                        if selected { selectedFoodIDs.insert(food.id) } else { selectedFoodIDs.remove(food.id) }
                    }))
                }
                Button("Confirm selected food links") {
                    guard let log = diary.currentDailyLog else { return }
                    perform { owner in
                        try store.linkExistingFoods(planID: plan.id, phase: phase, foodIDs: selectedFoodIDs, diary: log, for: owner)
                        linkingPlan = nil
                    }
                }.disabled(selectedFoodIDs.isEmpty).accessibilityIdentifier("fuel_link_existing_confirm")
                if let error { Text(error).foregroundStyle(AppPalette.critical) }
            }.appFormStyle().navigationTitle("Link diary food").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { linkingPlan = nil } } }
        }
    }
    private func perform(_ action: (String) throws -> Void) {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { error = TrainingFuelLibraryError.accountChanged.localizedDescription; return }
        do { try action(ownerID); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct TrainingFuelFeedbackView: View {
    let plan: TrainingFuelConfirmedPlan
    let ownerID: String?
    @EnvironmentObject private var store: TrainingFuelPlanStore
    @Environment(\.dismiss) private var dismiss
    @State private var energy = 3
    @State private var comfort = 3
    @State private var practicality = 3
    @State private var error: String?
    @State private var savedFeedback: TrainingFuelFeedback?
    private var currentFeedback: TrainingFuelFeedback { .init(energy: energy, comfort: comfort, practicality: practicality) }
    private var matchesSavedFeedback: Bool {
        savedFeedback.map { $0.energy == energy && $0.comfort == comfort && $0.practicality == practicality } == true
    }
    var body: some View {
        Form {
            Section {
                Text(plan.draft.sessionTitle).appTextRole(.sectionTitle)
                Text(plan.draft.scheduledAt.formatted(date: .abbreviated, time: .shortened)).appTextRole(.secondary)
            }
            Text("Rate how you felt during this session, from 1 to 5.")
            Stepper("Energy · \(energy)", value: $energy, in: 1...5)
            Stepper("Comfort · \(comfort)", value: $comfort, in: 1...5)
            Stepper("Practicality · \(practicality)", value: $practicality, in: 1...5)
            Button("Save observation") {
                guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
                do {
                    let feedback = currentFeedback
                    try store.saveFeedback(feedback, planID: plan.id, for: ownerID)
                    savedFeedback = feedback; error = nil
                } catch { self.error = error.localizedDescription }
            }
            if matchesSavedFeedback, let savedFeedback {
                Section("Explore what works") {
                    Text("Observation saved \(savedFeedback.recordedAt.formatted(date: .abbreviated, time: .shortened)). Compare meals across similar sessions to look for a pattern.")
                    NavigationLink("Compare familiar meals") {
                        MealExperimentsView(fuelContext: .init(planID: plan.id, sessionTitle: plan.draft.sessionTitle,
                            scheduledAt: plan.draft.scheduledAt, feedback: savedFeedback,
                            linkedFoods: (plan.foodLinks ?? []).map(\.name)))
                    }.accessibilityIdentifier("fuel_feedback_experiment")
                }
            }
            if let error { Text(error).foregroundStyle(AppPalette.critical) }
        }.appFormStyle().navigationTitle("Session feedback")
            .onAppear { if savedFeedback == nil, let feedback = plan.feedback { energy = feedback.energy; comfort = feedback.comfort; practicality = feedback.practicality; savedFeedback = feedback } }
    }
}
