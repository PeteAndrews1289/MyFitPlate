import SwiftUI
import MyFitPlateCore

struct FoodLoggingDraftView: View {
    @ObservedObject var model: FoodSearchViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dailyLogService: DailyLogService
    @State private var confirmingDiscard = false
    @State private var editingEntry: FoodLoggingDraft.Entry?

    var body: some View {
        NavigationStack {
            Form {
                if let draft = model.mealDraft {
                    if let target = draft.trainingFuelTarget { TrainingFuelTargetContextView(target: target, onDismiss: draft.isSubmitted || model.isSavingDraft ? nil : { _ = model.updateMealDraft { $0.trainingFuelTarget = nil } }) }
                    Section("Add to") {
                        Picker("Meal", selection: Binding(get: { draft.mealName }, set: { value in
                            model.updateMealDraft { $0.mealName = value }
                        })) {
                            ForEach(["Breakfast", "Lunch", "Dinner", "Snacks"], id: \.self) { Text($0) }
                        }
                        .accessibilityIdentifier("meal_draft_destination")
                        DatePicker("Date", selection: Binding(get: { draft.date }, set: { value in
                            model.updateMealDraft { $0.date = Calendar.current.startOfDay(for: value) }
                        }), displayedComponents: .date)
                    }
                    .disabled(draft.isSubmitted || model.isSavingDraft)

                    Section("Foods") {
                        ForEach(Array(draft.entries.enumerated()), id: \.element.id) { index, entry in
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Button { editingEntry = entry } label: {
                                    HStack(alignment: .top, spacing: AppSpacing.row) {
                                        Text(FoodEmojiMapper.getEmoji(for: entry.food.name))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.food.name).foregroundStyle(AppPalette.text).fontWeight(.semibold)
                                            Text(entry.preparedFood?.servingSize ?? entry.food.servingSize)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Review nutrition and serving")
                                .accessibilityIdentifier("meal_draft_edit_\(index)")
                                Stepper(value: Binding(get: { entry.multiplier }, set: { value in
                                    model.updateMealDraft { $0.entries[index].multiplier = value }
                                }), in: 0.25...10, step: 0.25) {
                                    Text("\(entry.multiplier.formatted(.number.precision(.fractionLength(0...2)))) × original amount")
                                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityIdentifier("meal_draft_serving_\(index)")
                                HStack {
                                    Text("\(Int((entry.preparedFood?.calories ?? 0).rounded()).formatted()) cal")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                    Spacer()
                                    Button("Remove", role: .destructive) {
                                        model.updateMealDraft { $0.entries.removeAll { $0.id == entry.id } }
                                    }
                                    .buttonStyle(AppListButtonStyle())
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("Remove \(entry.food.name)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .disabled(draft.isSubmitted || model.isSavingDraft)

                    Section {
                        Text("\(draft.foods.count) \(draft.foods.count == 1 ? "food" : "foods") · \(Int(draft.calories.rounded()).formatted()) cal · \(Int(draft.protein.rounded()).formatted()) g protein")
                            .fontWeight(.semibold).monospacedDigit()
                            .accessibilityIdentifier("meal_draft_total")
                        if let message = model.draftMessage {
                            Text(message).foregroundStyle(.secondary)
                                .accessibilityIdentifier("meal_draft_status")
                        }
                        if draft.hasPendingHydration {
                            Button("Retry unfinished food details") { model.retryDraftHydration() }
                                .accessibilityIdentifier("meal_draft_retry_details")
                        }
                        if draft.isSubmitted {
                            Text("This meal is ready to finish saving. Its foods and destination are kept together for a safe retry.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section { Text("Choose foods from search to build a meal.") }
                }
            }.appFormStyle()
            .navigationTitle("Review meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .disabled(model.isSavingDraft)
                        .accessibilityLabel("Keep building")
                        .accessibilityIdentifier("meal_draft_keep_building")
                }
                ToolbarItem(placement: .primaryAction) {
                    if model.mealDraft?.isSubmitted != true {
                        Button("Discard", role: .destructive) { confirmingDiscard = true }
                            .disabled(model.isSavingDraft)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.logMealDraft { success in if success { dismiss() } }
                } label: {
                    Label(model.isSavingDraft ? "Saving meal…" : model.mealDraft?.isSubmitted == true ? "Finish logging" : "Log meal",
                          systemImage: "checkmark")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(model.isSavingDraft || model.mealDraft?.isReadyToSubmit != true || !model.loggingFoodIDs.isEmpty)
                .accessibilityIdentifier("meal_draft_log")
                .padding(AppSpacing.row)
                .background(.bar)
            }
            .interactiveDismissDisabled(model.isSavingDraft)
            .confirmationDialog("Discard this meal draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { if model.discardMealDraft() { dismiss() } }
            } message: { Text("These foods have not been added to your diary.") }
            .fullScreenCover(item: $editingEntry) { entry in
                FoodDetailView(
                    initialFoodItem: entry.preparedFood ?? entry.food,
                    dailyLog: $dailyLogService.currentDailyLog,
                    date: model.mealDraft?.date ?? dailyLogService.activelyViewedDate,
                    source: "image_result_edit",
                    targetMealName: model.mealDraft?.mealName,
                    isPresentedModally: true,
                    onLogUpdated: { editingEntry = nil },
                    onUpdateAccepted: { food in
                        model.updateMealDraft { draft in
                            guard let index = draft.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                            draft.entries[index].food = food
                            draft.entries[index].multiplier = 1
                            draft.entries[index].hydrationPending = false
                        }
                    },
                    reviewActionTitle: "Update portion",
                    reviewNavigationTitle: "Review portion"
                )
            }
        }
    }
}
