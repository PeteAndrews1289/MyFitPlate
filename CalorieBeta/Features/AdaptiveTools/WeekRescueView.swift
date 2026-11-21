import MyFitPlateCore
import SwiftUI

struct WeekRescueView: View {
    @EnvironmentObject private var workoutService: WorkoutService
    @EnvironmentObject private var mealPlannerService: MealPlannerService
    @EnvironmentObject private var recipeService: RecipeService
    @Environment(\.dismiss) private var dismiss
    @State private var reason: WeekRescueReason = .missedWorkout
    @State private var scope: WeekRescueScope = .remainingWeek
    @State private var windowDays = 7
    @State private var availableDays = Set<Int>()
    @State private var workoutDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var mealDate = Date()
    @State private var minutes = 30
    @State private var recipeID = ""
    @State private var mealType = "Dinner"
    @State private var mealChoices: [RescueMealChoice] = []
    @State private var reviewDraft: WeekRescueReviewDraft?
    @State private var history: [WeekRescueAcceptedReceipt] = []
    @State private var busy = false
    @State private var message: String?
    @State private var ownerID: String?
    @State private var loadedProgramID: String?
    @State private var storageUnavailable = false
    @State private var confirmingDiscard = false
    @State private var confirmingCancel = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let store = WeekRescueReviewStore()
    private let coachingReview: CoachingActionReview?
    private let onAccepted: ((String) -> Void)?

