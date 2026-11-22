import Combine
import MyFitPlateCore
import SwiftUI
import UIKit

@MainActor
private enum CookingWorkspaceMemory {
    static var modes: [String: Int] = [:]
}

struct MealPrepCookingView: View {
    @StateObject private var mealPrepService = MealPrepService()

    let days: [MealPlanDay]
    let embedded: Bool
    let planStartDate: Date?
    @StateObject private var cookingProgress: MealCookingCheckpointSession

    @State private var keepScreenOn = true
    @State private var selectedTab: Int
    @State private var timerRemaining: TimeInterval = 0
    @State private var showTimerSheet = false
    @State private var idleTimerStateBeforePresentation: Bool?
    @State private var actualStock: [PantryItem] = []
    @State private var stockLoadError: String?
    @State private var recordingBatch: StockCookRequest?
    @State private var usingStock: PantryItem?
    @State private var pendingStockReview: InventorySaveSession?
    @State private var addingNamedTimer = false
    @State private var namedTimerStepID: String?
    @State private var suggestedRange: StepTimerRange?
    @State private var showingTimers = false
    @StateObject private var speech = CookingStepSpeech()
    @State private var cookingClock = Date()
    @State private var stepLayoutReady = false
    @State private var showingRecipeIngredients = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(days: [MealPlanDay], initialTab: Int = 0, embedded: Bool = false, planStartDate: Date? = nil) {
        self.days = days; self.embedded = embedded; self.planStartDate = planStartDate
        _cookingProgress = StateObject(wrappedValue: MealCookingCheckpointSession(
            userID: DIContainer.shared.authService.currentUserID,
            contextID: MealCookingCheckpointSession.contextID(days: days, starting: planStartDate)))
        let remembered = embedded ? DIContainer.shared.authService.currentUserID.flatMap { CookingWorkspaceMemory.modes[$0] } : nil
        _selectedTab = State(initialValue: remembered ?? min(max(initialTab, 0), 1))
    }

