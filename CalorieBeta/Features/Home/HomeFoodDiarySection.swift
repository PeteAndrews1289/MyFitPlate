import SwiftUI
import MyFitPlateCore

struct DiaryMealJump: Equatable {
    let id = UUID()
    var mealID: UUID?
}

struct DiaryFoodLoggingTarget: Identifiable {
    let id = UUID()
    let day: DiaryDayContext
    let meal: String?
}

struct HomeFoodDiaryGroupedContent: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    var meals: [Meal]
    var jump: DiaryMealJump?
    let dayContext: DiaryDayContext?
    var selectedDate: Date
    var onDeleteFood: (String) -> Void
    var onAddFood: (String) -> Void
    var onTransferFood: (FoodItem, DiaryTransferMode) -> Void
    var onCopyMeal: (Meal) -> Void
    @State private var collapsedMeals: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(meals) { meal in
                if !meal.foodItems.isEmpty {
                    let mealCalories = meal.foodItems.reduce(0) { $0 + $1.calories }
                    let itemCount = meal.foodItems.count

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            Button {
                                if !collapsedMeals.insert(meal.id).inserted { collapsedMeals.remove(meal.id) }
                            } label: {
                                HStack(spacing: AppSpacing.row) {
                                    Image(systemName: collapsedMeals.contains(meal.id) ? "chevron.right" : "chevron.down")
                                        .appTextRole(.caption).foregroundStyle(.secondary).frame(width: 14)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(meal.name).appTextRole(.sectionTitle)
                                        Text("\(itemCount.formatted()) \(itemCount == 1 ? "item" : "items") · \(Int(mealCalories.rounded()).formatted()) cal")
                                            .appTextRole(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(collapsedMeals.contains(meal.id) ? "Collapsed" : "Expanded")
                            .accessibilityIdentifier("diary_toggle_\(meal.name)")
                            Menu {
                                Button("Copy meal", systemImage: "doc.on.doc") { onCopyMeal(meal) }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Options for \(meal.name)")
                            .accessibilityIdentifier("diary_meal_options_\(meal.name)")
                            Button { onAddFood(meal.name) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Add food to \(meal.name)")
                                .accessibilityIdentifier("diary_add_\(meal.name)")
                        }

                        if !collapsedMeals.contains(meal.id) {
                            VStack(spacing: 0) {
                                ForEach(Array(meal.foodItems.enumerated()), id: \.element.id) { index, foodItem in
                                    HStack(alignment: .top, spacing: 4) {
                                        SwipeableFoodItemView(
                                            initialFoodItem: foodItem,
                                            dailyLog: $dailyLogService.currentDailyLog,
                                            onDelete: { itemID in onDeleteFood(itemID) },
                                            onLogUpdated: { }, date: selectedDate, mealName: meal.name, dayContext: dayContext
                                        )
                                        Menu {
                                            Button("Duplicate serving", systemImage: "plus.square.on.square") { onTransferFood(foodItem, .copy) }
                                            Button("Copy to day or meal…", systemImage: "doc.on.doc") { onTransferFood(foodItem, .copy) }
                                            Button("Move to day or meal…", systemImage: "arrow.right") { onTransferFood(foodItem, .move) }
                                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                        .accessibilityLabel("Copy or move \(foodItem.name)")
                                        .accessibilityIdentifier("diary_food_options_\(foodItem.id)")
                                    }

                                    if index < meal.foodItems.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .id(meal.id)
                }
            }
        }
        .onChange(of: jump) { _, request in
            if let mealID = request?.mealID { collapsedMeals.remove(mealID) }
        }
        .onChange(of: selectedDate) { _, _ in collapsedMeals.removeAll() }
    }
}

struct HomeFoodDiarySection: View {
    @EnvironmentObject var dailyLogService: DailyLogService
    @Binding var foodLoggingTarget: DiaryFoodLoggingTarget?
    let onAddFood: (String?) -> Void
    let jump: DiaryMealJump?
    @State private var savingDayStatus = false
    @State private var dayStatusError: String?
    @State private var transferReview: TransferReview?
    @State private var pendingTransfer: DiaryTransferSession?
    @State private var showingTransferHistory = false
    @State private var transferMessage: String?
    private struct TransferReview: Identifiable { let id = UUID(); let session: DiaryTransferSession }

    var currentLogForDisplay: DailyLog?
    let dayContext: DiaryDayContext?
    var selectedDate: Date
    var isDailyLogSpotlightActive: Bool

    @Binding var showingAddExerciseView: Bool
    @Binding var selectedExerciseForDetail: LoggedExercise?
    @Binding var showingWorkoutDetail: Bool

    var onDeleteFood: (String) -> Void
    var onDeleteExercise: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meals").appTextRole(.sectionTitle)
                    .accessibilityIdentifier("diary_meals_heading")
                Spacer()
                Menu {
                    Button("Copy this day", systemImage: "doc.on.doc") { beginTransfer(mode: .copy) }
                        .disabled(currentLogForDisplay?.meals.flatMap(\.foodItems).isEmpty != false)
                    Button("Select foods to copy", systemImage: "checklist") { beginTransfer(mode: .copy, selectAll: false) }
                        .disabled(currentLogForDisplay?.meals.flatMap(\.foodItems).isEmpty != false)
                    Button("Food changes", systemImage: "clock.arrow.circlepath") { showingTransferHistory = true }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("Daily food options").accessibilityIdentifier("diary_day_options")
                Button {
                    onAddFood(nil)
                } label: {
                    Image(systemName: "plus.circle.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Add food to this day")
                .accessibilityIdentifier("diary_add_food")
            }

            if let pendingTransfer, pendingTransfer.checkpoint != nil || pendingTransfer.isUnreadable {
                Button {
                    transferReview = TransferReview(session: pendingTransfer)
                } label: {
                    Label(pendingTransfer.receipt != nil ? "Finish saved food change" : "Resume food transfer", systemImage: "arrow.left.arrow.right")
                        .appTextRole(.secondary).frame(minHeight: 44)
                }.accessibilityIdentifier("diary_transfer_resume")
            }
            if let transferMessage { Text(transferMessage).appTextRole(.secondary).foregroundStyle(AppPalette.caution) }
            if let currentLogForDisplay {
                if currentLogForDisplay.meals.allSatisfy({ $0.foodItems.isEmpty }) {
                    EmptyDailyLogView(onAddFood: { onAddFood($0) })
                }
                HomeFoodDiaryGroupedContent(meals: currentLogForDisplay.meals, jump: jump, dayContext: dayContext, selectedDate: selectedDate,
                    onDeleteFood: onDeleteFood, onAddFood: onAddFood, onTransferFood: { food, mode in beginTransfer(mode: mode, foodIDs: [food.id]) },
                    onCopyMeal: { meal in beginTransfer(mode: .copy, foodIDs: meal.foodItems.map(\.id)) })

                let dedupedExercises = (currentLogForDisplay.exercises ?? []).dedupedAgainstHealthKit()
                if !dedupedExercises.isEmpty {
                    Divider().padding(.vertical, 8)
                    HomeActivityWidget(exercises: dedupedExercises, showingAddExerciseView: $showingAddExerciseView, selectedExerciseForDetail: $selectedExerciseForDetail, showingWorkoutDetail: $showingWorkoutDetail, onDeleteExercise: onDeleteExercise)
                }
            }
            if currentLogForDisplay == nil {
                Text("No entries loaded for this day.").appTextRole(.secondary).foregroundStyle(.secondary)
            }
            if Calendar.current.startOfDay(for: selectedDate) <= Calendar.current.startOfDay(for: Date()), let log = currentLogForDisplay {
                Divider()
                Menu {
                    ForEach(NutritionDayStatus.allCases, id: \.self) { status in
                        Button(status.title) { saveDayStatus(status) }
                    }
                } label: {
                    HStack {
                        Image(systemName: NutritionDayEvidence.status(of: log) == .complete ? "checkmark.circle" : "circle.dashed")
                        Text(savingDayStatus ? "Saving review…" : "Day: \(NutritionDayEvidence.status(of: log).title)")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .appTextRole(.secondary)
                    .frame(minHeight: 44)
                }
                .disabled(savingDayStatus)
                .accessibilityIdentifier("nutrition_day_review")
                Text("Fully logged means everything you ate is included. Only those days inform coaching averages.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if let dayStatusError { Text(dayStatusError).appTextRole(.caption).foregroundStyle(AppPalette.critical) }
            }
        }
        .frame(maxWidth: 520)
        .padding(.vertical, AppSpacing.compact)
        .featureSpotlight(isActive: isDailyLogSpotlightActive)
        .sheet(item: $foodLoggingTarget) { target in
            if let active = dailyLogService.activelyViewedDayContext,
               active.userID == target.day.userID, active.dayKey == target.day.dayKey,
               active.isOwned(by: DIContainer.shared.authService.currentUserID) {
                FoodSearchView(dailyLog: $dailyLogService.currentDailyLog, searchContext: "diary", selectedMeal: target.meal)
            } else {
                VStack(spacing: AppSpacing.row) {
                    Text("The selected diary has changed.").appTextRole(.control)
                    Button("Return to diary") { foodLoggingTarget = nil }
                }
            }
        }
        .sheet(item: $transferReview, onDismiss: loadPendingTransfer) { review in
            DiaryTransferReviewView(session: review.session)
        }
        .sheet(isPresented: $showingTransferHistory, onDismiss: loadPendingTransfer) {
            if let owner = DIContainer.shared.authService.currentUserID { DiaryTransferHistoryView(userID: owner) }
        }
        .task(id: dailyLogService.activelyViewedDayContext?.userID) { loadPendingTransfer() }
        .onReceive(NotificationCenter.default.publisher(for: DiaryTransferReviewView.didClose)) { note in
            if note.userInfo?["userID"] as? String == DIContainer.shared.authService.currentUserID { loadPendingTransfer() }
        }
    }

    private func loadPendingTransfer() {
        guard let owner = DIContainer.shared.authService.currentUserID else {
            pendingTransfer = nil; transferReview = nil; return
        }
        if let review = transferReview, review.session.userID != owner { transferReview = nil }
        guard transferReview == nil else { return }
        pendingTransfer = DiaryTransferSession(userID: owner)
    }

    private func beginTransfer(mode: DiaryTransferMode, foodIDs: [String]? = nil, selectAll: Bool = true) {
        guard let owner = DIContainer.shared.authService.currentUserID, let log = currentLogForDisplay,
              let source = dailyLogService.diaryDayContext(for: owner, date: selectedDate, existingLog: log) else { return }
        do {
            var draft = try DiaryTransferDraft(source: source, destination: source, sourceLog: log, mode: mode, foodIDs: foodIDs)
            if !selectAll { for index in draft.entries.indices { draft.entries[index].isIncluded = false } }
            let session = DiaryTransferSession(userID: owner, draft: draft)
            pendingTransfer = session
            transferReview = TransferReview(session: session)
            transferMessage = nil
        } catch { transferMessage = error.localizedDescription }
    }

    private func saveDayStatus(_ status: NutritionDayStatus) {
        guard !savingDayStatus, let userID = DIContainer.shared.authService.currentUserID, let reviewedLog = currentLogForDisplay else { return }
        savingDayStatus = true
        dayStatusError = nil
        let reviewedDate = selectedDate
        dailyLogService.setNutritionDayStatus(status, for: userID, date: reviewedDate, reviewedLog: reviewedLog) { success in
            guard DIContainer.shared.authService.currentUserID == userID else { return }
            savingDayStatus = false
            if !success { dayStatusError = "Review wasn't saved. Try again." }
        }
    }
}

struct EmptyDailyLogView: View {
    let onAddFood: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose a meal to log your first food for this day.")
                .appTextRole(.secondary).foregroundStyle(.secondary)
                .padding(.bottom, AppSpacing.compact)
            ForEach(["Breakfast", "Lunch", "Dinner", "Snacks"], id: \.self) { meal in
                Divider()
                Button { onAddFood(meal) } label: {
                    HStack {
                        Text(meal).appTextRole(.control)
                        Spacer()
                        Image(systemName: "plus").foregroundStyle(AppPalette.brandText)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add food to " + meal)
                .accessibilityIdentifier("diary_add_" + meal)
            }
        }
    }
}

struct NutritionDayReviewList: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var logs: [DailyLog] = []
    @State private var ownerID = DIContainer.shared.authService.currentUserID
    @State private var loading = true
    @State private var savingDates: Set<Date> = []
    @State private var message: String?
    @State private var endingDay = Date()
    @State private var dayCount = 21
    @State private var loadID = UUID()
    @State private var selectedDates: Set<String> = []
    @State private var batchReview: NutritionDayBatchReview?
    @State private var showingBatchReview = false
    @State private var pendingBatch: NutritionDayBatchReview?
    @State private var batchReadError = false

    private var windowKey: String { "\(dayCount):\(Calendar.current.startOfDay(for: endingDay).timeIntervalSince1970)" }
    private var currentOwner: Bool { ownerID != nil && ownerID == DIContainer.shared.authService.currentUserID }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Review the food first, then confirm days where everything you ate is included. Partial, changed and unreviewed days stay out of coaching averages.")
                        .appTextRole(.secondary)
                    Picker("Days shown", selection: $dayCount) {
                        Text("Coaching window · 21").tag(21)
                        Text("30 days").tag(30)
                    }.accessibilityIdentifier("review_day_range")
                    DatePicker("Ending", selection: $endingDay, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("review_day_ending")
                    HStack {
                        Button("Earlier", systemImage: "chevron.left") { movePage(-dayCount) }
                            .accessibilityIdentifier("review_days_earlier")
                        Spacer()
                        Button("Later", systemImage: "chevron.right") { movePage(dayCount) }
                            .disabled(Calendar.current.isDateInToday(endingDay))
                            .accessibilityIdentifier("review_days_later")
                    }.buttonStyle(.borderless)
                    if let first = logs.last, let last = logs.first {
                        Text("\(NutritionDayReviewRules.displayDate(first).formatted(date: .abbreviated, time: .omitted)) – \(NutritionDayReviewRules.displayDate(last).formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("review_days_scope")
                    }
                }.disabled(!savingDates.isEmpty)
                if loading { ProgressView("Loading food logs") }
                if let pendingBatch {
                    Section {
                        Button("Continue unfinished review · \(pendingBatch.unresolvedCount) dates") {
                            batchReview = pendingBatch; showingBatchReview = true
                        }.accessibilityIdentifier("review_days_resume")
                        Text("Saved dates are kept. Finish this review before selecting another group.").font(.caption)
                    }
                }
                if !selectedDates.isEmpty {
                    Section {
                        Button("Review \(selectedDates.count) selected days") {
                            guard let ownerID else { return }
                            do {
                                batchReview = try .init(ownerID: ownerID, status: .complete,
                                    logs: logs.filter { selectedDates.contains(NutritionDayReviewRules.key($0) ?? "") })
                                showingBatchReview = true
                            } catch { message = error.localizedDescription }
                        }.disabled(pendingBatch != nil || batchReadError).accessibilityIdentifier("review_days_selected")
                        Button("Clear selection") { selectedDates = [] }
                    }
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary).accessibilityIdentifier("review_days_message")
                        Button("Refresh saved days") { Task { await load() } }.disabled(!savingDates.isEmpty)
                    }
                }
                Section {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                        HStack(spacing: 12) {
                            Button {
                                guard let key = NutritionDayReviewRules.key(log) else { return }
                                if selectedDates.contains(key) { selectedDates.remove(key) } else { selectedDates.insert(key) }
                            } label: {
                                Image(systemName: selectedDates.contains(NutritionDayReviewRules.key(log) ?? "") ? "checkmark.circle.fill" : "circle")
                                    .frame(width: 32, height: 44)
                            }.buttonStyle(.borderless).disabled(loading || !savingDates.isEmpty)
                                .accessibilityLabel("Select \(NutritionDayReviewRules.displayDate(log).formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityIdentifier("review_day_select_\(index)")
                            NavigationLink {
                                NutritionReviewDayDetail(
                                    log: logs.first(where: { $0.id == log.id }) ?? log,
                                    saving: savingDates.contains(log.date),
                                    onReview: { status in save(status, reviewedLog: log) }
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NutritionDayReviewRules.displayDate(log).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    Text("\(log.totalCalories().formatted(.number.precision(.fractionLength(0)))) cal · \(log.meals.flatMap(\.foodItems).count) foods")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let explanation = reviewExplanation(log) {
                                        Text(explanation).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(minHeight: 44)
                            }.accessibilityIdentifier("review_day_detail_\(index)")
                            Menu {
                                ForEach(NutritionDayStatus.allCases, id: \.self) { status in
                                    Button(status.title) { save(status, reviewedLog: log) }
                                        .accessibilityIdentifier("review_status_\(status.rawValue)")
                                }
                            } label: {
                                Text(savingDates.contains(log.date) ? "Saving…" : NutritionDayEvidence.status(of: log).title)
                                    .font(.subheadline).frame(minHeight: 44)
                            }.disabled(savingDates.contains(log.date) || loading)
                                .accessibilityIdentifier("review_day_\(index)")
                        }
                    }
                } footer: {
                    Text("Missing days are unknown, not zero-intake days. A food's accuracy badge does not establish that the whole day is complete. Older declarations without a captured intake revision are retained and labeled.")
                }
            }
            .appFormStyle()
            .navigationTitle("Food-log days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(!savingDates.isEmpty) } }
            .task(id: windowKey) { await load() }
            .sheet(isPresented: $showingBatchReview, onDismiss: { Task { await load() } }) {
                if let batchReview { NutritionBatchReviewView(initial: batchReview) }
            }
        }
        .opacity(currentOwner ? 1 : 0).allowsHitTesting(currentOwner).accessibilityHidden(!currentOwner)
        .interactiveDismissDisabled(!savingDates.isEmpty)
        .onReceive(appState.$isUserLoggedIn) { _ in
            guard !currentOwner else { return }
            loadID = UUID(); logs = []; message = nil; dismiss()
        }
    }

    private func movePage(_ amount: Int) {
        selectedDates = []
        let next = Calendar.current.date(byAdding: .day, value: amount, to: endingDay) ?? endingDay
        endingDay = min(next, Date())
    }
    @MainActor private func load() async {
        guard let userID = ownerID, currentOwner else { loading = false; return }
        do {
            let saved = try EditorDraftStore().load(NutritionDayBatchReview.self, userID: userID, scope: NutritionDayBatchReview.scope)?.value
            pendingBatch = saved.flatMap { $0.ownerID == userID && $0.unresolvedCount > 0 ? $0 : nil }
            batchReadError = false
        } catch { batchReadError = true; message = "Your previous group review couldn't be read. It has been kept; individual day reviews remain available." }
        let request = UUID(); loadID = request
        let count = dayCount, end = min(Calendar.current.startOfDay(for: endingDay), Calendar.current.startOfDay(for: Date()))
        let start = Calendar.current.date(byAdding: .day, value: 1 - count, to: end) ?? end
        let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        loading = true
        let result = await dailyLogService.fetchDailyHistory(for: userID, startDate: start.addingTimeInterval(-172_800), endDate: exclusiveEnd.addingTimeInterval(172_800))
        guard request == loadID, currentOwner, !Task.isCancelled else { return }
        loading = false
        switch result {
        case .failure:
            logs = []; message = "Could not load this range. Your saved food and reviews are unchanged."
        case .success(let values):
            logs = NutritionDayReviewRules.page(values, through: end, count: count)
        }
    }
    private func save(_ status: NutritionDayStatus, reviewedLog: DailyLog) {
        guard let ownerID, currentOwner, !savingDates.contains(reviewedLog.date), !loading else { return }
        savingDates.insert(reviewedLog.date); message = nil
        dailyLogService.setNutritionDayStatus(status, for: ownerID, date: reviewedLog.date, reviewedLog: reviewedLog) { success in
            savingDates.remove(reviewedLog.date)
            guard currentOwner else { return }
            message = success ? "Review saved. Coaching uses confirmed saved evidence." : "The review could not be confirmed, or this day's food changed. Refresh and inspect the current day before retrying."
            Task { await load() }
        }
    }
    private func reviewExplanation(_ log: DailyLog) -> String? {
        if let receipt = log.nutritionDayReview, !NutritionDayReviewRules.isCurrent(receipt, in: log) { return "Changed since review" }
        if log.nutritionDayReview == nil, log.nutritionDayStatus != nil { return "Earlier review · intake revision unknown" }
        if log.meals.flatMap(\.foodItems).isEmpty { return "No recorded food · intake unknown" }
        return nil
    }
}

private struct NutritionReviewDayDetail: View {
    let log: DailyLog
    let saving: Bool
    let onReview: (NutritionDayStatus) -> Void
    var body: some View {
        List {
            Section {
                Text(NutritionDayReviewRules.displayDate(log).formatted(date: .complete, time: .omitted)).font(.headline)
                Text("\(log.totalCalories().formatted(.number.precision(.fractionLength(0)))) calories · \(NutritionDayEvidence.status(of: log).title)")
                if let review = log.nutritionDayReview {
                    Text("Reviewed \(review.reviewedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    if !NutritionDayReviewRules.isCurrent(review, in: log) {
                        Text("Food changed after that review. Inspect the current entries before confirming again.")
                    }
                }
            }
            if log.meals.flatMap(\.foodItems).isEmpty {
                Text("No food is recorded for this day. That does not establish zero intake.")
            }
            ForEach(log.meals) { meal in
                Section(meal.name) {
                    ForEach(Array(meal.foodItems.enumerated()), id: \.offset) { _, food in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                            Text("\(food.calories.formatted(.number.precision(.fractionLength(0)))) cal · \(food.protein.formatted(.number.precision(.fractionLength(0...1)))) g protein")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                ForEach(NutritionDayStatus.allCases, id: \.self) { status in
                    Button(status == .complete ? "Everything I ate is included" : status.title) { onReview(status) }
                        .disabled(saving)
                }
            } footer: {
                Text("This declaration concerns the whole day. Unknown nutrients stay unknown. Returning to the list keeps its selected dates.")
            }
        }.appFormStyle().navigationTitle("Review this day").navigationBarTitleDisplayMode(.inline)
    }
}