    init(initialReason: WeekRescueReason = .missedWorkout, coachingReview: CoachingActionReview? = nil,
         onAccepted: ((String) -> Void)? = nil) {
        _reason = State(initialValue: initialReason)
        self.coachingReview = coachingReview; self.onAccepted = onAccepted
    }

    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        return today...(Calendar.current.date(byAdding: .day, value: windowDays, to: today) ?? today)
    }
    private var canAct: Bool {
        !busy && !storageUnavailable && ownerID == DIContainer.shared.authService.currentUserID
            && (reviewDraft == nil || reviewDraft?.programID == workoutService.activeProgram?.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    Text("Make room for real life. Review changes before they reach your plan.")
                        .appTextRole(.secondary).foregroundStyle(.secondary).id("rescue_top")
                    if let program = workoutService.activeProgram {
                        AnyView(content(program))
                        WorkoutSyncNotice(service: workoutService)
                    } else { AdaptiveProgramRequirementView().appSurface(.quiet) }
                    if let message {
                        Text(message).appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("rescue_status")
                    }
                    if !history.isEmpty {
                        DisclosureGroup("Accepted rescue history") {
                            ForEach(history.reversed()) { receipt in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(receipt.wasUndo ? "Rescue undone" : receipt.rescue.reason.rawValue).appTextRole(.body)
                                    Text(receipt.acceptedAt.formatted(date: .abbreviated, time: .shortened))
                                        .appTextRole(.caption).foregroundStyle(.secondary)
                                    Text("\(receipt.rescue.slots.count) sessions · \(receipt.rescue.meals.count) meal days")
                                        .appTextRole(.secondary)
                                }.padding(.vertical, AppSpacing.compact)
                            }
                        }.appSurface(.quiet).accessibilityIdentifier("rescue_history")
                    }
                }.padding(AppSpacing.screenHorizontal)
            }
            .background(AppPalette.canvas)
            .onChange(of: reviewDraft?.command.id) { _, _ in proxy.scrollTo("rescue_top", anchor: .top) }
            .navigationTitle("Rescue my week").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.disabled(busy)
            } }
            .safeAreaInset(edge: .bottom) { footer }
            .task {
                ownerID = DIContainer.shared.authService.currentUserID
                workoutService.fetchRoutinesAndPrograms()
                loadReview()
                await recipeService.fetchUserRecipes()
            }
            .onChange(of: workoutService.activeProgram?.id) { _, _ in loadReview() }
            .confirmationDialog("Discard this unsent rescue review?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard review", role: .destructive) { discardReview() }
                Button("Keep review", role: .cancel) {}
            }
            .confirmationDialog("Cancel this pending rescue change?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Cancel pending change", role: .destructive) { Task { await resolve(cancel: true) } }
                Button("Keep pending", role: .cancel) {}
            } message: { Text("An accepted change will be shown instead. A cancelled request cannot save later.") }
        }
    }

    @ViewBuilder private func content(_ program: WorkoutProgram) -> some View {
        if let draft = reviewDraft {
            review(draft.rescue, program: program, undo: draft.isUndo)
            Text(draft.submitted ? "This submitted review is fixed for safe retry. Closing keeps it on this device."
                 : "Review saved on this device. Your program has not changed.")
                .appTextRole(.caption).foregroundStyle(.secondary).accessibilityIdentifier("rescue_draft_status")
            if draft.submitted {
                HStack {
                    Button("Check status") { Task { await resolve(cancel: false) } }.accessibilityIdentifier("rescue_check_status")
                    Spacer()
                    Button("Cancel pending") { confirmingCancel = true }.accessibilityIdentifier("rescue_cancel_pending")
                }.frame(minHeight: 44).disabled(!canAct)
            } else {
                Button("Discard review") { confirmingDiscard = true }
                    .buttonStyle(AppActionButtonStyle(.secondary)).disabled(!canAct)
                    .accessibilityIdentifier("rescue_discard_review")
            }
        } else if let rescue = program.weekRescue {
            Label("Rescue applied", systemImage: "checkmark.circle.fill")
                .appTextRole(.sectionTitle).foregroundStyle(AppPalette.brandText).accessibilityIdentifier("rescue_applied")
            review(rescue, program: program)
            Button("Review undo") { prepareUndo(rescue, program: program) }
                .buttonStyle(AppActionButtonStyle(.secondary)).disabled(!canAct).accessibilityIdentifier("rescue_undo")
        } else { setup(program) }
    }

    @ViewBuilder private var footer: some View {
        if workoutService.activeProgram != nil, reviewDraft != nil || workoutService.activeProgram?.weekRescue == nil {
            Button {
                Task { if reviewDraft == nil { await buildPreview() } else { await apply() } }
            } label: {
                Text(busy ? "Checking…" : reviewDraft == nil ? "Preview changes"
                     : reviewDraft?.submitted == true ? "Retry reviewed change"
                     : reviewDraft?.isUndo == true ? "Undo reviewed changes" : "Apply rescue")
            }
            .buttonStyle(AppActionButtonStyle(.primary)).disabled(!canAct)
            .accessibilityIdentifier("rescue_primary")
            .padding(AppSpacing.row).background(.bar)
        }
    }

    private func setup(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Text(program.name).appTextRole(.sectionTitle)
            Text("What changed?").appTextRole(.body)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.compact),
                                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: AppSpacing.compact) {
            ForEach(WeekRescueReason.allCases) { option in
                Button { reason = option } label: {
                    HStack {
                        Text(option.rawValue).appTextRole(.secondary)
                        Spacer()
                        Image(systemName: reason == option ? "checkmark.circle.fill" : "circle")
                    }.padding(AppSpacing.compact).frame(minHeight: 56).contentShape(Rectangle())
                        .background(reason == option ? AppPalette.brand.opacity(0.08) : AppPalette.control,
                                    in: RoundedRectangle(cornerRadius: AppRadius.control))
                }.buttonStyle(.plain).foregroundStyle(reason == option ? AppPalette.brandText : AppPalette.text)
                    .accessibilityIdentifier("rescue_reason_\(option.id)")
                    .accessibilityAddTraits(reason == option ? [.isSelected] : [])
            }
            }
            LabeledContent("Plan window") {
                Picker("Recovery window", selection: $windowDays) {
                    Text("3 days").tag(3); Text("7 days").tag(7); Text("14 days").tag(14)
                }.labelsHidden().accessibilityIdentifier("rescue_window")
            }
            if reason == .lessTime || reason == .lighterWeek {
                LabeledContent("Adjust") {
                    Picker("Target changes", selection: $scope) {
                        ForEach(WeekRescueScope.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().accessibilityIdentifier("rescue_scope")
                }
                if reason == .lessTime {
                    LabeledContent("Time per workout") {
                        Picker("Available time", selection: $minutes) {
                            Text("20 minutes").tag(20); Text("30 minutes").tag(30); Text("45 minutes").tag(45)
                        }.labelsHidden()
                    }
                }
                Text("An active workout and completed slots stay protected. Loads and rep ranges are not inferred from recovery data.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            } else {
                DatePicker("Next workout", selection: $workoutDate, in: dateRange, displayedComponents: .date)
                DisclosureGroup("Available days") {
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: Binding(
                            get: { availableDays.contains(weekday) },
                            set: { if $0 { availableDays.insert(weekday) } else { availableDays.remove(weekday) } }))
                    }
                    Text("Leave all unselected to keep your existing gaps. Selected weekdays constrain the recovery window.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }.accessibilityIdentifier("rescue_available_days")
            }
            Divider()
            Text("Make meals easier").appTextRole(.sectionTitle)
            LabeledContent("Recipe") {
                Picker("Saved meal", selection: $recipeID) {
                    Text("Keep planned meals").tag("")
                    ForEach(recipeService.userRecipes.filter { $0.id != nil }, id: \.id) { Text($0.name).tag($0.id ?? "") }
                }.labelsHidden().accessibilityIdentifier("rescue_recipe")
            }
            if !recipeID.isEmpty {
                DatePicker("Meal day", selection: $mealDate, in: dateRange, displayedComponents: .date)
                Picker("Meal", selection: $mealType) {
                    ForEach(["Breakfast", "Lunch", "Dinner", "Snack"], id: \.self) { Text($0).tag($0) }
                }
                Button("Add another meal") {
                    mealChoices.removeAll { Calendar.current.isDate($0.date, inSameDayAs: mealDate) && $0.mealType == mealType }
                    mealChoices.append(RescueMealChoice(recipeID: recipeID, date: mealDate, mealType: mealType))
                    recipeID = ""
                }.frame(minHeight: 44).accessibilityIdentifier("rescue_add_meal")
            }
            ForEach(mealChoices) { choice in
                HStack {
                    Text("\(choice.mealType) · \(choice.date.formatted(date: .abbreviated, time: .omitted))").appTextRole(.secondary)
                    Spacer()
                    Button("Remove") { mealChoices.removeAll { $0.id == choice.id } }.frame(minHeight: 44)
                }
            }
            Text("One reviewed serving replaces the matching meal or fills an empty slot. Shared cooking batches stay protected; planning never logs food.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
        }.disabled(busy).appSurface(.quiet)
    }

    private func review(_ rescue: WeekRescueAdjustment, program: WorkoutProgram, undo: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            Text(undo ? "Review what Undo restores" : "Review all changes").appTextRole(.sectionTitle)
            if undo {
                Text("Only this rescue's temporary overlay is removed. Completed logs and later base-plan edits remain. Active workout changes must finish before Undo.")
                    .appTextRole(.secondary)
            } else { ForEach(rescue.explanation, id: \.self) { Text($0).appTextRole(.secondary) } }
            ForEach(rescue.slots) { slot in
                DisclosureGroup {
                    if let routine = slot.routine {
                        Text("About \(WeekRescueRules.estimatedMinutes(routine)) minutes").appTextRole(.secondary)
                        ForEach(routine.exercises) { exercise in
                            Text("\(exercise.name) · \(exercise.sets.count) sets").appTextRole(.secondary)
                        }
                    } else { Text("Exercise targets stay unchanged.").appTextRole(.secondary) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.routine(forSlot: slot.index)?.name ?? "Workout").appTextRole(.body)
                        Text(undo ? "\(slot.date.formatted(date: .abbreviated, time: .omitted)) → original schedule where unchanged"
                             : "\(slot.originalDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unscheduled") → \(slot.date.formatted(date: .abbreviated, time: .omitted))")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("rescue_slot_\(slot.index)")
            }
            ForEach(rescue.meals) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.replacement.date.formatted(date: .abbreviated, time: .omitted)).appTextRole(.body)
                    ForEach(change.replacement.meals) { meal in
                        Text("\(meal.mealType): \(meal.foodItem?.name ?? "Planned meal")").appTextRole(.secondary)
                    }
                }
            }
            Text("Every affected item is shown. Original recipes, food logs and completed workout receipts stay intact.")
                .appTextRole(.caption).foregroundStyle(.secondary)
        }.appSurface(.quiet)
    }

    private func loadReview() {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID,
              let id = workoutService.activeProgram?.id, loadedProgramID != id else { return }
        do {
            reviewDraft = try store.load(userID: ownerID, programID: id)
            history = try store.history(userID: ownerID, programID: id)
            loadedProgramID = id; storageUnavailable = false
        } catch { storageUnavailable = true; message = "Your saved rescue review could not be read. It is kept on this device." }
    }

    @MainActor private func buildPreview() async {
        guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID,
              let program = workoutService.activeProgram, program.userID == ownerID else { return }
        busy = true; defer { busy = false }
        do {
            try validateCoachingContext(program)
            var choices = mealChoices
            if !recipeID.isEmpty {
                choices.removeAll { Calendar.current.isDate($0.date, inSameDayAs: mealDate) && $0.mealType == mealType }
                choices.append(RescueMealChoice(recipeID: recipeID, date: mealDate, mealType: mealType))
            }
            let changes = try await mealChanges(choices, ownerID: ownerID)
            guard ownerID == DIContainer.shared.authService.currentUserID,
                  let current = workoutService.activeProgram, current.id == program.id,
                  try PlanFingerprint.make(current) == PlanFingerprint.make(program) else { throw WeekRescueError.changed }
            let protected = try workoutService.protectedBlockSlots(in: current)
            let rescue = try WeekRescueReviewRules.preview(program: current, reason: reason, workoutDate: workoutDate,
                scope: scope, windowDays: windowDays, availableWeekdays: availableDays, minutes: minutes,
                mealChanges: changes, protectedSlots: protected)
            let draft = try WeekRescueReviewDraft(program: current, rescue: rescue, protectedSlots: protected)
            try store.save(draft, userID: ownerID); reviewDraft = draft; message = nil
        } catch { message = error.localizedDescription }
    }

    private func mealChanges(_ choices: [RescueMealChoice], ownerID: String) async throws -> [RescueMealChange] {
        var changes: [RescueMealChange] = []
        for day in Set(choices.map { Calendar.current.startOfDay(for: $0.date) }).sorted() {
            let base = try await mealPlannerService.fetchBasePlanResult(for: day, userID: ownerID).get()
            guard ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
            var replacement = base ?? MealPlanEditingRules.emptyDay(day)
            for choice in choices.filter({ Calendar.current.isDate($0.date, inSameDayAs: day) }) {
                guard let recipe = recipeService.userRecipes.first(where: { $0.id == choice.recipeID }) else { throw WeekRescueError.changed }
                let selection = RecipePortionRules.defaultSelection(for: recipe)
                var meal = PlannedMeal(mealType: choice.mealType, recipeID: recipe.id,
                    foodItem: try RecipePortionRules.foodItem(for: recipe, selection: selection),
                    ingredients: try RecipePortionRules.ingredients(for: recipe, selection: selection),
                    instructions: recipe.instructions.joined(separator: "\n"))
                if let profile = recipe.planningProfile, profile.isCurrent(for: recipe) {
                    meal.planningEvidence = try PlannedMealEvidence(profile: profile, meal: meal)
                }
                if let index = replacement.meals.firstIndex(where: { $0.mealType.lowercased() == choice.mealType.lowercased() }) {
                    replacement.meals[index] = meal
                } else { replacement.meals.append(meal) }
            }
            changes.append(try RescueMealChange(original: base, replacement: replacement))
        }
        return changes
    }

    private func prepareUndo(_ rescue: WeekRescueAdjustment, program: WorkoutProgram) {
        do {
            guard let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
            let draft = try WeekRescueReviewDraft(program: program, rescue: rescue, undo: true,
                protectedSlots: workoutService.protectedBlockSlots(in: program))
            try store.save(draft, userID: ownerID); reviewDraft = draft; message = nil
        } catch { message = error.localizedDescription }
    }

    @MainActor private func apply() async {
        guard var draft = reviewDraft, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        busy = true; defer { busy = false }
        do {
            if draft.submitted {
                let status = try await DIContainer.shared.workoutRepository.resolveProgramEdit(userID: ownerID, command: draft.command, cancelPending: false)
                if try finish(status, draft: draft, ownerID: ownerID) { return }
            }
            guard let current = workoutService.activeProgram, current.id == draft.programID,
                  ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
            if !draft.isUndo {
                try validateCoachingContext(current)
                for meal in draft.rescue.meals {
                    let base = try await mealPlannerService.fetchBasePlanResult(for: meal.replacement.date, userID: ownerID).get()
                    guard meal.matches(base) else { throw WeekRescueError.changed }
                }
            }
            guard ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
            draft.submitted = true; try store.save(draft, userID: ownerID); reviewDraft = draft
            let accepted = try await workoutService.saveReviewedProgramEdit(draft.command)
            _ = try finish(.accepted(accepted), draft: draft, ownerID: ownerID)
        } catch { message = error.localizedDescription }
    }

    @MainActor private func resolve(cancel: Bool) async {
        guard let draft = reviewDraft, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        busy = true; defer { busy = false }
        do {
            let status = try await DIContainer.shared.workoutRepository.resolveProgramEdit(userID: ownerID, command: draft.command, cancelPending: cancel)
            if try !finish(status, draft: draft, ownerID: ownerID) { message = "No accepted save was found. Retry this fixed review or cancel it." }
        } catch { message = error.localizedDescription }
    }

    @MainActor private func finish(_ result: WorkoutProgramEditResolution, draft: WeekRescueReviewDraft, ownerID: String) throws -> Bool {
        guard ownerID == DIContainer.shared.authService.currentUserID else { throw WorkoutBlockError.accountChanged }
        switch result {
        case .pending: return false
        case .cancelled:
            try store.discard(draft, userID: ownerID, cancellationConfirmed: true)
            message = "Pending rescue cancelled. Your saved program and history stay intact."
        case .accepted:
            try store.finish(draft, userID: ownerID)
            history = try store.history(userID: ownerID, programID: draft.programID)
            if !draft.isUndo { onAccepted?(draft.rescue.id) }
            message = draft.isUndo ? "Rescue undone. Completed logs and later edits are kept." : "Rescue accepted. Train and Meal Plan can use the reviewed changes."
        }
        reviewDraft = nil; workoutService.fetchRoutinesAndPrograms(); return true
    }

    private func discardReview() {
        guard let draft = reviewDraft, let ownerID, ownerID == DIContainer.shared.authService.currentUserID else { return }
        do { try store.discard(draft, userID: ownerID); reviewDraft = nil; message = nil } catch { message = error.localizedDescription }
    }

    private func validateCoachingContext(_ program: WorkoutProgram) throws {
        guard let coachingReview else { return }
        try coachingReview.validate(userID: DIContainer.shared.authService.currentUserID,
            currentTargetID: program.id, currentFingerprint: WorkoutBlockRules.structureFingerprint(program))
    }
}

private struct RescueMealChoice: Identifiable {
    let id = UUID()
    let recipeID: String
    let date: Date
    let mealType: String
}