    var body: some View {
        Group {
            if embedded {
                cookingContent
            } else {
                AppSheetScaffold(
                    title: "Meal Prep",
                    subtitle: "Cook the planned quantities, then use your leftovers.",
                    dismiss: { dismiss() }
                ) { cookingContent }
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showTimerSheet) {
            TimerSetupView(initialMinutes: lastTimerMinutes, asksForName: addingNamedTimer) { minutes, name in
                if addingNamedTimer {
                    let instruction = mealPrepService.structuredSteps.first { $0.id == namedTimerStepID }?.text
                    _ = cookingProgress.addNamedTimer(name: name, minutes: minutes, stepID: namedTimerStepID, instruction: instruction)
                } else { startTimer(minutes: minutes) }
                showTimerSheet = false
            }
        }
        .sheet(item: $suggestedRange) { suggestion in
            TimerSetupView(initialMinutes: suggestion.minutes.lowerBound, allowedMinutes: suggestion.minutes,
                           subtitle: suggestion.name + " · Choose \(suggestion.minutes.lowerBound)–\(suggestion.minutes.upperBound) minutes.") { minutes, _ in
                _ = cookingProgress.addNamedTimer(name: suggestion.name, minutes: minutes, stepID: suggestion.id, instruction: suggestion.instruction)
                suggestedRange = nil
            }
        }
        .sheet(item: $recordingBatch, onDismiss: { Task { await loadActualStock() } }) { request in
            StockCookReviewView(batch: request.batch, originalMeal: request.meal)
        }
        .sheet(item: $usingStock, onDismiss: { Task { await loadActualStock() } }) { item in
            StockConsumeReviewView(item: item)
        }
        .sheet(item: $pendingStockReview, onDismiss: { Task { await loadActualStock() } }) { session in
            InventoryOperationReviewView(session: session)
        }
        .sheet(isPresented: $showingTimers) { CookingTimersInspectionView() }
        .task { await loadActualStock() }
        .onAppear {
            aggregateSelection()
            updateTimer()
            if idleTimerStateBeforePresentation == nil {
                idleTimerStateBeforePresentation = UIApplication.shared.isIdleTimerDisabled
            }
            applyIdleTimerPreference()
        }
        .onDisappear {
            speech.stop()
            UIApplication.shared.isIdleTimerDisabled = idleTimerStateBeforePresentation ?? false
            idleTimerStateBeforePresentation = nil
        }
        .onChange(of: keepScreenOn) {
            applyIdleTimerPreference()
        }
        .onChange(of: selectedTab) { _, mode in
            guard embedded, let owner = cookingProgress.userID,
                  DIContainer.shared.authService.currentUserID == owner else { return }
            CookingWorkspaceMemory.modes[owner] = mode
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                updateTimer()
                applyIdleTimerPreference()
            }
        }
        .onReceive(timer) { date in
            updateTimer(now: date)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            updateTimer()
            Task { await CookingNotificationCoordinator.shared.reconcile(userID: cookingProgress.userID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cookingTimersChanged)) { _ in
            cookingProgress.refreshFromDisk()
            aggregateSelection()
            Task { await CookingNotificationCoordinator.shared.reconcile(userID: cookingProgress.userID) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_prep_screen")
    }

    private var cookingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                if let message = cookingProgress.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("meal_prep_checkpoint_error")
                }
                if selectedTab == 0 { prepSummary }
                prepSelection
                modePicker
                if let timer = featuredNamedTimer { featuredTimerControls(timer) }
                if selectedTab == 1 { guidedStep }
                if selectedTab == 0 { ingredientsContent } else { stepsContent }
                Divider()
                actualCookingSection
                namedTimersSection
                cookingTools
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_prep_scroll")
        .safeAreaInset(edge: .bottom) {
            if timerRemaining > 0 || cookingProgress.checkpoint.timerFinished { timerBar }
        }
    }

    private var cookingTools: some View {
        DisclosureGroup("Cooking tools and settings") {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                screenAwakeControl
                PlannedStockReservationsLink()
                Text(cookingProgress.restored ? "Your cooking progress is restored." : "Your steps and timers save automatically.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("meal_prep_checkpoint_status")
                if cookingProgress.checkpoint.legacyCompletedStepIndexes != nil {
                    Text("Earlier checks stay with their original prep session. Identical meals on other dates have separate steps.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("cooking_step_layout_notice")
                }
            }
            .padding(.top, AppSpacing.row)
        }
        .appTextRole(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cooking_tools")
    }

    private var completedStepIndexes: Set<Int> { stepLayoutReady ? cookingProgress.checkpoint.completedStepIndexes : [] }
    private var requirements: [MealCookingRequirement] { MealPlanCookingRules.requirements(from: days, starting: planStartDate) }
    private var selectedRequirements: Set<String> { cookingProgress.checkpoint.selectedRequirementIDs ?? Set(requirements.map(\.id)) }
    private var visibleStepIndexes: [Int] {
        CookingSessionRules.selectedStepIndexes(steps: mealPrepService.structuredSteps, selected: selectedRequirements)
    }
    private var currentStepIndex: Int? { visibleStepIndexes.first { mealPrepService.structuredSteps[$0].id == cookingProgress.checkpoint.currentStepID }
        ?? visibleStepIndexes.first { !completedStepIndexes.contains($0) } ?? visibleStepIndexes.first }
    private var isTimerRunning: Bool { cookingProgress.isRunning }
    private var lastTimerMinutes: Int { cookingProgress.checkpoint.lastTimerMinutes }

    private func aggregateSelection() {
        mealPrepService.aggregate(days: days, starting: planStartDate, selectedRequirementIDs: selectedRequirements)
        stepLayoutReady = cookingProgress.reconcileStepLayout(steps: mealPrepService.structuredSteps,
            legacyStepIDs: CookingSessionRules.legacyStepIDs(requirements: requirements))
    }

    private func prepSourceLabel(requirementID: String, fallback: String) -> String {
        guard let source = requirements.first(where: { $0.id == requirementID }) else { return fallback }
        return "\(source.name) · \(source.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var prepSelection: some View {
        DisclosureGroup("Prep sessions · \(selectedRequirements.count) selected") {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                ForEach(requirements, id: \.id) { requirement in
                    Toggle("\(requirement.name) · \(requirement.date.formatted(date: .abbreviated, time: .omitted))", isOn: Binding(get: {
                        selectedRequirements.contains(requirement.id)
                    }, set: { include in
                        var ids = selectedRequirements
                        if include { ids.insert(requirement.id) } else { ids.remove(requirement.id) }
                        if cookingProgress.selectRequirements(ids, available: Set(requirements.map(\.id))) { aggregateSelection() }
                    })).frame(minHeight: 44).accessibilityIdentifier("cooking_requirement_\(requirement.id)")
                }
                Text("Selection changes only this prep checklist. Plan quantities and physical stock stay unchanged.").appTextRole(.caption)
                let checklist = CookingSessionRules.checklist(requirements: requirements, selected: selectedRequirements,
                    completed: Set(completedStepIndexes.filter { mealPrepService.structuredSteps.indices.contains($0) }.map { mealPrepService.structuredSteps[$0].id }))
                DisclosureGroup("Preview checklist") {
                    Text(checklist).appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("cooking_checklist_preview")
                }
                ShareLink(item: checklist) { Label("Share checklist", systemImage: "square.and.arrow.up") }.frame(minHeight: 44)
                if let json = try? CookingSessionRules.structuredChecklist(requirements: requirements, selected: selectedRequirements),
                   let text = String(data: json, encoding: .utf8) {
                    ShareLink(item: text) { Label("Share structured JSON", systemImage: "curlybraces") }.frame(minHeight: 44)
                }
                Button("Print checklist", systemImage: "printer") {
                    let controller = UIPrintInteractionController.shared
                    let info = UIPrintInfo(dictionary: nil); info.jobName = "Meal prep checklist"; info.outputType = .general
                    controller.printInfo = info; controller.printFormatter = UISimpleTextPrintFormatter(text: checklist)
                    controller.present(animated: true)
                }.frame(minHeight: 44)
            }
        }.appTextRole(.secondary).accessibilityElement(children: .contain)
            .accessibilityIdentifier("cooking_prep_selection")
    }

    @ViewBuilder private var guidedStep: some View {
        if let index = currentStepIndex, mealPrepService.structuredSteps.indices.contains(index) {
            let step = mealPrepService.structuredSteps[index]
            let source = requirements.first { $0.id == step.requirementID }
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                let position = visibleStepIndexes.firstIndex(of: index) ?? 0
                AppSectionHeader(title: "Step \(position + 1) of \(visibleStepIndexes.count)",
                                 subtitle: source.map { "\($0.name) · \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? step.recipeName)
                Text(step.text)
                    .appTextRole(.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack { guidedControls(index: index) }
                    VStack(alignment: .leading) { guidedControls(index: index) }
                }
                Divider()
                guidedReference(step, ingredients: source?.ingredients ?? [])
            }.appSurface(.emphasized).accessibilityElement(children: .contain).accessibilityIdentifier("cooking_current_step")
        }
    }

    @ViewBuilder private func guidedReference(_ step: CookingSessionStep, ingredients: [ParsedIngredient]) -> some View {
        HStack(spacing: AppSpacing.row) {
            if !ingredients.isEmpty {
                Button {
                    showingRecipeIngredients.toggle()
                } label: {
                    Label("Ingredients", systemImage: showingRecipeIngredients ? "chevron.up" : "chevron.down")
                        .frame(minHeight: 44)
                }
                .accessibilityValue(showingRecipeIngredients ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("cooking_step_ingredients")
            }
            Spacer(minLength: 0)
            Button {
                speech.read(step.text)
            } label: {
                Label("Read", systemImage: "speaker.wave.2")
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Read this step")
            stepTimerButton(step)
        }
        .buttonStyle(.borderless)
        .appTextRole(.secondary)
        .foregroundStyle(AppPalette.text)
        .controlSize(.large)
        if showingRecipeIngredients {
            ForEach(ingredients.indices, id: \.self) { index in
                let ingredient = ingredients[index]
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                    Text(ingredient.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(quantityText(ingredient.quantity, unit: ingredient.unit,
                                      known: InventoryQuantityRules.explicitLeadingAmount(ingredient.originalString) != nil))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                .appTextRole(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cooking_step_ingredient_\(index)")
            }
        }
    }

    private struct StepTimerRange: Identifiable {
        let id: String
        let name: String
        let instruction: String
        let minutes: ClosedRange<Int>
    }

    @ViewBuilder private func stepTimerButton(_ step: CookingSessionStep) -> some View {
        let live = cookingProgress.checkpoint.additionalTimers?.contains {
            $0.stepID == step.id && !$0.finished && $0.remaining(now: cookingClock) > 0
        } == true
        let minutes = MealPrepTimerRules.instructionMinutes(step.text)
        let label = minutes.map { $0.lowerBound == $0.upperBound ? "Start \($0.lowerBound) min" : "\($0.lowerBound)–\($0.upperBound) min…" }
        Button {
            if live {
                showingTimers = true
            } else if let minutes {
                let position = (visibleStepIndexes.firstIndex(where: { mealPrepService.structuredSteps[$0].id == step.id }) ?? 0) + 1
                let name = String(("Step \(position) · " + step.recipeName).prefix(80))
                if minutes.lowerBound == minutes.upperBound {
                    _ = cookingProgress.addNamedTimer(name: name, minutes: minutes.lowerBound, stepID: step.id, instruction: step.text)
                } else {
                    suggestedRange = StepTimerRange(id: step.id, name: name, instruction: step.text, minutes: minutes)
                }
            } else {
                namedTimerStepID = step.id
                addingNamedTimer = true
                showTimerSheet = true
            }
        } label: {
            Label(live ? "View timer" : label ?? "Timer", systemImage: "timer")
                .frame(minHeight: 44)
        }
        .accessibilityLabel(live ? "View step timer" : label ?? "Start a timer for this step")
        .accessibilityIdentifier("cooking_start_step_timer")
    }

    @ViewBuilder private func guidedControls(index: Int) -> some View {
        let position = visibleStepIndexes.firstIndex(of: index) ?? 0
        let hasOtherWork = visibleStepIndexes.contains { $0 != index && !completedStepIndexes.contains($0) }
        Button("Previous") { _ = cookingProgress.selectStep(mealPrepService.structuredSteps[visibleStepIndexes[max(0, position-1)]].id) }
            .frame(minHeight: 44).disabled(position == 0).accessibilityIdentifier("cooking_previous_step")
        Button(completedStepIndexes.contains(index) ? "Mark incomplete" : hasOtherWork ? "Complete & next" : "Complete") {
            guard cookingProgress.toggleGuidedStep(index, steps: mealPrepService.structuredSteps, advanceWhenComplete: true) else { return }
            HapticManager.instance.feedback(.medium)
        }
        .buttonStyle(AppActionButtonStyle(.primary, fillsWidth: false))
        .disabled(!stepLayoutReady).accessibilityIdentifier("cooking_complete_current_step")
        Button("Next") { _ = cookingProgress.selectStep(mealPrepService.structuredSteps[visibleStepIndexes[min(visibleStepIndexes.count-1, position+1)]].id) }
            .frame(minHeight: 44).disabled(position >= visibleStepIndexes.count-1).accessibilityIdentifier("cooking_next_step")
    }

    private var batchMeals: [PlannedMeal] {
        var seen = Set<String>()
        return days.flatMap(\.meals).filter { meal in
            guard let batch = meal.cookingBatch else { return false }
            guard selectedRequirements.contains("batch-\(batch.id)") else { return false }
            return seen.insert(batch.id).inserted
        }
    }

    private var actualCookingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(title: "Cooking and leftovers", subtitle: "Your actual stock is separate from the plan.")
            if let stockLoadError { Text(stockLoadError).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
            if batchMeals.isEmpty {
                Text("Edit a planned meal and enable a shared cooking batch to record its cooked portions here.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
            ForEach(batchMeals) { meal in
                if let batch = meal.cookingBatch {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text(batch.name).appTextRole(.control).fixedSize(horizontal: false, vertical: true)
                        if let lot = actualStock.first(where: { $0.cookedBatch?.id == batch.id && $0.creationUndone != true }) {
                            Text("Recorded · \(lot.quantity.formatted(.number.precision(.fractionLength(0...2)))) original portions left")
                                .appTextRole(.secondary).accessibilityIdentifier("inventory_batch_remaining_\(batch.id)")
                            Button("Use or log a portion") { usingStock = lot }
                                .buttonStyle(AppActionButtonStyle(.secondary)).disabled(lot.quantity <= 0 || lot.isArchived == true)
                            if lot.isArchived == true { Text("Archived stock · undo its archive in Stock history to restore it.").appTextRole(.secondary) }
                        } else {
                            Text("\(batch.totalPortions.formatted()) original portions planned · not recorded as cooked")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                            Button("Record batch cooked") { recordingBatch = StockCookRequest(batch: batch, meal: meal) }
                                .buttonStyle(AppActionButtonStyle(.secondary)).disabled(stockLoadError != nil)
                                .accessibilityIdentifier("inventory_record_cooked_\(batch.id)")
                        }
                    }.appSurface(.quiet)
                }
            }
            Button("Resume stock review") {
                let session = InventorySaveSession(userID: DIContainer.shared.authService.currentUserID)
                if session.checkpoint != nil || session.errorMessage != nil { pendingStockReview = session }
            }.frame(minHeight: 44).accessibilityIdentifier("inventory_cook_resume")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inventory_cooking_section")
    }

    private func loadActualStock() async {
        guard let owner = DIContainer.shared.authService.currentUserID else { actualStock = []; return }
        guard owner == cookingProgress.userID else { actualStock = []; stockLoadError = "Return to the account that opened this cooking plan."; return }
        do {
            let loaded = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            actualStock = loaded; stockLoadError = nil
        } catch { stockLoadError = "Couldn't refresh actual stock. Your recorded batches remain saved; try again after reconnecting." }
    }

    /// Keep the live task visible without placing every timer's full editor above
    /// the recipe. Finished timers take priority, then the current step's timer.
    private var featuredNamedTimer: NamedCookingTimer? {
        let timers = cookingProgress.checkpoint.additionalTimers ?? []
        if let finished = timers.first(where: \.finished) { return finished }
        if let index = currentStepIndex {
            let stepID = mealPrepService.structuredSteps[index].id
            if let current = timers.first(where: { $0.stepID == stepID }) { return current }
        }
        return timers.filter { $0.deadline != nil }.min {
            $0.remaining(now: cookingClock) < $1.remaining(now: cookingClock)
        } ?? timers.first
    }

    private func featuredTimerControls(_ timer: NamedCookingTimer) -> some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.compact))
         : AnyLayout(HStackLayout(spacing: AppSpacing.compact))) {
            Button { showingTimers = true } label: {
                HStack(spacing: AppSpacing.compact) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.name).appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                        Text(timer.finished ? "Finished · View timers" : timer.deadline == nil ? "Paused · View timers" : "Running · View timers")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: AppSpacing.compact)
                    Text(timer.finished ? "Done" : MealPrepTimerRules.display(timer.remaining(now: cookingClock)))
                        .appTextRole(.control).monospacedDigit()
                        .foregroundStyle(AppPalette.recovery)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("cooking_featured_timer_reading")
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View cooking timers. \(timer.name)")
            .accessibilityValue(timer.finished ? "Finished" : MealPrepTimerRules.display(timer.remaining(now: cookingClock)))
            .accessibilityIdentifier("cooking_featured_timer_manage")

            if timer.finished {
                Button { _ = cookingProgress.changeNamedTimer(id: timer.id, remove: true) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Clear \(timer.name)")
                .accessibilityIdentifier("cooking_featured_timer_clear")
            } else {
                Button { _ = cookingProgress.changeNamedTimer(id: timer.id) } label: {
                    Image(systemName: timer.deadline == nil ? "play.fill" : "pause.fill")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("\(timer.deadline == nil ? "Resume" : "Pause") \(timer.name)")
                .accessibilityValue(timer.deadline == nil ? "Paused" : "Running")
                .accessibilityIdentifier("cooking_featured_timer_toggle")
            }
        }
        .appSurface(.quiet, padding: AppSpacing.compact, radius: AppRadius.control)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cooking_featured_timer")
    }

    private var namedTimersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            ForEach(cookingProgress.checkpoint.additionalTimers ?? []) { timer in
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Text(timer.name).appTextRole(.control).fixedSize(horizontal: false, vertical: true)
                    Text(timer.finished ? "Finished" : MealPrepTimerRules.display(timer.remaining(now: cookingClock)))
                        .appTextRole(.metric).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if !timer.finished {
                            Button(timer.deadline == nil ? "Resume" : "Pause") { _ = cookingProgress.changeNamedTimer(id: timer.id) }
                                .buttonStyle(AppActionButtonStyle(.secondary))
                                .accessibilityLabel("\(timer.deadline == nil ? "Resume" : "Pause") \(timer.name)")
                        }
                        Button("Clear") { _ = cookingProgress.changeNamedTimer(id: timer.id, remove: true) }
                            .buttonStyle(AppActionButtonStyle(.secondary)).accessibilityLabel("Clear \(timer.name)")
                    }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    HStack {
                        Button("−1 min") { _ = cookingProgress.adjustNamedTimer(id: timer.id, seconds: -60) }.frame(minHeight: 44)
                        Button("+1 min") { _ = cookingProgress.adjustNamedTimer(id: timer.id, seconds: 60) }.frame(minHeight: 44)
                        if let stepID = timer.stepID { Button("Go to step") { _ = cookingProgress.selectStep(stepID); selectedTab = 1 }.frame(minHeight: 44) }
                    }
                }.appSurface(.quiet).accessibilityElement(children: .contain)
                    .accessibilityIdentifier("cooking_named_timer_\(timer.id.uuidString)")
            }
            Button("Add a named cooking timer", systemImage: "timer") {
                addingNamedTimer = true; namedTimerStepID = nil; showTimerSheet = true
            }.frame(minHeight: 44).disabled((cookingProgress.checkpoint.additionalTimers ?? []).count >= 12)
                .accessibilityIdentifier("cooking_add_named_timer")
            Button("All cooking timers and alerts") { showingTimers = true }.frame(minHeight: 44)
        }
    }

    private var prepSummary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Ready to prep")
                .appTextRole(.sectionTitle).accessibilityAddTraits(.isHeader)
            Text("\(recipeCount.formatted()) \(recipeCount == 1 ? "recipe" : "recipes") · \(ingredientCount.formatted()) \(ingredientCount == 1 ? "ingredient" : "ingredients") · \(completedStepIndexes.intersection(visibleStepIndexes).count.formatted()) of \(visibleStepIndexes.count.formatted()) steps complete")
                .appTextRole(.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_prep_summary")
    }

    private var screenAwakeControl: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: keepScreenOn ? "lightbulb.fill" : "lightbulb.slash")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(keepScreenOn ? AppPalette.brandText : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Keep Screen Awake")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                Text("Prevent Auto-Lock during prep")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppSpacing.compact)
            Toggle("Keep Screen Awake", isOn: $keepScreenOn)
                .labelsHidden()
                .tint(AppPalette.brand)
        }
        .padding(AppSpacing.group)
        .background(
            AppPalette.control,
            in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
    }

