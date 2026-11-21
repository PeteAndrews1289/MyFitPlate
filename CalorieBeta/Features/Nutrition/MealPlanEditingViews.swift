import MyFitPlateCore
import SwiftUI
import UIKit

/// Keep actionable planner errors, including errors bridged through Firestore's NSError API.
/// Transport errors should explain recovery without exposing backend or file-storage wording.
enum MealPlannerErrorText {
    static func message(for error: Error) -> String {
        if (error as NSError).domain == (MealPlanEditError.changed as NSError).domain
            || (error as NSError).domain == (MealCookingError.changed as NSError).domain
            || (error as NSError).domain == (MealPlanChangeReceiptError.changed as NSError).domain
            || (error as NSError).domain == (MealPlanConstraintError.invalid as NSError).domain {
            return error.localizedDescription
        }
        return "Couldn't update your plan. Your choices are still here. Check your connection and try again."
    }
}

struct PlannedMealEditSheet: View {
    let date: Date
    var title = "Edit meal"
    let save: (PlannedMeal) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var meal: PlannedMeal
    @State private var isSaving = false
    @State private var error: String?
    @State private var householdBatch: Bool
    @State private var cookingPortions: Double
    @State private var measuredUnit = "original"
    @State private var measuredAmount = "1"
    @State private var reviewedPattern: PlanningDiet = .unrestricted
    @State private var reviewedExclusions = ""
    @State private var reviewedEquipment = ""
    @State private var reviewedMinutes = ""
    @State private var reviewedCost = ""
    @State private var planningConfirmed = false
    private let originalMeal: PlannedMeal

