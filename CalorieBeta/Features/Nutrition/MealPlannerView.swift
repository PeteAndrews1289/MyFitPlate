import MyFitPlateCore

import SwiftUI

/// Navigation context lives only for this app session. It never changes a saved plan
/// and is keyed by account so switching tabs cannot borrow another person's date.
@MainActor
private enum MealPlannerSessionContext {
    struct Position { let date: Date; let showingWeek: Bool }
    static var positions: [String: Position] = [:]
}

private struct PlannedMealLoggingReceiptView: View {
    @ObservedObject var review: PlannedMealSaveSession
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var fuelStore: TrainingFuelPlanStore
    @Environment(\.dismiss) private var dismiss
    let onAccepted: () -> Void
    @State private var actualFood: FoodItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(review.checkpoint.date.formatted(date: .complete, time: .omitted))
                        .accessibilityIdentifier("planned_log_destination")
                    if review.restoredReview {
                        Text("Restored your pending review. Later plan edits do not change these saved foods.")
                            .foregroundStyle(.secondary)
                    }
                    if let error = review.errorMessage {
                        Text(error).foregroundStyle(AppPalette.caution).accessibilityIdentifier("planned_log_error")
                    }
                }
                if let target = review.checkpoint.trainingFuelTarget {
                    Section("Training Fuel") {
                        Text("Link these reviewed foods to \(target.sessionTitle). Only accepted diary entries count toward this phase.")
                        if !review.checkpoint.isSubmitted {
                            Button("Log without a fuel link") { _ = review.removeFuelContext() }
                        }
                    }
                }
                ForEach(review.checkpoint.meals) { meal in
                    Section(meal.name) {
                        ForEach(meal.foodItems) { food in
                            VStack(alignment: .leading) {
                                Text(food.name).fontWeight(.semibold)
                                Text("\(ServingNutritionCalculator.displayPortion(food.servingSize)) · \(food.calories.formatted(.number.precision(.fractionLength(0)))) cal")
                                    .foregroundStyle(.secondary)
                                if !review.checkpoint.isSubmitted {
                                    Button("Adjust portions, substitute or skip components") { actualFood = food }.frame(minHeight: 44)
                                        .accessibilityIdentifier("planned_actual_\(food.id)")
                                    Button("Leave this meal out of this log") { _ = review.omitFood(entryID: food.id) }.frame(minHeight: 44)
                                }
                            }
                        }
                    }
                }
                if !review.checkpoint.isSubmitted {
                    Button("Discard this unsubmitted log review", role: .destructive) { if review.discardUnsubmitted() { dismiss() } }.frame(minHeight: 44)
                }
            }.appFormStyle()
            .navigationTitle("Review planned meals")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(review.isSaving) } }
            .safeAreaInset(edge: .bottom) {
                Button(review.isSaving ? "Saving…" : review.checkpoint.isSubmitted ? "Retry reviewed meals" : "Log reviewed meals") {
                    review.save(using: dailyLogService, fuelStore: fuelStore) { accepted in
                        guard accepted else { return }
                        onAccepted(); dismiss()
                    }
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(review.isSaving || review.isAccepted)
                .padding(AppSpacing.screenHorizontal).background(.bar)
                .accessibilityIdentifier("planned_log_action")
            }
            .interactiveDismissDisabled(review.isSaving)
            .sheet(item: $actualFood) { food in
                ActualPlannedFoodReviewView(food: food, date: review.checkpoint.date) { review.updateFood($0, entryID: food.id) }
            }
        }
    }
}

struct MealPlannerView: View {
    private enum Workspace: String, CaseIterable {
        case plan = "Plan", shop = "Shop", cook = "Cook"
    }
    private struct LeftoverRequest: Identifiable {
        let id = UUID()
        let source: MealPlanDay
        let meal: PlannedMeal
    }
    private struct PlannedStockUse: Identifiable {
        let id = UUID()
        let item: PantryItem
        let meal: PlannedMeal
        let date: Date
    }
    private struct SavedWeekLibraryRequest: Identifiable {
        let id = UUID()
        let days: [MealPlanDay]
        let starting: Date
    }
    @ObservedObject private var cookingTimers = CookingTimerRegistry.shared
    @State private var showingCookingTimers = false
    @State private var savedWeekLibrary: SavedWeekLibraryRequest?
    @State private var showingPlanHistory = false
    @State private var observation: PantryPhotoObservationDraft?
    @State private var cameraDate: Date?
    @State private var cameraOwner: String?
    @State private var pendingSavedWeek: MealPlanWeekDraft?
    private struct AlternativeRequest: Identifiable { let id = UUID(); let day: MealPlanDay; let meal: PlannedMeal; let userID: String }
    @State private var alternatives: AlternativeRequest?
    private struct PendingMealChangeRequest: Identifiable { let id = UUID(); let session: MealPlanWeekSaveSession }
    @State private var resumedMealChange: PendingMealChangeRequest?
    @State private var hasPendingMealRemoval = false
    @State private var hasPendingMealChange = false
    @State private var hasPendingPantryObservation = false
    private struct DateJumpRequest: Identifiable { let id = UUID(); let date: Date; let userID: String }
    @State private var dateJump: DateJumpRequest?
    @State private var workspaceOwner: String?
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var spotlightManager: SpotlightManager
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var recipeService: RecipeService
    @EnvironmentObject var workoutService: WorkoutService
    @EnvironmentObject private var trainingFuelPlanStore: TrainingFuelPlanStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var plannedStock: [PantryItem] = []
    @State private var plannedStockError: String?
    @State private var plannedStockLoading = true
    @State private var plannedStockUse: PlannedStockUse?
    @State private var workspace: Workspace = .plan
    @State private var planForSelectedDate: MealPlanDay?
    @State private var isLoading = false
    @State private var loadingMessage = "Checking saved plan"
    @State private var showingMealPlanSurvey = false
    @State private var showingAddMealToPlan = false
    @State private var showingLogDayConfirmation = false
    @State private var showingPantrySheet = false
    @State private var showingDiscardPlanConfirmation = false
    @State private var isDiscardingMealPlan = false
    @State private var discardPlanErrorMessage: String?
    
    @State private var showingImagePicker = false
    @State private var inputImage: UIImage?
    @State private var isAnalyzingImage = false
    @State private var visionRecipes: [VisionRecipe] = []
    @State private var showingVisionResults = false
    @State private var errorMessage: String?

    @State private var regeneratingMealID: String?
    @State private var loggedFoodIDsByDate: [String: Set<String>] = [:]
    @State private var logReadIDs: [String: UUID] = [:]
    @State private var loggingMealID: String?
    @State private var loggedPortionUndo: (id: UUID, entryID: String, date: Date)?
    @State private var mealActionMessage: String?
    @State private var planLoggingReview: PlannedMealSaveSession?
    @State private var isUpdatingPlan = false
    @State private var mealPendingDelete: PlannedMeal?
    @State private var weekPlans: [String: MealPlanDay] = [:]
    @State private var didPrefetchVisibleWeek = false
    @State private var showingWeek = false
    @State private var reusableWeek: MealPlanWeekDraft?
    @State private var pendingWeekReview: MealPlanWeekSaveSession?
    @State private var showingPendingWeekReview = false
    @State private var isLoadingWeek = false
    @State private var weekLoadError: String?
    @State private var planLoadError: String?
    @State private var fetchRequestID = UUID()
    @State private var weekRequestID = UUID()
    @State private var undoAvailable = false
    @State private var editingMeal: PlannedMeal?
    @State private var requestedMealDestination: MealPlannerDestination?
    @State private var coachingOutcome: CoachingActionOutcome?
    @State private var replacingMeal: PlannedMeal?
    @State private var transferRequest: MealPlanTransferRequest?
    @State private var leftoverRequest: LeftoverRequest?
    @State private var pendingLeftoverReview: MealPlanLeftoverSaveSession?
    @State private var showingPendingLeftoverReview = false

    @State private var tourSpotlightIDs: [String] = []
    @State private var currentSpotlightIndex: Int = 0
    @State private var showingSpotlightTour = false

