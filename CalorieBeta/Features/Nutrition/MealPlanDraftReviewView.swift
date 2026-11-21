import MyFitPlateCore
import SwiftUI

struct MealPlanDraftReviewView: View {
    let didSave: () -> Void
    @EnvironmentObject private var planner: MealPlannerService
    @EnvironmentObject private var recipes: RecipeService
    @EnvironmentObject private var goals: GoalSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var review: MealPlanWeekSaveSession
    @State private var existing: [MealPlanDay] = []
    @State private var replaceExisting = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var proposed: MealPlanChange?
    @State private var editingMeal: PlannedMeal?
    @State private var isRegenerating = false
    @State private var confirmingDiscard = false
    @State private var editingRecipe: Recipe?
    init(draft: MealPlanWeekDraft, didSave: @escaping () -> Void) {
        self.didSave = didSave
        _review = StateObject(wrappedValue: MealPlanWeekSaveSession(userID: DIContainer.shared.authService.currentUserID, draft: draft))
    }
    private var draft: MealPlanWeekDraft? { review.checkpoint?.draft }
    private var change: MealPlanChange? { review.checkpoint?.submitted == true ? review.checkpoint?.change : proposed }
    private var mergedDays: [MealPlanDay] {
        guard let draft else { return [] }
        return draft.days.map { day in
            let old = existing.first { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) } ?? MealPlanEditingRules.emptyDay(day.date)
            if review.checkpoint?.submitted == true { return change?.after.first { MealPlanEditingRules.dayID($0.date) == MealPlanEditingRules.dayID(day.date) } ?? day }
            let occupied = Set(old.meals.map { MealPlanEditingRules.canonicalSlot($0.mealType) })
            var preview = day
            preview.meals = (replaceExisting ? [] : old.meals) + day.meals.filter { replaceExisting || !occupied.contains(MealPlanEditingRules.canonicalSlot($0.mealType)) }
            return preview
        }
    }
    private var report: MealPlanConstraintReport? {
        draft?.constraints.map { saved in
            var current = saved
            if review.canEdit, let profile = goals.effectiveMealConstraintProfile {
                current.ingredientProfile = profile.adding(diet: saved.effectiveIngredientProfile?.diet ?? .unrestricted,
                    exclusions: saved.effectiveIngredientProfile?.hardExclusions ?? [])
            }
            return MealPlanConstraintRules.report(days: mergedDays, constraints: current)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if review.checkpoint?.submitted == true {
                        Label("Your reviewed plan is kept while saving is resolved.", systemImage: "arrow.triangle.2.circlepath")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    if review.checkpoint?.accepted == true || review.checkpoint?.cancelled == true {
                        Text(review.checkpoint?.accepted == true ? "Week saved" : "Pending save cancelled").appTextRole(.sectionTitle)
                        Text("Close this receipt to load the current saved plan. Later edits stay intact.").appTextRole(.secondary)
                        Button("Done") { finish() }.buttonStyle(AppActionButtonStyle(.primary)).accessibilityIdentifier("planner_draft_finish")
                    } else if isLoading { ProgressView("Checking existing meals") } else if let draft {
                        HStack(alignment: .firstTextBaseline) {
                            Text(draft.title).appTextRole(.sectionTitle)
                            Spacer()
                            Text("\(mergedDays.flatMap(\.meals).count) meals")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        if let report {
                            constraintSummary(report, currency: draft.constraints?.currency ?? "USD")
                        }
                        if review.canEdit, let constraints = draft.constraints {
                            let missing = MealPlanningPreflight.missingSlots(days: mergedDays, constraints: constraints)
                            if !missing.isEmpty {
                                VStack(alignment: .leading, spacing: AppSpacing.row) {
                                    Text("Partial week · \(missing.count) \(missing.count == 1 ? "meal" : "meals") unresolved").appTextRole(.sectionTitle)
                                    Text("Keep the meals that fit. For each gap, allow more cooking time or choose to leave it open.")
                                        .appTextRole(.secondary)
                                    ForEach(missing) { slot in
                                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                            Text("\(slot.date.formatted(date: .abbreviated, time: .omitted)) · \(slot.mealType)").appTextRole(.control)
                                            HStack(spacing: AppSpacing.row) {
                                                Button("Leave open") { leaveOpen(slot) }
                                                    .accessibilityLabel("Leave this meal open")
                                                    .accessibilityIdentifier("planner_leave_open_\(slot.id)")
                                                Spacer(minLength: AppSpacing.compact)
                                                Button("Add 15 cooking minutes") { addCookingTime(slot) }
                                                    .disabled((constraints.practicalWeek?.days.first { $0.offset == slot.dayOffset }?.cookingMinutes ?? 0) >= 480)
                                                    .accessibilityIdentifier("planner_add_cooking_\(slot.id)")
                                            }.appTextRole(.secondary).buttonStyle(.borderless).tint(AppPalette.text).frame(minHeight: 44)
                                        }
                                    }
                                    DisclosureGroup("Review recipe readiness") {
                                        ForEach(MealPlanningPreflight.recipes(recipes.userRecipes, constraints: constraints)) { recipe in
                                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                                Text(recipe.name).appTextRole(.control)
                                                ForEach(recipe.issues, id: \.self) { Text($0).appTextRole(.secondary) }
                                                Button("Review recipe details") { editingRecipe = recipes.userRecipes.first { ($0.id ?? $0.name) == recipe.id } }
                                            }
                                        }
                                    }
                                }.appSurface(.quiet).accessibilityIdentifier("planner_partial_review")
                                regenerateButton
                            }
                        }
                        if change?.after.isEmpty == true {
                            Text("These slots are already planned. Keep the current week, or close this review and build a different brief.").appTextRole(.body)
                        }
                        ForEach(mergedDays) { day in dayCard(day) }
                        DisclosureGroup("Plan options") {
                            VStack(alignment: .leading, spacing: AppSpacing.row) {
                                if draft.lockedMealIDs?.isEmpty != false {
                                    Toggle("Replace existing meals", isOn: $replaceExisting).disabled(!review.canEdit)
                                        .accessibilityIdentifier("planner_draft_replace")
                                } else {
                                    Label("Existing meal slots are locked", systemImage: "lock.fill").appTextRole(.secondary)
                                }
                                Text(replaceExisting ? "Meals shown here will replace the current meals in these dates." : "Your existing meals stay. This plan fills the remaining slots.")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                                if review.canEdit, let constraints = draft.constraints,
                                   MealPlanningPreflight.missingSlots(days: mergedDays, constraints: constraints).isEmpty {
                                    regenerateButton
                                }
                            }.padding(.top, AppSpacing.compact)
                        }.appTextRole(.control).tint(AppPalette.text)

                    }
                }.padding()
            }
            .background(AppPalette.canvas)
            .navigationTitle("Week review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(review.isWorking) }
                if review.canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button { confirmingDiscard = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Discard week draft").accessibilityIdentifier("planner_discard_draft")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .task { await load() }
            .onChange(of: replaceExisting) { _, _ in rebuild() }
            .confirmationDialog("Discard this week draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { if review.closeResolvedOrUnsubmitted() { dismiss() } }
                Button("Keep draft", role: .cancel) {}
            } message: { Text("Your saved meal plan stays intact.") }
            .sheet(item: $editingMeal) { meal in
                if let date = draft?.days.first(where: { $0.meals.contains { $0.id == meal.id } })?.date {
                    PlannedMealEditSheet(meal: meal, date: date) { updated in
                        guard var draft, let day = draft.days.firstIndex(where: { $0.meals.contains { $0.id == updated.id } }),
                              let index = draft.days[day].meals.firstIndex(where: { $0.id == updated.id }) else { throw MealPlanEditError.changed }
                        draft.days[day].meals[index] = updated
                        guard review.updateDraft(draft) else { throw MealPlanEditError.changed }
                        rebuild()
                    }
                }
            }
            .sheet(item: $editingRecipe, onDismiss: { Task { await recipes.fetchUserRecipes() } }) { recipe in
                CreateRecipeView(recipeToEdit: recipe, planningDetailsInitiallyExpanded: true)
            }
        }.interactiveDismissDisabled(review.isWorking)
    }
    private func leaveOpen(_ slot: MealPlanningMissingSlot) {
        guard var draft, let constraints = draft.constraints, review.canEdit else { return }
        do {
            draft.constraints = try MealPlanningPreflight.leavingOpen(slot, in: constraints)
            if review.updateDraft(draft) { rebuild() }
        } catch { self.error = error.localizedDescription }
    }
    private func addCookingTime(_ slot: MealPlanningMissingSlot) {
        guard var draft, var c = draft.constraints, var brief = c.practicalWeek,
              let index = brief.days.firstIndex(where: { $0.offset == slot.dayOffset }), review.canEdit else { return }
        brief.days[index].cookingMinutes = min(480, brief.days[index].cookingMinutes + 15)
        c.practicalWeek = brief; draft.constraints = c
        if review.updateDraft(draft) { rebuild() }
    }
    private func dayCard(_ day: MealPlanDay) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).appTextRole(.control)
            let foods = day.meals.compactMap(\.plannedFood)
            Text("\(Int(foods.reduce(0) { $0+$1.calories }.rounded())) cal · \(Int(foods.reduce(0) { $0+$1.protein }.rounded())) g protein")
                .appTextRole(.secondary).foregroundStyle(.secondary)
            if let brief = draft?.constraints?.practicalWeek,
               let offset = draft?.days.sorted(by: { $0.date < $1.date }).firstIndex(where: { $0.id == day.id }),
               let dayBrief = brief.days.first(where: { $0.offset == offset }) {
                Text(dayBrief.cookingMinutes == 0 ? "No cooking planned" : "Cooking allowance · \(dayBrief.cookingMinutes) min")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if !dayBrief.openMealTypes.isEmpty {
                    Text("Left open · " + dayBrief.openMealTypes.joined(separator: ", ")).appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(day.meals) { meal in
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.mealType).appTextRole(.caption).foregroundStyle(.secondary)
                    Text(meal.foodItem?.name ?? "Planned meal").appTextRole(.control)
                    if draft?.lockedMealIDs?.contains(meal.id) == true {
                        if existing.flatMap(\.meals).contains(where: { $0.id == meal.id }) {
                            Label("Locked existing meal", systemImage: "lock").appTextRole(.caption).foregroundStyle(.secondary)
                        } else if review.canEdit {
                            Button { setLock(meal.id, locked: false) } label: { Label("Locked · tap to unlock", systemImage: "lock.fill") }.frame(minHeight: 44)
                        }
                    } else if review.canEdit, draft?.days.contains(where: { $0.meals.contains { $0.id == meal.id } }) == true {
                        HStack {
                            Button("Adjust portion") { editingMeal = meal }.frame(minHeight: 44)
                            Spacer()
                            Button("Lock meal") { setLock(meal.id, locked: true) }.frame(minHeight: 44)
                        }.appTextRole(.secondary).buttonStyle(.borderless).tint(AppPalette.text)
                    }
                    if let summary = MealPlanCookingRules.summary(for: meal) { Text(summary).appTextRole(.caption).foregroundStyle(.secondary) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).appSurface(.quiet)
    }
    private var footer: some View {
        VStack(spacing: AppSpacing.compact) {
            if let message = error ?? review.errorMessage { Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("planner_draft_error") }
            if review.checkpoint?.submitted == true, review.checkpoint?.accepted != true, review.checkpoint?.cancelled != true {
                Button("Check saved status") { Task { await review.resolve(using: DIContainer.shared.nutritionRepository) } }
                    .frame(minHeight: 44).accessibilityIdentifier("planner_draft_check_status")
                Button("Cancel pending save", role: .destructive) { Task { await review.resolve(using: DIContainer.shared.nutritionRepository, cancelPending: true) } }
                    .frame(minHeight: 44).accessibilityIdentifier("planner_draft_cancel_pending")
            }
            if review.checkpoint?.accepted != true, review.checkpoint?.cancelled != true {
                Text(replaceExisting ? "Replaces existing meals in these dates" : "Keeps your existing meals")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                Button(review.isWorking ? "Saving…" : review.checkpoint?.submitted == true ? "Retry exact save" : "Use this plan") {
                    guard let change else { return }
                    if review.checkpoint?.submitted != true, !review.prepare(change, ingredientProfile: goals.effectiveMealConstraintProfile) { return }
                    Task { if await review.save(using: planner, goalSettings: goals) { finish() } }
                }.buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(isLoading || review.isWorking || isRegenerating || change?.after.isEmpty != false || (review.checkpoint?.submitted != true && report?.canSave == false))
                    .accessibilityIdentifier("planner_use_draft")
            }
        }.padding().background(AppPalette.canvas).disabled(review.isWorking)
    }
    private func constraintSummary(_ report: MealPlanConstraintReport, currency: String) -> some View {
        let blocking = report.issues.filter(\.blocking)
        let notes = report.issues.count - blocking.count
        return VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Label(report.canSave ? "Ready to review" : "Needs your attention",
                      systemImage: report.canSave ? "checkmark.circle" : "exclamationmark.circle")
                    .appTextRole(.control)
                Spacer(minLength: AppSpacing.compact)
                if !blocking.isEmpty {
                    Text("\(blocking.count) checks").appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            if !blocking.isEmpty {
                Text(constraintActionSummary(blocking))
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            if report.unpricedMeals > 0 {
                Text("Cost estimates incomplete · \(report.unpricedMeals) cooking quantities unpriced")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            } else if report.knownWeeklyCost > 0 {
                Text("Estimated cooking cost · \(report.knownWeeklyCost.formatted(.currency(code: currency)))")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
            if !report.issues.isEmpty {
                DisclosureGroup("Review checks\(notes > 0 ? " and \(notes) notes" : "")") {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        ForEach(report.issues) { issue in
                            Label(issue.message, systemImage: issue.blocking ? "exclamationmark.circle" : "info.circle")
                                .appTextRole(.secondary)
                                .foregroundStyle(issue.blocking ? AppPalette.caution : .secondary)
                        }
                    }.padding(.top, AppSpacing.compact)
                }.appTextRole(.secondary).tint(AppPalette.text)
            }
        }.appSurface(.quiet).accessibilityIdentifier("planner_constraint_report")
    }

    private func constraintActionSummary(_ issues: [MealPlanConstraintIssue]) -> String {
        var actions: [String] = []
        func include(_ prefix: String, _ action: String) {
            if issues.contains(where: { $0.id.hasPrefix(prefix) }), !actions.contains(action) { actions.append(action) }
        }
        include("missing-slots-", "Fill the meal gaps below, or leave them open.")
        include("day-prep-", "Review cooking-time estimates for the planned meals.")
        include("prep-", "Review cooking-time estimates for the planned meals.")
        include("day-time-", "Reduce planned cooking or allow more time.")
        include("ingredient-", "Review ingredients against your saved restrictions.")
        include("equipment-", "Review the cooking equipment each meal needs.")
        include("energy-", "Adjust portions to fit your calorie range.")
        include("protein-", "Review protein on the flagged days.")
        include("household-", "Check the cooking quantities for your household.")
        include("price-", "Add recipe prices to check your budget.")
        include("budget", "Adjust cooking quantities to fit your budget.")
        include("nutrition-", "Confirm nutrition for the flagged meals.")
        include("invalid-nutrition-", "Confirm nutrition for the flagged meals.")
        if actions.isEmpty { return "Review the checks below before using this plan." }
        return actions.prefix(2).joined(separator: " ")
    }

    private var regenerateButton: some View {
        Button(isRegenerating ? "Checking new meals…" : "Regenerate unlocked meals") { regenerateGaps() }
            .buttonStyle(AppActionButtonStyle(.secondary))
            .disabled(isRegenerating).accessibilityIdentifier("planner_regenerate_gaps")
    }

    private func setLock(_ id: String, locked: Bool) {
        guard var draft, review.canEdit else { return }
        var ids = draft.lockedMealIDs ?? []
        let group = Set(draft.days.flatMap(\.meals).first { $0.id == id }?.cookingBatch?.allocations.map(\.mealID) ?? [id])
        if locked { ids.formUnion(group) } else { ids.subtract(group) }
        draft.lockedMealIDs = ids
        if review.updateDraft(draft) { replaceExisting = false; rebuild() }
    }
    private func regenerateGaps() {
        guard var draft, var constraints = draft.constraints, let starting = draft.days.first?.date, review.canEdit else { return }
        let originalBasis = try? PlanFingerprint.make(draft)
        if let profile = goals.effectiveMealConstraintProfile {
            constraints.ingredientProfile = profile.adding(diet: constraints.effectiveIngredientProfile?.diet ?? .unrestricted,
                exclusions: constraints.effectiveIngredientProfile?.hardExclusions ?? [])
        }
        draft.constraints = constraints
        let ids = draft.lockedMealIDs ?? []
        let locked = draft.days.map { day -> MealPlanDay in
            var result = day; result.meals = day.meals.filter { ids.contains($0.id) }; return result
        }
        let basis = originalBasis
        let sources = recipes.userRecipes
        isRegenerating = true
        Task { @MainActor in
            defer { isRegenerating = false }
            do {
                var stock: [PantryItem] = [], savedPlans: [MealPlanDay] = []
                if constraints.practicalWeek?.usePreparedStock == true, let owner = review.userID {
                    stock = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
                    savedPlans = try await DIContainer.shared.nutritionRepository.fetchMealPlansForStockReservations(userID: owner)
                }
                draft.days = try await SavedRecipeWeekPlanner.makeAsync(recipes: sources, constraints: constraints,
                    starting: starting, locked: locked, stock: stock, savedPlans: savedPlans, allowPartialReview: true)
                guard try review.checkpoint.map({ try PlanFingerprint.make($0.draft) }) == basis else { throw MealPlanEditError.changed }
                if review.updateDraft(draft) { rebuild() }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func finish() {
        guard let owner = review.userID, DIContainer.shared.authService.currentUserID == owner else { return }
        planner.invalidateCache(for: owner)
        if review.closeResolvedOrUnsubmitted() { didSave(); dismiss() }
    }
    private func rebuild() {
        guard review.canEdit, let draft else { return }
        do { proposed = try MealPlanWeekReviewRules.merging(draft, existing: existing, replace: replaceExisting); error = nil } catch { proposed = nil; self.error = error.localizedDescription }
    }
    private func load() async {
        defer { isLoading = false }
        guard let owner = review.userID, DIContainer.shared.authService.currentUserID == owner, let draft else { return }
        guard review.checkpoint?.submitted != true else { return }
        do {
            planner.invalidateCache(for: owner)
            var days: [MealPlanDay] = []
            for day in draft.days { days.append(try await planner.fetchBasePlanResult(for: day.date, userID: owner).get() ?? MealPlanEditingRules.emptyDay(day.date)) }
            guard DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
            existing = days; rebuild()
        } catch { self.error = MealPlannerErrorText.message(for: error) }
    }
}