    init(meal: PlannedMeal, date: Date, title: String = "Edit meal", save: @escaping (PlannedMeal) async throws -> Void) {
        self.date = date; self.title = title; self.save = save
        originalMeal = meal
        var editable = meal; editable.mealType = MealPlanEditingRules.canonicalSlot(meal.mealType)
        _meal = State(initialValue: editable)
        _householdBatch = State(initialValue: meal.cookingBatch != nil)
        _cookingPortions = State(initialValue: meal.cookingBatch?.totalPortions ?? max(2, meal.portions))
        _measuredAmount = State(initialValue: meal.portions.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))))
        if let evidence = meal.planningEvidence, evidence.isCurrent(for: meal) {
            _reviewedPattern = State(initialValue: evidence.profile.diet)
            _reviewedExclusions = State(initialValue: evidence.profile.reviewedExclusions.joined(separator: ", "))
            _reviewedEquipment = State(initialValue: evidence.profile.equipment.joined(separator: ", "))
            _reviewedMinutes = State(initialValue: evidence.profile.prepMinutes.map(String.init) ?? "")
            _reviewedCost = State(initialValue: evidence.profile.costPerServing.map { String($0) } ?? "")
            _planningConfirmed = State(initialValue: evidence.userReviewed)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        mealIdentity
                        destination
                        Divider()
                        portionControls
                        if let food = meal.plannedFood {
                            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                Text("\(Int(food.calories.rounded()).formatted()) cal · \(Int(food.protein.rounded()).formatted()) g protein")
                                    .appTextRole(.control).monospacedDigit()
                                    .contentTransition(.numericText())
                                    .accessibilityIdentifier("planner_portion_nutrition")
                                Text("\(Int(food.carbs.rounded()).formatted()) g carbs · \(Int(food.fats.rounded()).formatted()) g fat")
                                    .appTextRole(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.compact)
                }
                if !meal.plannedIngredients.isEmpty {
                    cookingQuantitySection
                }
                if !meal.plannedIngredients.isEmpty || meal.instructions?.isEmpty == false {
                    recipeDetails
                }
                planningReview
            }.appFormStyle()
            .accessibilityIdentifier("planner_edit_form")
            .disabled(isSaving)
            .onChange(of: reviewedPattern) { _, _ in planningConfirmed = false }
            .onChange(of: reviewedExclusions) { _, _ in planningConfirmed = false }
            .onChange(of: reviewedEquipment) { _, _ in planningConfirmed = false }
            .onChange(of: reviewedMinutes) { _, _ in planningConfirmed = false }
            .onChange(of: reviewedCost) { _, _ in planningConfirmed = false }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.accessibilityIdentifier("planner_portion_keyboard_done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.compact) {
                Text("Updates your plan. Logged food stays unchanged.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                if let error { Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("planner_edit_error") }
                Button(isSaving ? "Saving…" : "Save meal") {
                    isSaving = true; error = nil
                    Task { @MainActor in
                        do {
                            if let base = meal.foodItem {
                                _ = try PlannedMealMeasurementRules.multiplier(amount: Double(measuredAmount.replacingOccurrences(of: ",", with: ".")) ?? .nan, unit: measuredUnit, base: base)
                            }
                            if planningConfirmed {
                                let minutes = reviewedMinutes.trimmingCharacters(in: .whitespaces), cost = reviewedCost.trimmingCharacters(in: .whitespaces)
                                guard minutes.isEmpty || Int(minutes).map({ $0 > 0 && $0 <= 480 }) == true,
                                      cost.isEmpty || Double(cost).map({ $0.isFinite && $0 >= 0 }) == true else { throw MealPlanEditError.invalid }
                                let profile = RecipePlanningProfile(prepMinutes: Int(minutes), equipment: reviewedEquipment.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                    diet: reviewedPattern, reviewedExclusions: reviewedExclusions.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                    costPerServing: Double(cost), reviewedAt: Date())
                                meal.planningEvidence = try PlannedMealEvidence(profile: profile, meal: meal)
                            } else { meal.planningEvidence = nil }
                            let updated: PlannedMeal
                            if originalMeal.cookingBatch?.allocations.count ?? 0 > 1 {
                                var linked = meal; linked.cookingBatch?.totalPortions = cookingPortions; updated = linked
                            } else {
                                updated = try MealPlanCookingRules.configuring(meal, date: date, cookingPortions: householdBatch ? cookingPortions : nil)
                            }
                            try await save(updated); dismiss()
                        } catch { self.error = MealPlannerErrorText.message(for: error) }
                        isSaving = false
                    }
                }
                .buttonStyle(AppActionButtonStyle(.primary)).disabled(isSaving)
                .accessibilityIdentifier("planner_save_meal")
                }.padding().background(AppPalette.canvas)
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var mealIdentity: some View {
        HStack(alignment: .center, spacing: AppSpacing.row) {
            Text(FoodEmojiMapper.getEmoji(for: meal.foodItem?.name ?? "Planned meal"))
                .font(.system(size: 26)).frame(width: 44, height: 44)
                .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
                .accessibilityHidden(true)
            Text(meal.foodItem?.name ?? "Planned meal")
                .appTextRole(.sectionTitle).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destination: some View {
        HStack(alignment: .center, spacing: AppSpacing.row) {
            Text(date.formatted(date: .complete, time: .omitted))
                .appTextRole(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planner_review_date")
            Spacer(minLength: 0)
            Picker("Meal", selection: $meal.mealType) {
                ForEach(MealPlanEditingRules.mealTypes, id: \.self) { Text($0).tag($0) }
                if !MealPlanEditingRules.mealTypes.contains(meal.mealType) { Text(meal.mealType).tag(meal.mealType) }
            }
            .pickerStyle(.menu).labelsHidden().tint(AppPalette.text)
            .accessibilityIdentifier("planner_review_slot")
        }
    }

    private var portionControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text("Your planned portion").appTextRole(.secondary).foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    measuredPortionInput
                    portionStepper
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.compact) {
                        measuredPortionInput
                        portionStepper
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        measuredPortionInput
                        HStack { Spacer(minLength: 0); portionStepper }
                    }
                }
            }
            if let serving = meal.foodItem?.servingSize, !serving.isEmpty {
                Text("1 portion = \(serving)")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var measuredPortionInput: some View {
        if let base = meal.foodItem {
            HStack(spacing: AppSpacing.compact) {
                TextField("Amount", text: $measuredAmount)
                    .keyboardType(.decimalPad).appTextRole(.control).monospacedDigit()
                    .textFieldStyle(.plain).padding(.horizontal, AppSpacing.compact)
                    .frame(width: 96, height: 44)
                    .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityIdentifier("planner_measured_amount")
                    .onChange(of: measuredAmount) { _, _ in applyMeasuredAmount(base) }
                    .onChange(of: measuredUnit) { _, unit in
                        let amount = unit == "original" ? meal.portions : unit == "g" ? base.servingWeight * meal.portions
                            : InventoryQuantityRules.convert(base.servingWeight * meal.portions, from: "g", to: unit) ?? (base.quantityValue ?? 1) * meal.portions
                        measuredAmount = amount.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...4)))
                    }
                Picker("Measure", selection: $measuredUnit) {
                    Text("Portions").tag("original")
                    if PlannedMealMeasurementRules.hasKnownMass(base) { Text("Grams").tag("g"); Text("Ounces (mass)").tag("oz"); Text("Pounds").tag("lb") }
                    if let unit = base.servingUnit, base.quantityValue.map({ $0 > 0 }) == true, !["g", "oz", "lb"].contains(unit) { Text(unit).tag(unit) }
                }
                .pickerStyle(.menu).labelsHidden().appTextRole(.secondary).tint(AppPalette.text)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("planner_measured_unit")
            }
        } else {
            Text("\(meal.portions.formatted(.number.precision(.fractionLength(0...2)))) × original portion")
                .appTextRole(.control)
        }
    }

    private var portionStepper: some View {
        Stepper(value: Binding(get: { meal.portions }, set: { value in
            meal.portionMultiplier = value
            if let base = meal.foodItem {
                let amount = measuredUnit == "original" ? value : InventoryQuantityRules.convert(base.servingWeight * value, from: "g", to: measuredUnit) ?? (base.quantityValue ?? 1) * value
                measuredAmount = amount.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
            }
        }), in: 0.25...8, step: 0.25) {
            Text("\(meal.portions.formatted(.number.precision(.fractionLength(0...2)))) × original portion")
        }
        .labelsHidden().fixedSize()
        .accessibilityHint("Adjusts by a quarter of the original portion")
        .accessibilityIdentifier("planner_portions")
    }

    private var recipeDetails: some View {
        Section {
            DisclosureGroup("Ingredients & method") {
                if !meal.plannedIngredients.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Ingredients for your portion").appTextRole(.control)
                        ForEach(Array(meal.plannedIngredients.enumerated()), id: \.offset) { _, item in
                            Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(item.unit == "item" ? "" : item.unit + " ")\(item.name)")
                                .appTextRole(.secondary)
                        }
                    }.padding(.vertical, AppSpacing.compact)
                }
                if let instructions = meal.instructions, !instructions.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        Text("Method").appTextRole(.control)
                        Text(instructions).appTextRole(.secondary)
                        Text("Cooking times do not scale with your portion.").appTextRole(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, AppSpacing.compact)
                }
            }
            .tint(AppPalette.text)
            .accessibilityIdentifier("planner_recipe_details")
        }
    }

    private var planningReview: some View {
        Section {
            DisclosureGroup("Personal planning review") {
                Picker("Ingredient pattern", selection: $reviewedPattern) { ForEach(PlanningDiet.allCases) { Text($0.title).tag($0) } }
                TextField("Ingredients reviewed as excluded · comma separated", text: $reviewedExclusions)
                TextField("Required equipment · or no cooking", text: $reviewedEquipment)
                TextField("Prep minutes · optional", text: $reviewedMinutes).keyboardType(.numberPad)
                TextField("Cost per original portion in USD · optional", text: $reviewedCost).keyboardType(.decimalPad)
                Toggle("I reviewed these ingredients and planning estimates", isOn: $planningConfirmed)
                Text("This is your personal ingredient review, not allergen or cross-contact certification. Unknown prices and prep times remain unknown.").appTextRole(.caption)
            }.tint(AppPalette.text)
        }
    }

    private var cookingQuantitySection: some View {
        Section("Cooking for your household") {
            Toggle("Plan a shared cooking batch", isOn: $householdBatch)
                .accessibilityIdentifier("planner_household_batch")
                .disabled(meal.cookingBatch?.allocations.count ?? 0 > 1)
            if householdBatch {
                Stepper(value: $cookingPortions, in: 0.25...100, step: 0.25) {
                    Text("Cook \(cookingPortions.formatted(.number.precision(.fractionLength(0...2)))) × original portion")
                }
                .accessibilityIdentifier("planner_cooking_portions")
                Text("Your planned calories stay the same. Groceries and cooking use this full amount. Unallocated portions may be for other people or future leftovers.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                if let batch = try? MealPlanCookingRules.configuring(meal, date: date, cookingPortions: cookingPortions).cookingBatch {
                    Text("\(batch.unallocatedPortions.formatted(.number.precision(.fractionLength(0...2)))) original portions unallocated")
                        .accessibilityIdentifier("planner_batch_remaining")
                    DisclosureGroup("Ingredients for this batch") {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            ForEach(Array(batch.ingredientsPerPortion.enumerated()), id: \.offset) { _, item in
                                Text("\((item.quantity * cookingPortions).formatted(.number.precision(.fractionLength(0...2)))) \(item.unit == "item" ? "" : item.unit + " ")\(item.name)")
                            }
                        }.accessibilityIdentifier("planner_cooking_ingredients")
                    }.tint(AppPalette.text)
                } else if let summary = MealPlanCookingRules.summary(for: meal) {
                    Text(summary).accessibilityIdentifier("planner_batch_remaining")
                }
                if meal.cookingBatch?.allocations.count ?? 0 > 1 {
                    Text("Saving reviews all linked dates together. Changing your portion keeps the full batch; changing its cooking quantity updates every allocation's shared snapshot.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if cookingPortions < meal.portions {
                    Text("Cook at least as much as your personal portion.").foregroundStyle(AppPalette.caution)
                }
            } else {
                Text("Groceries follow just your personal portion. Enable a batch when cooking extra.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
        }
    }

    private func applyMeasuredAmount(_ base: FoodItem) {
        do {
            meal.portionMultiplier = try PlannedMealMeasurementRules.multiplier(amount: Double(measuredAmount.replacingOccurrences(of: ",", with: ".")) ?? .nan, unit: measuredUnit, base: base)
            error = nil
        } catch { self.error = "Enter a compatible amount between one quarter and eight original portions. Counts are never assumed to be grams." }
    }
}

struct MealPlanTransferRequest: Identifiable {
    let id = UUID()
    let source: MealPlanDay
    let meals: [PlannedMeal]
    let moving: Bool
}

struct MealPlanTransferSheet: View {
    let request: MealPlanTransferRequest
    let didSave: () -> Void
    @EnvironmentObject private var planner: MealPlannerService
    @Environment(\.dismiss) private var dismiss
    @State private var dates: Set<Date> = []
    @State private var pickedDate = Calendar.current.startOfDay(for: Date())
    @State private var prepared: MealPlanChange?
    @State private var isWorking = false
    @State private var error: String?
    @State private var owner: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(request.meals) { meal in
                        Label(meal.foodItem?.name ?? meal.mealType, systemImage: "fork.knife")
                    }
                    Text(request.moving ? "Moves the planned meal. Food already logged stays on its original date."
                         : "Adds independent copies alongside any existing meals. Food already logged stays unchanged.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if let prepared {
                    Section("Review destinations") {
                        ForEach(prepared.after.filter { MealPlanEditingRules.dayID($0.date) != MealPlanEditingRules.dayID(request.source.date) }) { day in
                            let previous = prepared.before.first { $0.id == day.id }?.meals.count ?? 0
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                Text("\(request.meals.count) added · \(previous) existing meals kept")
                                    .appTextRole(.secondary).foregroundStyle(.secondary)
                            }
                        }
                        Button("Change dates") { self.prepared = nil; error = nil }
                    }
                } else {
                    Section("Choose dates") {
                        DatePicker("Destination", selection: $pickedDate, displayedComponents: .date)
                            .accessibilityIdentifier("planner_destination")
                        Button(request.moving ? "Use this date" : "Add this date") {
                            let date = Calendar.current.startOfDay(for: pickedDate)
                            if request.moving { dates = [date] } else { dates.insert(date) }
                        }.disabled(Calendar.current.isDate(pickedDate, inSameDayAs: request.source.date) || dates.count >= 7)
                        ForEach(dates.sorted(), id: \.self) { date in
                            HStack {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Button { dates.remove(date) } label: { Image(systemName: "minus.circle") }
                                    .accessibilityLabel("Remove \(date.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                    }
                }
            }.appFormStyle()
            .disabled(isWorking)
            .navigationTitle(request.moving ? "Move meal" : "Copy meals").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.compact) {
                if let error { Text(error).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("planner_transfer_error") }
                Button(isWorking ? "Saving…" : prepared == nil ? "Review changes" : request.moving ? "Move meal" : "Copy meals") { perform() }
                    .buttonStyle(AppActionButtonStyle(.primary)).disabled(isWorking || dates.isEmpty)
                    .accessibilityIdentifier("planner_transfer_confirm")
                }.padding().background(AppPalette.canvas)
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onAppear {
            owner = DIContainer.shared.authService.currentUserID
            if dates.isEmpty, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: request.source.date) {
                pickedDate = tomorrow; dates = [Calendar.current.startOfDay(for: tomorrow)]
            }
        }
    }

    private func perform() {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { error = MealPlanEditError.accountChanged.localizedDescription; return }
        isWorking = true; error = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                if let prepared {
                    try await planner.applyPlanChange(prepared, for: owner)
                    didSave(); dismiss()
                } else {
                    planner.invalidateCache(for: owner)
                    var destinations: [MealPlanDay] = []
                    for date in dates.sorted() {
                        let plan = try await planner.fetchBasePlanResult(for: date, userID: owner).get()
                        destinations.append(plan ?? MealPlanEditingRules.emptyDay(date))
                    }
                    guard DIContainer.shared.authService.currentUserID == owner else { throw MealPlanEditError.accountChanged }
                    prepared = try MealPlanEditingRules.transferring(request.meals, from: request.source, to: destinations, moving: request.moving)
                }
            } catch { self.error = MealPlannerErrorText.message(for: error) }
        }
    }
}