    private let spotlightOrder = ["weekView", "planContent", "toolbarActions"]
    private let spotlightContent: [String: (title: String, text: String)] = [
        "weekView": ("Select a day", "Tap the date to open the week, then choose the day you want."),
        "planContent": ("Your daily plan", "Tap a meal to change its recipe or portion. Its action shows when you can cook or log it."),
        "toolbarActions": ("Meal plan tools", "Add meal opens foods and recipes. More holds week plans, history, and pantry tools.")
    ]

    private var visibleWeekDates: [Date] {
        MealPlanEditingRules.week(containing: selectedDate)
    }

    private var trainingByDay: [String: String] {
        guard let program = workoutService.activeProgram else { return [:] }
        var result: [String: String] = [:]
        for slot in 0..<program.totalSlots {
            if let date = program.date(forSlot: slot), let routine = program.routine(forSlot: slot) {
                result[dateKey(for: date)] = routine.name
            }
        }
        return result
    }

    private var visibleWeekPlans: [MealPlanDay] {
        visibleWeekDates.compactMap { weekPlans[dateKey(for: $0)] }
    }

    private var weekIdentity: String {
        "\(DIContainer.shared.authService.currentUserID ?? "signed-out")-\(dateKey(for: visibleWeekDates.first ?? selectedDate))"
    }

    private var hasVisibleMealPlan: Bool {
        !visibleWeekPlans.isEmpty || planForSelectedDate?.meals.isEmpty == false
    }