    private var modePicker: some View {
        HStack(spacing: AppSpacing.row) {
            Picker("Prep mode", selection: $selectedTab) {
                Text("Ingredients").tag(0)
                Text("Steps").tag(1)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("meal_prep_mode_picker")
            if timerRemaining <= 0 && !cookingProgress.checkpoint.timerFinished {
                Button {
                    addingNamedTimer = false
                    showTimerSheet = true
                } label: {
                    Image(systemName: "timer")
                }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Start cooking timer")
                .accessibilityIdentifier("meal_prep_start_timer")
            }
        }
    }

    @ViewBuilder
    private var ingredientsContent: some View {
        if ingredientCount == 0 {
            MealPrepEmptyState(
                icon: "basket",
                title: "No Ingredients Yet",
                message: "Add ingredients to planned meals before opening meal prep."
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppSectionHeader(
                    title: "Bulk Ingredients",
                    subtitle: "Full household batches, counted once. Earlier planned leftovers need no new ingredients."
                )

                ForEach(categoryNames, id: \.self) { category in
                    if let items = mealPrepService.bulkIngredients[category], !items.isEmpty {
                        ingredientSection(category: category, items: items)
                    }
                }
            }
            .accessibilityIdentifier("meal_prep_ingredients")
        }
    }

    private func ingredientSection(category: String, items: [BulkIngredient]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: category,
                subtitle: "\(items.count) item\(items.count == 1 ? "" : "s")"
            )

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    AppListRow(
                        title: item.name,
                        subtitle: recipeUsageText(for: item),
                        hidesTextFromAccessibility: true
                    ) {
                        Text(quantityText(for: item))
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(item.name), \(quantityText(for: item)), \(recipeUsageText(for: item))"
                    )

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, AppSpacing.group)
                    }
                }
            }
            .background(
                AppPalette.control,
                in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var stepsContent: some View {
        if visibleStepIndexes.isEmpty {
            MealPrepEmptyState(
                icon: "list.number",
                title: "No Prep Steps Yet",
                message: "Add instructions to planned meals before opening meal prep."
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(
                    title: "Prep Steps",
                    subtitle: "\(completedStepIndexes.intersection(visibleStepIndexes).count) of \(visibleStepIndexes.count) complete"
                )

                VStack(spacing: 0) {
                    ForEach(visibleStepIndexes, id: \.self) { index in
                        prepStepRow(index: index)

                        if index != visibleStepIndexes.last {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("meal_prep_steps")
        }
    }

    private func prepStepRow(index: Int) -> some View {
        let step = mealPrepService.prepSteps[index]
        let source = prepSourceLabel(requirementID: mealPrepService.structuredSteps[index].requirementID, fallback: step.recipeName)
        let isComplete = completedStepIndexes.contains(index)

        return Button {
            HapticManager.instance.feedback(.light)
            _ = cookingProgress.toggleGuidedStep(index, steps: mealPrepService.structuredSteps)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .appFont(size: 20, weight: .semibold)
                    .foregroundStyle(isComplete ? Color.accentPositive : Color.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(source)
                        .appTextRole(.caption)
                        .foregroundStyle(isComplete ? Color.accentPositive : Color.secondary)
                    Text(step.step)
                        .appTextRole(.body)
                        .foregroundStyle(AppPalette.text)
                        .strikethrough(isComplete, color: .secondary)
                        .opacity(isComplete ? 0.65 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.group)
            .padding(.vertical, AppSpacing.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!stepLayoutReady)
        .accessibilityIdentifier("meal_prep_step_\(index)")
        .accessibilityLabel("Step \(index + 1), \(source), \(step.step)")
        .accessibilityValue(isComplete ? "Complete" : "Not complete")
        .accessibilityHint(isComplete ? "Marks this step incomplete" : "Marks this step complete")
    }

    @ViewBuilder
    private var timerBar: some View {
        if timerRemaining > 0 {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        timerReading
                        HStack(spacing: AppSpacing.compact) {
                            Button(isTimerRunning ? "Pause" : "Resume") {
                                isTimerRunning ? pauseTimer() : resumeTimer()
                            }
                            .buttonStyle(AppActionButtonStyle(.secondary))
                            .accessibilityLabel(isTimerRunning ? "Pause timer" : "Resume timer")
                            Button("Clear", action: clearTimer)
                                .buttonStyle(AppActionButtonStyle(.secondary))
                                .accessibilityLabel("Clear timer")
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                } else {
                    HStack(spacing: AppSpacing.row) {
                        timerReading
                        Spacer(minLength: AppSpacing.compact)
                        Button {
                            isTimerRunning ? pauseTimer() : resumeTimer()
                        } label: {
                            Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(AppIconButtonStyle(.brand))
                        .accessibilityLabel(isTimerRunning ? "Pause timer" : "Resume timer")
                        Button(action: clearTimer) { Image(systemName: "xmark") }
                            .buttonStyle(AppIconButtonStyle(.neutral))
                            .accessibilityLabel("Clear timer")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.compact)
            .background(AppPalette.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("meal_prep_active_timer")
        } else {
            VStack(spacing: AppSpacing.compact) {
                if cookingProgress.checkpoint.timerFinished {
                    Text("Cooking timer finished").appTextRole(.control)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("meal_prep_timer_finished")
                }
                Button {
                    addingNamedTimer = false
                    showTimerSheet = true
                } label: {
                    Label("Start timer", systemImage: "timer")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
                .accessibilityIdentifier("meal_prep_start_timer")
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.compact)
            .background(AppPalette.canvas.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppPalette.separator)
                    .frame(height: 1)
            }
        }
    }

    private var timerReading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isTimerRunning ? "Cooking Timer" : "Timer Paused")
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(MealPrepTimerRules.display(timerRemaining))
                .appTextRole(.metric).foregroundStyle(AppPalette.text).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isTimerRunning ? "Cooking timer" : "Timer paused")
        .accessibilityValue(MealPrepTimerRules.display(timerRemaining))
        .accessibilityIdentifier("meal_prep_timer_reading")
    }

    private var categoryNames: [String] {
        mealPrepService.bulkIngredients.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var ingredientCount: Int {
        mealPrepService.bulkIngredients.values.reduce(0) { $0 + $1.count }
    }

    private var recipeCount: Int {
        requirements.filter { selectedRequirements.contains($0.id) }.count
    }

    private func recipeUsageText(for item: BulkIngredient) -> String {
        let recipes = item.originalRecipes
        if recipes.count == 1 {
            return recipes[0]
        }
        return "Used in \(recipes.count) planned meals"
    }

    private func quantityText(for item: BulkIngredient) -> String {
        quantityText(item.quantity, unit: item.unit, known: !item.quantityUnknown)
    }

    private func quantityText(_ value: Double, unit: String, known: Bool) -> String {
        guard known, value.isFinite, value >= 0 else { return "Amount unconfirmed" }
        let quantity = value.formatted(.number.precision(.fractionLength(0...2)))
        let unit = MealPrepQuantityRules.displayUnit(unit, quantity: value)
        return unit.isEmpty ? quantity : "\(quantity) \(unit)"
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
    }

    private func startTimer(minutes: Int) {
        _ = cookingProgress.startTimer(minutes: minutes)
        updateTimer()
    }

    private func updateTimer(now: Date = Date()) {
        cookingClock = now
        _ = cookingProgress.finishExpiredNamedTimers(now: now)
        timerRemaining = cookingProgress.remaining(now: now)
        if cookingProgress.finishExpiredTimer(now: now) {
            HapticManager.instance.notification(.success)
        }
    }

    private func pauseTimer() {
        _ = cookingProgress.pauseTimer()
        updateTimer()
    }

    private func resumeTimer() {
        _ = cookingProgress.resumeTimer()
        updateTimer()
    }

    private func clearTimer() {
        _ = cookingProgress.clearTimer()
        updateTimer()
    }

}

private struct MealPrepEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: icon)
                .appFont(size: 24, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
                .accessibilityHidden(true)
            Text(title)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.emphasized)
    }
}

struct TimerSetupView: View {
    var onStart: (Int, String) -> Void
    let asksForName: Bool
    let allowedMinutes: ClosedRange<Int>
    let subtitle: String

    @State private var minutes: Int
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(initialMinutes: Int = 10, asksForName: Bool = false, allowedMinutes: ClosedRange<Int> = 1...120,
         subtitle: String = "Choose a duration for the next prep task.", onStart: @escaping (Int, String) -> Void) {
        self.onStart = onStart
        self.asksForName = asksForName
        self.allowedMinutes = allowedMinutes
        self.subtitle = subtitle
        _minutes = State(initialValue: MealPrepTimerRules.clampedMinutes(initialMinutes))
    }

    var body: some View {
        AppSheetScaffold(
            title: "Cooking Timer",
            subtitle: subtitle,
            dismiss: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if asksForName {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text("Timer name").appTextRole(.caption)
                            HStack(spacing: AppSpacing.row) {
                                TextField("Rice, oven, vegetables…", text: $name).textFieldStyle(.roundedBorder)
                                    .focused($nameIsFocused)
                                    .submitLabel(.done)
                                    .onSubmit { nameIsFocused = false }
                                    .accessibilityIdentifier("cooking_timer_name")
                                if nameIsFocused {
                                    Button("Start", action: startTimer)
                                        .buttonStyle(.borderedProminent)
                                        .tint(AppPalette.brand)
                                        .fixedSize()
                                        .disabled(!canStart)
                                        .accessibilityLabel("Start Timer")
                                        .accessibilityIdentifier("meal_prep_timer_start")
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Duration")
                            .appTextRole(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(minutes) min")
                            .appTextRole(.metric)
                            .foregroundStyle(AppPalette.text)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.emphasized)

                    Stepper("Timer Minutes", value: $minutes, in: allowedMinutes, step: 1)
                        .appTextRole(.control)
                        .padding(AppSpacing.group)
                        .background(
                            AppPalette.control,
                            in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous)
                                .stroke(AppPalette.separator, lineWidth: 1)
                        }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cooking_timer_form")
            .safeAreaInset(edge: .bottom) {
                if !nameIsFocused {
                    Button(action: startTimer) { Label("Start Timer", systemImage: "timer") }
                        .buttonStyle(AppActionButtonStyle(.primary))
                        .disabled(!canStart)
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.vertical, AppSpacing.compact)
                        .background(AppPalette.canvas.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { Divider() }
                        .dynamicTypeSize(.xSmall ... .accessibility1)
                        .accessibilityIdentifier("meal_prep_timer_start")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_prep_timer_setup")
    }

    private var canStart: Bool {
        !asksForName || (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80)
    }

    private func startTimer() {
        guard canStart else { return }
        nameIsFocused = false
        onStart(MealPrepTimerRules.clampedMinutes(minutes), name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct StockCookRequest: Identifiable {
    var id: String { batch.id }
    let batch: MealCookingBatch
    let meal: PlannedMeal
}

@MainActor private final class CookingStepSpeech: ObservableObject {
    private var ownsSpeech = false
    func read(_ text: String) { ownsSpeech = true; TTSManager.shared.speak(text) }
    func stop() { if ownsSpeech { TTSManager.shared.stopSpeaking(); ownsSpeech = false } }
}