struct MealPlanWeekAgenda: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let dates: [Date]
    let plans: [String: MealPlanDay]
    let training: [String: String]
    let select: (Date) -> Void

    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ForEach(dates, id: \.self) { date in
                let meals = plans[dateKey(for: date)]?.meals ?? []
                Button { select(date) } label: {
                    VStack(alignment: .leading, spacing: AppSpacing.row) {
                        HStack {
                            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).appTextRole(.control)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        if let workout = training[dateKey(for: date)] {
                            Label(workout, systemImage: "dumbbell").appTextRole(.caption).foregroundStyle(AppPalette.effort)
                        }
                        if meals.isEmpty {
                            Text("Plan a meal").appTextRole(.secondary).foregroundStyle(.secondary)
                        } else {
                            ForEach(meals) { meal in
                                (dynamicTypeSize.isAccessibilitySize
                                 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                                 : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                                    Text(meal.mealType).appTextRole(.caption).foregroundStyle(.secondary)
                                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 65, alignment: .leading)
                                    Text(meal.foodItem?.name ?? "Planned meal").appTextRole(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).appSurface(.quiet)
                }
                .buttonStyle(.plain).accessibilityIdentifier("planner_agenda_\(dateKey(for: date))")
            }
        }
    }
}

/// Explicit leftover allocation; every existing member is re-read and committed together.
struct MealPlanLeftoverSheet: View {
    let source: MealPlanDay
    let meal: PlannedMeal
    let didSave: () -> Void
    @EnvironmentObject private var planner: MealPlannerService
    @Environment(\.dismiss) private var dismiss
    @State private var destinationDate: Date
    @State private var mealType = "Lunch"
    @State private var portions: Double = 1
    @StateObject private var review: MealPlanLeftoverSaveSession
    @State private var isWorking = false
    @State private var error: String?
    @State private var owner: String?