    private var weekMealCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: visibleWeekDates.map { date in
            (dateKey(for: date), weekPlans[dateKey(for: date)]?.meals.count ?? 0)
        })
    }

    private var selectedPlanTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today's plan"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: selectedDate))'s plan"
    }

    var body: some View {
        ZStack {
            mainWorkspace
                .mealPlannerPresentationBoundary()
                .background(Color.backgroundPrimary)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showingAddMealToPlan, onDismiss: handlePlanEditDismiss) {
                    AddMealToPlanView(date: selectedDate, isPresented: $showingAddMealToPlan)
                        .environmentObject(mealPlannerService)
                        .environmentObject(dailyLogService)
                        .environmentObject(recipeService)
                }
                .sheet(isPresented: $showingMealPlanSurvey, onDismiss: handlePlanEditDismiss) {
                    MealPlanSurveyView(startingDate: visibleWeekDates.first ?? selectedDate)
                }
                .sheet(item: $reusableWeek, onDismiss: handlePlanEditDismiss) { draft in
                    MealPlanDraftReviewView(draft: draft, didSave: handlePlanEditDismiss)
                }
                .mealPlannerPresentationBoundary()
                .sheet(isPresented: $showingPendingWeekReview, onDismiss: handlePlanEditDismiss) {
                    if let draft = pendingWeekReview?.checkpoint?.draft {
                        MealPlanDraftReviewView(draft: draft, didSave: handlePlanEditDismiss)
                    }
                }
                .sheet(item: $editingMeal, onDismiss: {
                    closeCoachingReview()
                    handlePlanEditDismiss()
                }) { meal in
                    if let plan = planForSelectedDate, let owner = DIContainer.shared.authService.currentUserID {
                        PlannedMealEditSheet(meal: meal, date: plan.date) { updated in
                            if let review = coachingOutcome?.review, review.targetID == meal.id {
                                try review.validate(userID: DIContainer.shared.authService.currentUserID,
                                    currentTargetID: meal.id, currentFingerprint: PlanFingerprint.make(meal))
                            }
                            let change: MealPlanChange
                            if meal.cookingBatch?.allocations.count ?? 0 > 1 {
                                var related: [MealPlanDay] = []
                                for date in MealPlanCookingRules.relatedDates(for: meal) {
                                    let latest = try await mealPlannerService.fetchBasePlanResult(for: date, userID: owner).get()
                                    related.append(latest ?? MealPlanEditingRules.emptyDay(date))
                                }
                                change = try MealPlanCookingRules.editingLinked(updated, original: meal, source: plan, relatedDays: related)
                            } else { change = try MealPlanEditingRules.replacing(updated, in: plan) }
                            let changedDefinitions = MealPlanCookingRules.changedCookingDefinitions(in: change)
                            if !changedDefinitions.isEmpty {
                                let stock = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
                                guard !stock.contains(where: { $0.creationUndone != true && $0.cookedBatch.map { changedDefinitions.contains($0.id) } == true }) else { throw MealCookingError.alreadyCooked }
                            }
                            try await mealPlannerService.applyPlanChange(change, for: owner)
                            acceptCoachingChange(change, mealID: meal.id, owner: owner)
                        }
                    }
                }
                .sheet(item: $replacingMeal, onDismiss: handlePlanEditDismiss) { meal in
                    AddMealToPlanView(date: selectedDate, isPresented: Binding(
                        get: { replacingMeal != nil }, set: { if !$0 { replacingMeal = nil } }
                    ), replacing: meal)
                }
                .sheet(item: $transferRequest, onDismiss: handlePlanEditDismiss) { request in
                    MealPlanTransferSheet(request: request, didSave: handlePlanEditDismiss)
                }
                .mealPlannerPresentationBoundary()
                .sheet(item: $leftoverRequest, onDismiss: refreshPendingLeftoverReview) { request in
                    MealPlanLeftoverSheet(source: request.source, meal: request.meal, didSave: handlePlanEditDismiss)
                }
                .sheet(isPresented: $showingPendingLeftoverReview, onDismiss: refreshPendingLeftoverReview) {
                    if let pendingLeftoverReview {
                        MealPlanLeftoverSheet(resuming: pendingLeftoverReview, didSave: handlePlanEditDismiss)
                    }
                }
                .sheet(isPresented: $showingPantrySheet, onDismiss: { Task { await refreshPlannedStock() } }) {
                    PantryView()
                }
                .sheet(item: $plannedStockUse, onDismiss: {
                    Task { await refreshPlannedStock() }
                }) { request in
                    StockConsumeReviewView(item: request.item, plannedMeal: request.meal, date: request.date,
                        alreadyLogged: isMealLogged(request.meal), trainingFuelTarget: appState.pendingTrainingFuelTarget,
                        onAcceptedFood: { target in
                            if target.context?.requestID == appState.pendingTrainingFuelTarget?.context?.requestID {
                                appState.pendingTrainingFuelTarget = nil
                            }
                            if trainingFuelPlanStore.pendingFoodLinkCount > 0 {
                                mealActionMessage = "Stock and food saved. The Training Fuel link is waiting to retry in Fuel history."
                            }
                        })
                        .onDisappear {
                            refreshLoggedMeals(for: request.date, forceRemote: true)
                        }
                }
                .mealPlannerPresentationBoundary()
                .sheet(item: $savedWeekLibrary, onDismiss: { reusableWeek = pendingSavedWeek; pendingSavedWeek = nil }) { request in
                    SavedMealWeeksView(currentDays: request.days, starting: request.starting) { draft in pendingSavedWeek = draft }
                }
                .sheet(isPresented: $showingPlanHistory, onDismiss: handlePlanEditDismiss) { MealPlanHistoryView() }
                .sheet(isPresented: $showingCookingTimers) { CookingTimersInspectionView() }
                .sheet(item: $dateJump) { request in
                    MealPlannerDateJumpView(date: request.date) { date in
                        guard DIContainer.shared.authService.currentUserID == request.userID else { return }; selectedDate = date
                    }
                }
                .mealPlannerPresentationBoundary()
                .sheet(item: $resumedMealChange, onDismiss: handlePlanEditDismiss) { request in
                    MealPlanOperationReviewView(session: request.session, onFinished: handlePlanEditDismiss)
                }
                .sheet(item: $alternatives, onDismiss: handlePlanEditDismiss) { request in
                    MealAlternativesView(day: request.day, original: request.meal, didFinish: handlePlanEditDismiss)
                }
                .task { await refreshPlannedStock() }
                .onChange(of: workspace) { _, mode in
                    if let owner = workspaceOwner, DIContainer.shared.authService.currentUserID == owner,
                       let key = AccountScopedStorageKey.make(prefix: "meal-planner-workspace", userID: owner) { UserDefaults.standard.set(mode.rawValue, forKey: key) }
                    if mode == .plan { Task { await refreshPlannedStock() } }
                }
                .sheet(item: $planLoggingReview) { review in
                    PlannedMealLoggingReceiptView(review: review) { finishMealLog(review) }
                }
                .mealPlannerPresentationBoundary()

        }
        .overlayPreferenceValue(SpotlightBoundsKey.self) { anchor in
            if showingSpotlightTour, !spotlightManager.isPresentationPaused,
               currentSpotlightIndex < tourSpotlightIDs.count,
               let content = spotlightContent[tourSpotlightIDs[currentSpotlightIndex]] {
                GeometryReader { proxy in
                    SpotlightTourOverlay(
                        targetRect: anchor.map { proxy[$0] },
                        containerSize: proxy.size,
                        content: content,
                        currentIndex: currentSpotlightIndex,
                        total: tourSpotlightIDs.count,
                        onNext: advanceTour,
                        onSkip: finishTour,
                        onBack: { withAnimation(reduceMotion ? nil : AppMotion.standard) { currentSpotlightIndex = max(0, currentSpotlightIndex - 1) } }
                    )
                    .animation(reduceMotion ? nil : AppMotion.standard, value: currentSpotlightIndex)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker { image in
                self.inputImage = image
            }
            .onDisappear {
                if let image = inputImage {
                    analyzePantryImage(image)
                    inputImage = nil
                }
            }
        }
        .sheet(item: $observation, onDismiss: refreshRecoveryTools) { draft in PantryPhotoObservationView(draft: draft) }
        .sheet(isPresented: $showingVisionResults) {
            VisionRecipeResultsView(recipes: visionRecipes, date: selectedDate)
                .environmentObject(dailyLogService)
        }
        .alert("Analysis error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .mealPlannerPresentationBoundary()
        .confirmationDialog(
            "Remove this meal?",
            isPresented: Binding(
                get: { mealPendingDelete != nil },
                set: { if !$0 { mealPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove meal", role: .destructive) {
                if let meal = mealPendingDelete {
                    delete(meal: meal)
                }
                mealPendingDelete = nil
            }

            Button("Cancel", role: .cancel) {
                mealPendingDelete = nil
            }
        } message: {
            Text(mealPendingDelete?.cookingBatch == nil
                 ? mealPendingDelete?.foodItem?.name ?? "This meal will be removed from the selected day."
                 : "Remove this planned portion. Other allocations will be checked and kept. Meals already logged stay unchanged.")
        }
        .confirmationDialog(
            "Log this planned day?",
            isPresented: $showingLogDayConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log planned meals") {
                if let plan = planForSelectedDate {
                    logDay(plan: plan)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This adds the planned meals to the food log for \(selectedDate, formatter: DateFormatter.longDate).")
        }
        .confirmationDialog(
            "Clear this selected meal week?",
            isPresented: $showingDiscardPlanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Review clearing selected week", role: .destructive) {
                discardVisibleMealPlan()
            }
            .accessibilityIdentifier("meal_plan_discard_confirm")

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Review the selected week of \(visibleWeekPlans.flatMap(\.meals).count) planned meals before removing it. " +
                "Pantry items, manual grocery items, and meals already added to your food log stay unchanged."
            )
        }
        .alert(
            "Couldn’t discard meal plan",
            isPresented: Binding(
                get: { discardPlanErrorMessage != nil },
                set: { if !$0 { discardPlanErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                discardPlanErrorMessage = nil
            }
        } message: {
            Text(discardPlanErrorMessage ?? "")
        }
        .mealPlannerPresentationBoundary()
        .onAppear(perform: onMealPlanAppear)
        .onChange(of: appState.pendingMealPlannerDestination) { _, destination in
            guard destination != nil else { return }
            receiveMealDestination()
            fetchPlan()
            refreshWeekOverview()
        }
        .onChange(of: selectedDate) { old, _ in
            mealActionMessage = nil
            loggedPortionUndo = nil
            rememberPosition()
            fetchPlan()
            if MealPlanEditingRules.week(containing: old).first != visibleWeekDates.first { refreshWeekOverview() }
        }
        .onChange(of: showingWeek) { _, _ in rememberPosition() }
        .onChange(of: spotlightManager.replayToken) { _, _ in startMealPlanTourIfNeeded() }
        .onChange(of: spotlightManager.isPresentationPaused) { _, paused in
            if paused { showingSpotlightTour = false } else { startMealPlanTourIfNeeded() }
        }
        .mealPlannerPresentationBoundary()
        .onReceive(NotificationCenter.default.publisher(for: .mealPlanChanged)) { note in
            guard note.object as? String == DIContainer.shared.authService.currentUserID else { return }
            handlePlanEditDismiss()
        }
        .onReceive(dailyLogService.$currentDailyLog) { log in
            guard let log else { return }
            let key = dateKey(for: log.date)
            logReadIDs[key] = nil
            loggedFoodIDsByDate[key] = Set(log.meals.flatMap(\.foodItems).map(\.id))
        }
        .mealPlannerPresentationBoundary()
    }

    /// Cook already displays this session's timers beside the step or in its footer.
    /// Timers from other cooking sessions remain visible in the planner header.
    private var visibleCookingContextID: String? {
        guard workspace == .cook, !isLoadingWeek, weekLoadError == nil else { return nil }
        return MealCookingCheckpointSession.contextID(days: visibleWeekPlans, starting: visibleWeekDates.first ?? selectedDate)
    }

    private var mainWorkspace: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.row) {
                HStack(spacing: AppSpacing.compact) {
                    if workspace == .plan {
                        Button {
                            showingWeek.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Text(showingWeek ? "Week of " + (visibleWeekDates.first ?? selectedDate).formatted(.dateTime.month(.abbreviated).day()) :
                                        selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .appTextRole(.sectionTitle)
                                Image(systemName: showingWeek ? "chevron.up" : "chevron.down").appTextRole(.caption)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showingWeek ? "Show selected day" : "Show week")
                        .accessibilityValue(selectedDate.formatted(date: .complete, time: .omitted))
                        .accessibilityIdentifier("planner_view_mode")
                        .featureSpotlight(isActive: isSpotlightActive(for: "weekView"))
                    } else {
                        Text(workspace == .shop ? "Groceries" : "Cooking").appTextRole(.sectionTitle)
                    }
                    Spacer(minLength: AppSpacing.compact)
                    if workspace == .plan {
                        Button("Add meal", systemImage: "plus") { showingAddMealToPlan = true }
                            .appTextRole(.control).frame(minHeight: 44)
                            .accessibilityIdentifier("meal_plan_add_meal")
                    }
                    mealPlanHeaderActions
                }
                .dynamicTypeSize(.xSmall ... .xxxLarge)
                Picker("Meal planning workspace", selection: $workspace) {
                    ForEach(Workspace.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("planner_workspace")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.compact)
            .padding(.bottom, 4)

            if let owner = DIContainer.shared.authService.currentUserID,
               let nearest = cookingTimers.timers(userID: owner).first(where: { $0.contextID != visibleCookingContextID }) {
                Button { showingCookingTimers = true } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label("\(nearest.name) · \(nearest.remaining(now: context.date) <= 0 ? "Finished" : MealPrepTimerRules.display(nearest.remaining(now: context.date)))", systemImage: "timer")
                            .appTextRole(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }.padding(.horizontal, AppSpacing.screenHorizontal).accessibilityIdentifier("planner_nearest_cooking_timer")
            }

            if let pendingWeekReview, pendingWeekReview.checkpoint != nil {
                Button { showingPendingWeekReview = true } label: {
                    Label("Resume week review", systemImage: "calendar.badge.clock")
                        .appTextRole(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("planner_resume_week_review").padding(.horizontal, AppSpacing.screenHorizontal)
            }

            if let pendingLeftoverReview, pendingLeftoverReview.checkpoint != nil || pendingLeftoverReview.errorMessage != nil {
                Button { showingPendingLeftoverReview = true } label: {
                    Label(pendingLeftoverReview.checkpoint?.accepted == true ? "Review saved leftovers" : "Resume leftover review",
                          systemImage: "tray.and.arrow.down")
                        .appTextRole(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("planner_resume_leftover_review")
                .padding(.horizontal, AppSpacing.screenHorizontal)
            }

            if workspace == .plan {
                mainScrollView
            } else {
                weekNavigation
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                if workspace == .shop {
                    GroceryListView(planStartDate: visibleWeekDates.first ?? selectedDate,
                                    embedded: true, onOpenPantry: { showingPantrySheet = true })
                        .id(weekIdentity)
                } else if isLoadingWeek {
                    ProgressView("Loading meals to cook").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let weekLoadError {
                    VStack(spacing: AppSpacing.row) {
                        Text(weekLoadError).appTextRole(.secondary)
                        Button("Retry") { refreshWeekOverview() }.frame(minHeight: 44)
                    }
                    .padding(AppSpacing.screenHorizontal)
                    .frame(maxHeight: .infinity)
                } else {
                    MealPrepCookingView(days: visibleWeekPlans, embedded: true,
                                        planStartDate: visibleWeekDates.first ?? selectedDate)
                        .id(weekIdentity + "-" + MealCookingCheckpointSession.contextID(
                            days: visibleWeekPlans, starting: visibleWeekDates.first ?? selectedDate))
                }
            }
        }
    }

    @ViewBuilder
    private var mainScrollView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.row) {
                if workoutService.activeProgram?.weekRescue != nil {
                    NavigationLink { WeekRescueView() } label: {
                        Label("Week rescue active · review or undo", systemImage: "calendar.badge.clock")
                            .appTextRole(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.tint(AppPalette.brandText)
                }
                if let trainingFuelTarget = appState.pendingTrainingFuelTarget {
                    TrainingFuelTargetContextView(
                        target: trainingFuelTarget,
                        onDismiss: { appState.pendingTrainingFuelTarget = nil }
                    )
                }

                if showingWeek { weekNavigation }

                if let mealActionMessage {
                    HStack {
                        Text(mealActionMessage).appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("meal_plan_save_status")
                        if let undo = loggedPortionUndo, undo.id == dailyLogService.undoChangeID,
                           dailyLogService.canUndoDiaryChange, Calendar.current.isDate(undo.date, inSameDayAs: selectedDate) {
                            Spacer()
                            Button("Undo", action: undoLoggedPortion)
                                .frame(minHeight: 44).accessibilityIdentifier("planner_undo_logged_portion")
                        }
                    }
                }
                if undoAvailable {
                    Button("Undo last plan change", systemImage: "arrow.uturn.backward", action: undoPlanChange)
                        .disabled(isUpdatingPlan).accessibilityIdentifier("planner_undo")
                }
                if let planLoadError = planLoadError ?? weekLoadError {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        Label(planLoadError, systemImage: "icloud.slash").appTextRole(.secondary)
                        Button("Retry") { handlePlanEditDismiss() }
                    }.appSurface(.quiet).accessibilityIdentifier("planner_load_error")
                }

                if showingWeek {
                    if isLoadingWeek {
                        ProgressView("Loading your week")
                    } else if weekLoadError == nil {
                        MealPlanWeekAgenda(dates: visibleWeekDates, plans: weekPlans, training: trainingByDay) { date in
                            selectedDate = date
                            showingWeek = false
                        }
                    }
                } else {
                    if isLoading {
                        MealPlanLoadingState(message: loadingMessage).padding(.top, 24)
                    } else if let plan = planForSelectedDate, !plan.meals.isEmpty {
                        planContentView(for: plan)
                    } else if planLoadError == nil {
                        MealPlannerEmptyState(onGenerate: { showingMealPlanSurvey = true })
                            .featureSpotlight(isActive: isSpotlightActive(for: "planContent"))
                            .id("planContent")
                    }
                    if let workout = trainingByDay[dateKey(for: selectedDate)] {
                        Label("Training · \(workout)", systemImage: "dumbbell")
                            .appTextRole(.secondary).foregroundStyle(AppPalette.effort)
                    }
                }

            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, 4)
            .padding(.bottom, AppSpacing.section)
        }
    }

    private var weekNavigation: some View {
        HStack(spacing: AppSpacing.compact) {
            calendarJumpButton
            Spacer(minLength: AppSpacing.compact)
            if !Calendar.current.isDateInToday(selectedDate) {
                Button("Today") { selectedDate = Calendar.current.startOfDay(for: Date()); showingWeek = false }
                    .appTextRole(.secondary).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("planner_return_today")
            }
            weekShiftButton(-1)
            weekShiftButton(1)
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var calendarJumpButton: some View {
        Button {
            if let owner = DIContainer.shared.authService.currentUserID { dateJump = .init(date: selectedDate, userID: owner) }
        } label: {
            if let first = visibleWeekDates.first, let last = visibleWeekDates.last {
                let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
                HStack(spacing: 4) {
                    Text("\(first.formatted(.dateTime.month(.abbreviated).day())) – \(sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day()))")
                        .appTextRole(.control).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("planner_week_range")
                    Image(systemName: "chevron.down").appTextRole(.caption).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose meal plan date")
        .accessibilityValue(selectedDate.formatted(date: .complete, time: .omitted))
        .accessibilityIdentifier("planner_choose_date")
    }

    private func weekShiftButton(_ direction: Int) -> some View {
        Button { shiftWeek(direction) } label: { Image(systemName: direction < 0 ? "chevron.left" : "chevron.right") }
            .buttonStyle(AppIconButtonStyle(.plain))
            .accessibilityLabel(direction < 0 ? "Previous week" : "Next week")
            .accessibilityIdentifier(direction < 0 ? "planner_previous_week" : "planner_next_week")
    }

    private func reusePreviousWeek() {
        guard let owner = DIContainer.shared.authService.currentUserID, !isUpdatingPlan else { return }
        let destinations = visibleWeekDates
        isUpdatingPlan = true
        Task { @MainActor in
            defer { isUpdatingPlan = false }
            do {
                var days: [MealPlanDay] = []
                for destination in destinations {
                    guard let previous = Calendar.current.date(byAdding: .day, value: -7, to: destination) else { continue }
                    let source = try await mealPlannerService.fetchBasePlanResult(for: previous, userID: owner).get()
                    var day = MealPlanEditingRules.emptyDay(destination); day.meals = source?.meals ?? []
                    days.append(day)
                }
                guard DIContainer.shared.authService.currentUserID == owner else { return }
                guard days.contains(where: { !$0.meals.isEmpty }) else {
                    mealActionMessage = "No meals were planned in the previous week. Add a meal or create a draft to start."; return
                }
                reusableWeek = MealPlanWeekDraft(days: days, title: "Reuse previous week")
            } catch { mealActionMessage = "Couldn't load the previous week. Your current plan is unchanged." }
        }
    }

    private func shiftWeek(_ direction: Int) {
        if let date = Calendar.current.date(byAdding: .day, value: 7 * direction, to: selectedDate) { selectedDate = date }
    }

    private var mealPlanHeaderActions: some View {
        HStack(spacing: AppSpacing.compact) {
            Menu {
                Button("Go to date", systemImage: "calendar") {
                    if let owner = DIContainer.shared.authService.currentUserID { dateJump = .init(date: selectedDate, userID: owner) }
                }
                if let plan = planForSelectedDate, Calendar.current.startOfDay(for: selectedDate) <= Calendar.current.startOfDay(for: Date()),
                   plan.meals.contains(where: { $0.foodItem != nil && !isMealLogged($0) }) {
                    Button("Log meals for this day", systemImage: "checkmark.circle") { showingLogDayConfirmation = true }
                        .disabled(loggingMealID != nil)
                        .accessibilityIdentifier("meal_plan_log_day")
                }
                Button("Generate week", systemImage: "wand.and.stars") {
                    showingMealPlanSurvey = true
                }
                Button("Reuse previous week", systemImage: "doc.on.doc") { reusePreviousWeek() }
                Button("Saved meal weeks", systemImage: "calendar.badge.clock") {
                    savedWeekLibrary = .init(days: visibleWeekPlans, starting: selectedDate)
                }
                Button("Clear selected day", systemImage: "calendar.badge.minus") {
                    preparePlanRemoval(dates: [selectedDate], title: "Clear selected meal day")
                }
                if hasPendingMealRemoval {
                    Button("Resume meal removal", systemImage: "arrow.clockwise") {
                        let session = MealPlanWeekSaveSession(userID: DIContainer.shared.authService.currentUserID, scope: "meal-plan-removal-review")
                        resumedMealChange = .init(session: session)
                    }
                }
                Button("Plan change history", systemImage: "clock.arrow.circlepath") { showingPlanHistory = true }
                if hasPendingMealChange {
                    Button("Resume meal change", systemImage: "arrow.clockwise") {
                        let session = MealPlanWeekSaveSession(userID: DIContainer.shared.authService.currentUserID, scope: "meal-alternative-review")
                        resumedMealChange = .init(session: session)
                    }
                }
                Button("Cooking timers", systemImage: "timer") { showingCookingTimers = true }
                Button("Open pantry", systemImage: "refrigerator.fill") {
                    showingPantrySheet = true
                }
                Button("Scan pantry", systemImage: "camera") { prepareCamera() }
                if hasPendingPantryObservation {
                    Button("Resume pantry observation", systemImage: "camera.badge.clock") {
                        guard let owner = DIContainer.shared.authService.currentUserID else { return }
                        do {
                            observation = try EditorDraftStore().load(PantryPhotoObservationDraft.self, userID: owner, scope: "pantry-photo-observation")?.value
                        } catch { mealActionMessage = "Your pantry observation couldn't be opened. It is still saved on this device." }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    showingDiscardPlanConfirmation = true
                } label: {
                    Label("Discard meal plan", systemImage: "trash")
                }
                .disabled(!hasVisibleMealPlan || isDiscardingMealPlan)
                .accessibilityIdentifier("meal_plan_discard")
            } label: {
                Group {
                    if isDiscardingMealPlan || isUpdatingPlan {
                        ProgressView()
                            .tint(AppPalette.text)
                    } else {
                        Image(systemName: "ellipsis")
                            .appFont(size: 17, weight: .semibold)
                            .foregroundStyle(AppPalette.text)
                    }
                }
                .frame(width: 44, height: 44)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
            }
            .accessibilityLabel("Meal plan tools")
            .accessibilityIdentifier("meal_plan_tools")
            .featureSpotlight(isActive: isSpotlightActive(for: "toolbarActions"))
            .disabled(isUpdatingPlan || isDiscardingMealPlan)
        }
    }

    @ViewBuilder
    private func planContentView(for plan: MealPlanDay) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            if isUpdatingPlan { ProgressView("Saving plan…") }
            ForEach(MealPlanEditingRules.sorted(plan.meals)) { meal in
                MealCardView(
                    meal: meal,
                    isRegenerating: regeneratingMealID == meal.id,
                    isLogged: isMealLogged(meal),
                    isLogging: loggingMealID == PlannedMealLoggingRules.entryID(for: meal, date: selectedDate),
                    onLog: { log(meal: $0, reviewFirst: true) },
                    onRegenerate: { regenerate(meal: meal) },
                    onDelete: { mealPendingDelete = meal },
                    onEdit: { editingMeal = meal },
                    onSwap: { replacingMeal = meal },
                    onCopy: { transferRequest = MealPlanTransferRequest(source: plan, meals: [meal], moving: false) },
                    onMove: { transferRequest = MealPlanTransferRequest(source: plan, meals: [meal], moving: true) },
                    onPlanLeftovers: planLeftoversAction(for: meal, in: plan),
                    executionAction: mealExecutionAction(meal, date: plan.date),
                    onPrimaryAction: { performMealAction(meal, date: plan.date) }
                )
                .disabled(isUpdatingPlan || loggingMealID != nil)
                if meal.cookingBatch != nil || meal.preparedStock != nil {
                    plannedStockAction(for: meal, date: plan.date)
                }
            }
        }
        .featureSpotlight(isActive: isSpotlightActive(for: "planContent"))
        .id("planContent")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meal_plan_day")
        MealPlanSummaryCard(date: selectedDate, meals: plan.meals, goals: goalSettings)
        Button("Copy this day", systemImage: "doc.on.doc") {
            transferRequest = MealPlanTransferRequest(source: plan, meals: plan.meals, moving: false)
        }.accessibilityIdentifier("planner_copy_day").frame(minHeight: 44)
    }

    private func planLeftoversAction(for meal: PlannedMeal, in source: MealPlanDay) -> (() -> Void)? {
        guard let batch = meal.cookingBatch, batch.unallocatedPortions >= 0.25 else { return nil }
        return { leftoverRequest = LeftoverRequest(source: source, meal: meal) }
    }

    private func mealExecutionAction(_ meal: PlannedMeal, date: Date) -> MealExecutionAction {
        if plannedStockError != nil, meal.cookingBatch != nil || meal.preparedStock != nil { return .checkStock }
        return MealExecutionAction.resolve(meal: meal, date: date, isLogged: isMealLogged(meal),
            stock: plannedStock, stockLoaded: !plannedStockLoading && plannedStockError == nil)
    }

    private func stockItem(for meal: PlannedMeal) -> PantryItem? {
        plannedStock.first { item in
            if let reference = meal.preparedStock { return reference.matches(item, meal: meal) }
            return meal.cookingBatch?.id == item.cookedBatch?.id && item.cookedBatch != nil && item.creationUndone != true
        }
    }

    private func performMealAction(_ meal: PlannedMeal, date: Date) {
        switch mealExecutionAction(meal, date: date) {
        case .review: editingMeal = meal
        case .cook: workspace = .cook
        case .useStock, .recordStockUse:
            if let item = stockItem(for: meal) { plannedStockUse = PlannedStockUse(item: item, meal: meal, date: date) }
        case .log: log(meal: meal)
        case .checkStock: showingPantrySheet = true
        case .logged, .loadingStock: break
        }
    }

    @ViewBuilder
    private func plannedStockAction(for meal: PlannedMeal, date: Date) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            if let plannedStockError {
                Text(plannedStockError).foregroundStyle(AppPalette.caution)
                Button("Retry stock") { Task { await refreshPlannedStock() } }
            } else {
                let action = mealExecutionAction(meal, date: date)
                switch action {
                case .cook:
                    Text("Batch planned · record actual cooking in Cook before using its portions.")
                case .useStock, .recordStockUse:
                    if let item = stockItem(for: meal) {
                        Text("Cooked stock · \(item.availableQuantity.formatted(.number.precision(.fractionLength(0...2)))) original portions available")
                    }
                case .checkStock:
                    Text("Review the cooked stock's amount and availability in Pantry before using it.")
                case .loadingStock: Text("Checking cooked stock…")
                case .logged, .log:
                    Text("This planned portion's stock use is recorded.")
                        .accessibilityIdentifier("planner_stock_used_\(meal.id)")
                case .review:
                    Text(meal.preparedStock == nil ? "Cooking and intake remain separate from this future plan." : "Uses an existing cooked portion, subject to availability when reviewed.")
                }
            }
        }
        .appTextRole(.secondary).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AppSpacing.compact)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner_stock_status_\(meal.id)")
    }

    private func refreshPlannedStock() async {
        guard let owner = DIContainer.shared.authService.currentUserID else { plannedStock = []; plannedStockLoading = false; return }
        plannedStockLoading = true
        defer { plannedStockLoading = false }
        do {
            let loaded = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            plannedStock = loaded; plannedStockError = nil
        } catch { plannedStockError = "Couldn't refresh cooked stock. Your saved food log is unchanged." }
    }

    @ViewBuilder
    private var scanPantryButton: some View {
        Button(action: prepareCamera) {
            AppListRow(
                icon: "camera.macro",
                iconColor: AppPalette.caution,
                title: isAnalyzingImage ? "Chef Maia is analyzing" : "Scan pantry",
                subtitle: isAnalyzingImage ? "Building recipe ideas" : "AI recipe generator"
            ) {
                if isAnalyzingImage {
                    ProgressView()
                        .tint(AppPalette.caution)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, AppSpacing.compact)
            .overlay(alignment: .bottom) { Divider() }
        }
        .buttonStyle(.plain)
        .disabled(isAnalyzingImage)
        .accessibilityIdentifier("meal_plan_scan_pantry")
    }

    private func onMealPlanAppear() {
        workspaceOwner = DIContainer.shared.authService.currentUserID
        refreshRecoveryTools()
        if let owner = workspaceOwner, let position = MealPlannerSessionContext.positions[owner] {
            selectedDate = position.date
            showingWeek = position.showingWeek
        }
        if let owner = workspaceOwner, let key = AccountScopedStorageKey.make(prefix: "meal-planner-workspace", userID: owner),
           let raw = UserDefaults.standard.string(forKey: key), let saved = Workspace(rawValue: raw) { workspace = saved }
        receiveMealDestination()
        pendingWeekReview = MealPlanWeekSaveSession(userID: DIContainer.shared.authService.currentUserID)
        refreshPendingLeftoverReview()
        fetchPlan()
        prefetchVisibleWeekIfNeeded()
        refreshWeekOverview()

        #if DEBUG
        if ScreenshotDemoData.requestedScreen == "pantry-photo-recipes" {
            visionRecipes = [VisionRecipe(title: "Chicken rice bowl", description: "Chicken, rice, and vegetables.",
                                          calories: 520, protein: 38, carbs: 64, fats: 12)]
            showingVisionResults = true
        }
        #endif

        startMealPlanTourIfNeeded()
    }

    private func rememberPosition() {
        guard let owner = workspaceOwner, DIContainer.shared.authService.currentUserID == owner else { return }
        MealPlannerSessionContext.positions[owner] = .init(date: selectedDate, showingWeek: showingWeek)
    }

    private func receiveMealDestination() {
        guard let request = appState.takeMealPlannerDestination() else { return }
        // Consuming the request is navigation only; no meal or stock write occurs.
        workspaceOwner = request.userID
        selectedDate = request.date
        showingWeek = false
        workspace = .plan
        requestedMealDestination = request
        coachingOutcome = request.coachingReview.map { CoachingActionOutcome(review: $0) }
        rememberPosition()
    }

    private func resolveMealDestination(in plan: MealPlanDay?) {
        guard let request = requestedMealDestination else { return }
        requestedMealDestination = nil
        guard request.isAvailable(to: DIContainer.shared.authService.currentUserID),
              Calendar.current.isDate(request.date, inSameDayAs: selectedDate) else { return }
        do {
            if let meal = try request.reviewedMeal(in: plan, currentUserID: DIContainer.shared.authService.currentUserID) {
                editingMeal = meal
            }
        } catch {
            mealActionMessage = error.localizedDescription
        }
    }

    private func acceptCoachingChange(_ change: MealPlanChange, mealID: String, owner: String) {
        guard var outcome = coachingOutcome, outcome.review.day.userID == owner,
              outcome.review.targetID == mealID, DIContainer.shared.authService.currentUserID == owner else { return }
        do {
            try outcome.accept(operationID: change.id.uuidString)
            try CoachingActionHistory().record(outcome, currentUserID: owner)
            coachingOutcome = outcome
        } catch {
            mealActionMessage = "Meal saved. Coaching history couldn't be updated."
        }
    }

    private func closeCoachingReview() {
        guard var outcome = coachingOutcome else { return }
        outcome.close()
        do { try CoachingActionHistory().record(outcome, currentUserID: DIContainer.shared.authService.currentUserID) } catch { mealActionMessage = "Coaching history couldn't be updated. Your meal save status is unchanged." }
        coachingOutcome = nil
    }

    private func startMealPlanTourIfNeeded() {
        guard SpotlightPresentation.isEnabled, !spotlightManager.isPresentationPaused, !showingSpotlightTour else { return }
        let needed = spotlightOrder.filter { !spotlightManager.isShown(id: $0) }
        if !needed.isEmpty {
            self.tourSpotlightIDs = needed
            self.currentSpotlightIndex = 0
            withAnimation(reduceMotion ? nil : AppMotion.standard) {
                self.showingSpotlightTour = true
            }
        }
    }

    private func isSpotlightActive(for id: String) -> Bool {
        guard showingSpotlightTour, !tourSpotlightIDs.isEmpty, currentSpotlightIndex < tourSpotlightIDs.count else {
             return false
        }
        return tourSpotlightIDs[currentSpotlightIndex] == id
    }

    private func advanceTour() {
        if currentSpotlightIndex < tourSpotlightIDs.count - 1 {
            withAnimation(reduceMotion ? nil : AppMotion.standard) {
                currentSpotlightIndex += 1
            }
        } else {
            finishTour()
        }
    }

    private func finishTour() {
        withAnimation(reduceMotion ? nil : AppMotion.standard) {
            showingSpotlightTour = false
        }
        tourSpotlightIDs.forEach { spotlightManager.markAsShown(id: $0) }
    }
    
    private func prepareCamera() {
        cameraDate = selectedDate; cameraOwner = DIContainer.shared.authService.currentUserID; showingImagePicker = true
    }

    private func analyzePantryImage(_ image: UIImage) {
        guard let owner = cameraOwner, DIContainer.shared.authService.currentUserID == owner, let date = cameraDate else { return }
        isAnalyzingImage = true
        PantryVisionService.shared.observeIngredients(image: image) { result in
            DispatchQueue.main.async {
                guard DIContainer.shared.authService.currentUserID == owner else { return }
                self.isAnalyzingImage = false
                switch result {
                case .success(let names):
                    let draft = PantryPhotoObservationDraft(userID: owner, date: date, mealName: "Dinner", ingredients: names)
                    do {
                        if let previous = try EditorDraftStore().load(PantryPhotoObservationDraft.self, userID: owner, scope: "pantry-photo-observation")?.value {
                            self.observation = previous
                            self.mealActionMessage = "Your previous observation is kept. Finish or discard it before replacing it with another photo."
                        } else {
                            try EditorDraftStore().save(draft, userID: owner, scope: "pantry-photo-observation"); self.observation = draft
                        }
                    } catch { self.errorMessage = "The observation could not be kept. Please try again." }
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func fetchPlan() {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            planForSelectedDate = nil; weekPlans = [:]; isLoading = false; undoAvailable = false
            return
        }
        let requestID = UUID(), requestedDate = selectedDate
        fetchRequestID = requestID
        planLoadError = nil
        refreshLoggedMeals()
        undoAvailable = mealPlannerService.lastPlanChange(for: userID) != nil
        planForSelectedDate = mealPlannerService.cachedPlan(for: requestedDate, userID: userID)
        isLoading = planForSelectedDate == nil
        Task { @MainActor in
            let result = await mealPlannerService.fetchPlanResult(for: requestedDate, userID: userID)
            guard DIContainer.shared.authService.currentUserID == userID, fetchRequestID == requestID else { return }
            isLoading = false
            switch result {
            case .success(let plan):
                planForSelectedDate = plan
                updateWeekCache(with: plan, for: requestedDate)
                resolveMealDestination(in: plan)
            case .failure:
                planLoadError = "Couldn't load this plan. Retry before making changes."
            }
        }
    }

    private func prefetchVisibleWeekIfNeeded() {
        guard !didPrefetchVisibleWeek, let userID = DIContainer.shared.authService.currentUserID else { return }
        didPrefetchVisibleWeek = true

        Task {
            await mealPlannerService.prefetchPlans(starting: Date(), userID: userID)
        }
    }

    private func refreshWeekOverview() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        let dates = visibleWeekDates, requestID = UUID()
        weekRequestID = requestID
        isLoadingWeek = true
        weekLoadError = nil
        Task { @MainActor in
            var plans: [String: MealPlanDay] = [:]
            var failed = false
            for date in dates {
                let result = await mealPlannerService.fetchPlanResult(for: date, userID: userID)
                guard DIContainer.shared.authService.currentUserID == userID, weekRequestID == requestID else { return }
                switch result {
                case .success(let plan):
                    if let plan { plans[dateKey(for: date)] = plan }
                case .failure: failed = true
                }
            }
            isLoadingWeek = false
            if failed { weekLoadError = "Some days couldn't load. Retry to see the complete week." } else { weekPlans = plans }
        }
    }

    private func updateWeekCache(with plan: MealPlanDay?, for date: Date) {
        let key = dateKey(for: date)
        if let plan, !plan.meals.isEmpty {
            weekPlans[key] = plan
        } else {
            weekPlans.removeValue(forKey: key)
        }
    }

    private func handlePlanEditDismiss() {
        refreshRecoveryTools()
        pendingWeekReview = MealPlanWeekSaveSession(userID: DIContainer.shared.authService.currentUserID)
        refreshPendingLeftoverReview()
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        // Reopening after a conflict must not re-use the snapshot that caused it.
        mealPlannerService.invalidateCache(for: userID)
        undoAvailable = mealPlannerService.lastPlanChange(for: userID) != nil
        fetchPlan()
        refreshWeekOverview()
    }

    private func refreshRecoveryTools() {
        let owner = DIContainer.shared.authService.currentUserID
        let removal = MealPlanWeekSaveSession(userID: owner, scope: "meal-plan-removal-review")
        let change = MealPlanWeekSaveSession(userID: owner, scope: "meal-alternative-review")
        hasPendingMealRemoval = removal.errorMessage != nil || removal.checkpoint.map { !$0.accepted && !$0.cancelled } == true
        hasPendingMealChange = change.errorMessage != nil || change.checkpoint.map { !$0.accepted && !$0.cancelled } == true
        guard let owner else { hasPendingPantryObservation = false; return }
        do {
            hasPendingPantryObservation = try EditorDraftStore().load(PantryPhotoObservationDraft.self, userID: owner, scope: "pantry-photo-observation") != nil
        } catch { hasPendingPantryObservation = true }
    }

    private func refreshPendingLeftoverReview() {
        guard !showingPendingLeftoverReview else { return }
        let review = MealPlanLeftoverSaveSession(userID: DIContainer.shared.authService.currentUserID)
        pendingLeftoverReview = review.checkpoint != nil || review.errorMessage != nil ? review : nil
    }

    private func discardVisibleMealPlan() {
        preparePlanRemoval(dates: visibleWeekDates, title: "Clear selected meal week")
    }

    private func preparePlanRemoval(dates: [Date], title: String) {
        guard let owner = DIContainer.shared.authService.currentUserID, !isDiscardingMealPlan else { return }
        let pending = MealPlanWeekSaveSession(userID: owner, scope: "meal-plan-removal-review")
        if pending.checkpoint != nil { resumedMealChange = .init(session: pending); return }
        isDiscardingMealPlan = true
        Task { @MainActor in
            defer { isDiscardingMealPlan = false }
            do {
                var days: [MealPlanDay] = []
                for date in dates {
                    days.append(try await mealPlannerService.fetchBasePlanResult(for: date, userID: owner).get() ?? MealPlanEditingRules.emptyDay(date))
                }
                let selected = Set(days.flatMap(\.meals).map(\.id))
                let related = days.flatMap(\.meals).flatMap(MealPlanCookingRules.relatedDates)
                for date in related where !days.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    days.append(try await mealPlannerService.fetchBasePlanResult(for: date, userID: owner).get() ?? MealPlanEditingRules.emptyDay(date))
                }
                let change = try MealPlanHistoryRules.removing(mealIDs: selected, from: days, title: title)
                let session = MealPlanWeekSaveSession(userID: owner, draft: .init(days: change.after, title: title), scope: "meal-plan-removal-review")
                guard session.prepare(change) else { throw MealPlanEditError.changed }
                resumedMealChange = .init(session: session)
            } catch { discardPlanErrorMessage = error.localizedDescription }
        }
    }

    private func log(meal: PlannedMeal, reviewFirst: Bool = false) {
        guard let userID = DIContainer.shared.authService.currentUserID, loggingMealID == nil, !isMealLogged(meal) else { return }
        let date = selectedDate
        guard let food = PlannedMealLoggingRules.food(for: meal, date: date) else {
            mealActionMessage = "Add a food or recipe to this meal to review its nutrition before logging."
            editingMeal = meal
            return
        }
        let review = PlannedMealSaveSession(userID: userID, date: date,
            meals: [Meal(name: meal.mealType, foodItems: [food])], trainingFuelTarget: appState.pendingTrainingFuelTarget)
        if reviewFirst || review.restoredReview || review.errorMessage != nil || review.checkpoint.trainingFuelTarget != nil
            || meal.plannedFood?.loggingPortionNotice() != nil {
            planLoggingReview = review
            return
        }
        let previousUndoID = dailyLogService.undoChangeID
        loggingMealID = food.id
        review.save(using: dailyLogService) { accepted in
            loggingMealID = nil
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            guard accepted else { planLoggingReview = review; return }
            finishMealLog(review)
            if let id = dailyLogService.undoID(forAddedFoods: [food.id], userID: userID), id != previousUndoID {
                loggedPortionUndo = (id, food.id, date)
            }
        }
    }

    private func finishMealLog(_ review: PlannedMealSaveSession) {
        guard DIContainer.shared.authService.currentUserID == review.userID else { return }
        let checkpoint = review.checkpoint
        let key = dateKey(for: checkpoint.date)
        logReadIDs[key] = nil
        loggedFoodIDsByDate[key, default: []].formUnion(checkpoint.meals.flatMap(\.foodItems).map(\.id))
        loggedPortionUndo = nil
        let destination = checkpoint.meals.count == 1 ? checkpoint.meals[0].name : "diary"
        mealActionMessage = "Logged to " + destination + " · " + checkpoint.date.formatted(date: .abbreviated, time: .omitted)
        if let target = checkpoint.trainingFuelTarget,
           target.context?.requestID == appState.pendingTrainingFuelTarget?.context?.requestID {
            appState.pendingTrainingFuelTarget = nil
            if trainingFuelPlanStore.pendingFoodLinkCount > 0 {
                mealActionMessage = "Meals logged. The Training Fuel link is waiting to retry in Fuel history."
            }
        }
    }

    private func undoLoggedPortion() {
        guard let owner = DIContainer.shared.authService.currentUserID, let undo = loggedPortionUndo,
              dailyLogService.undoID(forAddedFoods: [undo.entryID], userID: owner) == undo.id else { return }
        dailyLogService.undoLastDiaryChange(for: owner) { accepted in
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            if accepted {
                loggedPortionUndo = nil
                let key = dateKey(for: undo.date)
                logReadIDs[key] = nil
                loggedFoodIDsByDate[key]?.remove(undo.entryID)
                mealActionMessage = "Food log undone."
            } else {
                mealActionMessage = dailyLogService.undoErrorMessage ?? "Couldn't undo this portion. Try again."
            }
        }
    }

    private func logDay(plan: MealPlanDay) {
        guard let userID = DIContainer.shared.authService.currentUserID, loggingMealID == nil else { return }
        let destination = selectedDate
        let unloggedMeals = plan.meals.filter { !isMealLogged($0) }
        let unresolved = unloggedMeals.filter { PlannedMealLoggingRules.food(for: $0, date: destination) == nil }
        guard unresolved.isEmpty else {
            mealActionMessage = "\(unresolved.count) planned meals need reviewed nutrition. Add a food or recipe in Edit meal before logging the day. Nothing has been logged."
            editingMeal = unresolved.first
            return
        }

        let mealGroups: [(mealName: String, foodItems: [FoodItem])] = plan.meals.compactMap { meal in
            guard !isMealLogged(meal), let foodItem = PlannedMealLoggingRules.food(for: meal, date: destination) else { return nil }
            return (mealName: meal.mealType, foodItems: [foodItem])
        }

        guard !mealGroups.isEmpty else { return }
        planLoggingReview = PlannedMealSaveSession(userID: userID, date: destination,
            meals: mealGroups.map { Meal(name: $0.mealName, foodItems: $0.foodItems) })
    }

    private func isMealLogged(_ meal: PlannedMeal) -> Bool {
        let ids = loggedFoodIDsByDate[dateKey(for: selectedDate)] ?? []
        return PlannedMealLoggingRules.isLogged(meal, date: selectedDate, loggedFoodIDs: ids)
    }

    private func refreshLoggedMeals(for requestedDate: Date? = nil, forceRemote: Bool = false) {
        guard let userID = DIContainer.shared.authService.currentUserID else { loggedFoodIDsByDate = [:]; return }
        let date = requestedDate ?? selectedDate
        let key = dateKey(for: date)
        let requestID = UUID()
        logReadIDs[key] = requestID
        if !forceRemote, let log = dailyLogService.currentDailyLog, Calendar.current.isDate(log.date, inSameDayAs: date) {
            loggedFoodIDsByDate[key] = Set(log.meals.flatMap(\.foodItems).map(\.id))
            return
        }
        DIContainer.shared.nutritionRepository.fetchLogInternal(userID: userID, date: date) { result in
            DispatchQueue.main.async {
                guard DIContainer.shared.authService.currentUserID == userID, logReadIDs[key] == requestID else { return }
                if case .success(let log) = result {
                    loggedFoodIDsByDate[key] = Set(log.meals.flatMap(\.foodItems).map(\.id))
                }
            }
        }
    }

    private func delete(meal: PlannedMeal) {
        guard let userID = DIContainer.shared.authService.currentUserID,
              let original = planForSelectedDate, !isUpdatingPlan else { return }
        isUpdatingPlan = true
        Task { @MainActor in
            defer { isUpdatingPlan = false }
            do {
                let change: MealPlanChange
                if meal.cookingBatch != nil {
                    var relatedDays = [original]
                    for date in MealPlanCookingRules.relatedDates(for: meal)
                    where !Calendar.current.isDate(date, inSameDayAs: original.date) {
                        let related = try await mealPlannerService.fetchBasePlanResult(for: date, userID: userID).get()
                            ?? MealPlanEditingRules.emptyDay(date)
                        relatedDays.append(related)
                    }
                    guard DIContainer.shared.authService.currentUserID == userID else { throw MealPlanEditError.accountChanged }
                    change = try MealPlanCookingRules.removing(meal: meal, source: original, relatedDays: relatedDays)
                } else {
                    var updated = original
                    updated.meals.removeAll { $0.id == meal.id }
                    change = MealPlanChange(title: "Meal removed", before: [original], after: [updated])
                }
                let existing = MealPlanWeekSaveSession(userID: userID, scope: "meal-plan-removal-review")
                if existing.checkpoint != nil {
                    resumedMealChange = .init(session: existing); mealActionMessage = "Finish the pending removal before starting another."; return
                }
                let session = MealPlanWeekSaveSession(userID: userID, draft: .init(days: change.after, title: change.title), scope: "meal-plan-removal-review")
                guard session.prepare(change) else { throw MealPlanEditError.changed }
                guard await session.save(using: mealPlannerService) else {
                    resumedMealChange = .init(session: session); mealActionMessage = "This exact removal is kept. Check its saved status or retry."; return
                }
                _ = session.closeResolvedOrUnsubmitted()
                guard DIContainer.shared.authService.currentUserID == userID else { return }
                mealActionMessage = "Meal removed. You can undo this change."
                handlePlanEditDismiss()
            } catch { mealActionMessage = MealPlannerErrorText.message(for: error) }
        }
    }

    private func undoPlanChange() {
        guard let owner = DIContainer.shared.authService.currentUserID, !isUpdatingPlan else { return }
        isUpdatingPlan = true
        Task { @MainActor in
            defer { isUpdatingPlan = false }
            do {
                try await mealPlannerService.undoLastPlanChange(for: owner)
                guard DIContainer.shared.authService.currentUserID == owner else { return }
                mealActionMessage = "Plan change undone."
                handlePlanEditDismiss()
            } catch { mealActionMessage = MealPlannerErrorText.message(for: error) }
        }
    }

    private func regenerate(meal: PlannedMeal) {
        guard let owner = DIContainer.shared.authService.currentUserID, let day = planForSelectedDate, !isUpdatingPlan else { return }
        alternatives = .init(day: day, meal: meal, userID: owner)
    }

}

private extension View {
    /// Limit generic metadata depth: the unbroken planner presentation chain
    /// overflowed Swift's type decoder stack on a physical device. Keep these
    /// stable boundaries as new sheets and lifecycle modifiers are added.
    func mealPlannerPresentationBoundary() -> AnyView { AnyView(self) }
}

// MARK: - Pantry Vision Service & Views

struct VisionRecipe: Codable, Identifiable {
    var id: String { title }
    let title: String
    let description: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fats: Double
}

struct VisionRecipeResponse: Codable {
    let recipes: [VisionRecipe]
}

class PantryVisionService {
    static let shared = PantryVisionService()
    private init() {}
    
    func observeIngredients(image: UIImage, completion: @escaping (Result<[String], Error>) -> Void) {
        guard let data = image.aiPreparedJPEGData() else { completion(.failure(ImageRecognitionError.imageProcessingError)); return }
        let messages: [[String: Any]] = [["role": "user", "content": [
            ["type": "text", "text": "Identify only visible edible pantry/fridge ingredients. Do not infer hidden items or amounts. Return JSON {\"ingredients\":[\"name\"]}, at most 40. Return empty array for unrelated/unusable images."],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())", "detail": "high"]]
        ]]]
        Task {
            let result = await AIService.shared.performRequest(messages: messages, model: "gpt-6-luna", maxTokens: 1_600, responseFormat: ["type": "json_object"], requestKind: .pantryObservation, retryCount: 0)
            do {
                let raw = try result.get().replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                struct Response: Decodable { let ingredients: [String] }
                let value = try JSONDecoder().decode(Response.self, from: Data(raw.utf8))
                let names = Array(Set(value.ingredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= 200 })).sorted()
                guard !names.isEmpty, names.count <= 40 else { throw ImageRecognitionError.invalidOutputFormat }
                completion(.success(names))
            } catch { completion(.failure(error)) }
        }
    }

    func generateRecipesFromImage(image: UIImage, retryCount: Int = 1, completion: @escaping (Result<[VisionRecipe], Error>) -> Void) {
        guard let imageData = image.aiPreparedJPEGData() else {
            completion(.failure(ImageRecognitionError.imageProcessingError))
            return
        }
        let base64Image = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        
        let prompt = """
        You are a master chef and a nutritional expert. Analyze the provided image of a pantry, fridge, or ingredients.
        Identify all the edible ingredients you can see.
        Generate exactly 3 healthy, unique recipes that primarily use these ingredients.
        Your response MUST be a valid JSON object.
        Root key MUST be "recipes" (an array of objects).
        Each object MUST have the following keys:
        - "title" (String): The name of the recipe.
        - "description" (String): A short 1-2 sentence description of how to make it with the ingredients seen.
        - "calories" (Double): Estimated total calories for one serving.
        - "protein" (Double): Estimated total protein (g).
        - "carbs" (Double): Estimated total carbs (g).
        - "fats" (Double): Estimated total fats (g).
        """
        
        let messages: [[String: Any]] = [
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": base64Image, "detail": "high"]]
                ]
            ]
        ]
        
        Task {
            let result = await AIService.shared.performRequest(
                messages: messages,
                model: "gpt-6-luna",
                maxTokens: 2_400,
                responseFormat: ["type": "json_object"],
                requestKind: .recipePhoto,
                retryCount: 0
            )
            
            switch result {
            case .success(let jsonString):
                let cleanedContent = jsonString.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let contentData = cleanedContent.data(using: .utf8) else {
                    if retryCount > 0 {
                        self.generateRecipesFromImage(image: image, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(.failure(ImageRecognitionError.invalidOutputFormat))
                    }
                    return
                }
                
                do {
                    let decodedResponse = try JSONDecoder().decode(VisionRecipeResponse.self, from: contentData)
                    DispatchQueue.main.async { completion(.success(decodedResponse.recipes)) }
                } catch {
                    if retryCount > 0 {
                        self.generateRecipesFromImage(image: image, retryCount: retryCount - 1, completion: completion)
                    } else {
                        completion(.failure(ImageRecognitionError.decodingError(error)))
                    }
                }
                
            case .failure(let error):
                completion(.failure(ImageRecognitionError.networkError(error)))
            }
        }
    }
}

struct VisionRecipeResultsView: View {
    let recipes: [VisionRecipe]
    let date: Date
    @State private var selected: PantryIdeaRequest?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("These are recipe ideas, not evidence of measured pantry stock. Review ingredients, yield and the explicit destination before saving, planning or logging.")
                ForEach(recipes) { idea in
                    Button(idea.title) {
                        let recipe = Recipe(name: idea.title, ingredients: ["Ingredient quantities unconfirmed"], instructions: [idea.description],
                            nutrition: Nutrition(calories: idea.calories, protein: idea.protein, carbs: idea.carbs, fats: idea.fats),
                            servings: 1, nutritionBasis: .perServing, nutritionOrigin: .aiEstimate, nutritionNeedsReview: true)
                        selected = .init(recipe: recipe, date: date, meal: "Dinner")
                    }.frame(minHeight: 44)
                }
            }.appFormStyle().navigationTitle("Recipe ideas").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.sheet(item: $selected) { request in PantryRecipeIdeaReviewView(recipe: request.recipe, stock: [], date: request.date, meal: request.meal) }
    }
}