    init(source: MealPlanDay, meal: PlannedMeal, didSave: @escaping () -> Void) {
        let session = MealPlanLeftoverSaveSession(userID: DIContainer.shared.authService.currentUserID)
        let checkpoint = session.checkpoint
        let frozenSource = checkpoint?.change.before.first { day in day.meals.contains { $0.id == checkpoint?.sourceMealID } }
        self.source = frozenSource ?? source
        self.meal = frozenSource?.meals.first { $0.id == checkpoint?.sourceMealID } ?? meal
        self.didSave = didSave
        _review = StateObject(wrappedValue: session)
        _destinationDate = State(initialValue: checkpoint?.destinationDate ?? Calendar.current.date(byAdding: .day, value: 1, to: source.date) ?? source.date)
        _mealType = State(initialValue: checkpoint?.mealType ?? "Lunch")
        _portions = State(initialValue: checkpoint?.portions ?? min(1, max(0.25, meal.cookingBatch?.unallocatedPortions ?? 1)))
    }

    init(resuming session: MealPlanLeftoverSaveSession, didSave: @escaping () -> Void) {
        let checkpoint = session.checkpoint
        let source = checkpoint?.change.before.first { day in day.meals.contains { $0.id == checkpoint?.sourceMealID } }
            ?? MealPlanEditingRules.emptyDay(checkpoint?.destinationDate ?? Date())
        self.source = source
        self.meal = source.meals.first { $0.id == checkpoint?.sourceMealID } ?? PlannedMeal(mealType: checkpoint?.mealType ?? "Lunch")
        self.didSave = didSave
        _review = StateObject(wrappedValue: session)
        _destinationDate = State(initialValue: checkpoint?.destinationDate ?? Date())
        _mealType = State(initialValue: checkpoint?.mealType ?? "Lunch")
        _portions = State(initialValue: checkpoint?.portions ?? 1)
    }

    private var prepared: MealPlanChange? { review.checkpoint?.change }
    private var actionTitle: String {
        if isWorking || review.isSaving { return "Saving…" }
        if review.checkpoint?.accepted == true || review.checkpoint?.cancelled == true { return "Done" }
        if review.checkpoint?.submitted == true { return "Retry reviewed leftovers" }
        return prepared == nil ? "Review leftovers" : "Plan leftovers"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if review.restored {
                        Text(review.checkpoint?.accepted == true ? "These leftovers were already saved." : "Restored your exact leftover review. Later plan edits do not change this submitted meal.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                            .accessibilityIdentifier("planner_leftover_restored")
                    }
                    Text(meal.foodItem?.name ?? "Planned meal").appTextRole(.sectionTitle)
                    if let batch = meal.cookingBatch {
                        Text("Batch planned for \(batch.cookingDate.formatted(date: .abbreviated, time: .omitted)): \(batch.totalPortions.formatted(.number.precision(.fractionLength(0...2)))) original portions.")
                        Text("\(batch.unallocatedPortions.formatted(.number.precision(.fractionLength(0...2)))) original portions unallocated")
                            .accessibilityIdentifier("planner_leftover_available")
                    }
                    Text("This plans food from the same batch. It does not buy ingredients again, mark cooking complete, or log anything as eaten.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                if let prepared {
                    Section("Review leftovers") {
                        if review.checkpoint?.cancelled == true {
                            Text("This reviewed save was cancelled. No new leftovers will be added by this operation.")
                                .accessibilityIdentifier("planner_leftover_cancelled")
                        }
                        Text(destinationDate.formatted(date: .complete, time: .omitted))
                        Text("\(mealType) · \(portions.formatted(.number.precision(.fractionLength(0...2)))) × original portion")
                        if let food = meal.foodItem.flatMap({ FoodRepeatRules.adjusting($0, by: portions) }) {
                            Text("\(Int(food.calories.rounded())) cal · \(Int(food.protein.rounded())) g protein")
                                .accessibilityIdentifier("planner_leftover_nutrition")
                        }
                        Text("Existing meals stay in place. Ingredients are counted once for the whole cooking batch.")
                        Text("\(prepared.before.count) day\(prepared.before.count == 1 ? "" : "s") checked together")
                        if review.checkpoint?.submitted == false {
                            Button("Change leftovers") { _ = review.changeUnsubmittedReview(); error = nil }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("planner_leftover_review")
                    if review.checkpoint?.submitted == true,
                       review.checkpoint?.accepted == false, review.checkpoint?.cancelled == false {
                        Section("Save recovery") {
                            Button {
                                Task { @MainActor in
                                    await review.checkStatus(using: DIContainer.shared.nutritionRepository)
                                }
                            } label: {
                                Text("Check saved status").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }.accessibilityIdentifier("planner_leftover_check_status")
                            Button {
                                Task { @MainActor in
                                    await review.checkStatus(using: DIContainer.shared.nutritionRepository, cancelPending: true)
                                }
                            } label: {
                                Text("Cancel pending save").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }.accessibilityIdentifier("planner_leftover_cancel_pending")
                            Text("Cancellation checks the server first. An already saved allocation stays saved; later edits remain in place.")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("planner_leftover_recovery")
                    }
                } else {
                    Section("Plan your portion") {
                        DatePicker("Leftover date", selection: $destinationDate, displayedComponents: .date)
                            .accessibilityIdentifier("planner_leftover_destination")
                        Picker("Meal", selection: $mealType) {
                            ForEach(MealPlanEditingRules.mealTypes, id: \.self) { Text($0).tag($0) }
                        }.accessibilityIdentifier("planner_leftover_slot")
                        Stepper(value: $portions, in: 0.25...8, step: 0.25) {
                            Text("\(portions.formatted(.number.precision(.fractionLength(0...2)))) × original portion")
                        }.accessibilityIdentifier("planner_leftover_portions")
                        Text("Choose a date within seven days of the planned cooking date.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }
            }.appFormStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("planner_leftover_form")
            .disabled(isWorking || review.isSaving)
            .navigationTitle("Plan leftovers").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: AppSpacing.compact) {
                    if let message = error ?? review.errorMessage { Text(message).appTextRole(.secondary).foregroundStyle(AppPalette.caution).accessibilityIdentifier("planner_leftover_error") }
                    Button(actionTitle) { perform() }
                        .buttonStyle(AppActionButtonStyle(.primary)).disabled(isWorking || review.isSaving)
                        .accessibilityIdentifier("planner_leftover_confirm")
                }
                .padding().background(AppPalette.canvas)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("planner_leftover_footer")
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onAppear { if owner == nil { owner = DIContainer.shared.authService.currentUserID } }
    }

    private func perform() {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else {
            error = MealPlanEditError.accountChanged.localizedDescription; return
        }
        isWorking = true; error = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                if prepared != nil {
                    if review.checkpoint?.accepted == true || review.checkpoint?.cancelled == true {
                        _ = review.finishAcceptedReview()
                        didSave(); dismiss(); return
                    }
                    if await review.save(using: planner) {
                        _ = review.finishAcceptedReview()
                        didSave(); dismiss()
                    }
                } else {
                    planner.invalidateCache(for: owner)
                    let dates = Set(MealPlanCookingRules.relatedDates(for: meal) + [Calendar.current.startOfDay(for: source.date), Calendar.current.startOfDay(for: destinationDate)])
                    var days: [MealPlanDay] = []
                    for date in dates.sorted() {
                        let day = try await planner.fetchBasePlanResult(for: date, userID: owner).get()
                        days.append(day ?? MealPlanEditingRules.emptyDay(date))
                    }
                    guard DIContainer.shared.authService.currentUserID == owner,
                          let currentSource = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: source.date) }),
                          let destination = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: destinationDate) }) else {
                        throw MealPlanEditError.accountChanged
                    }
                    let change = try MealPlanCookingRules.planningLeftover(from: meal, source: currentSource,
                        relatedDays: days, destination: destination, mealType: mealType, portions: portions)
                    _ = review.prepare(MealPlanLeftoverCheckpoint(change: change, sourceMealID: meal.id,
                        destinationDate: destinationDate, mealType: mealType, portions: portions))
                }
            } catch { self.error = MealPlannerErrorText.message(for: error) }
        }
    }
}
