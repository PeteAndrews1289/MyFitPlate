import MyFitPlateCore
import SwiftUI

struct AISummaryView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalSettings: GoalSettings
    @State private var didOfferQuestion = false
    private var questionResponse: String? { review.checkpoint.portionQuestion?.receipt?.summary }
    private var question: UsefulMealQuestion? {
        guard let stored = review.checkpoint.portionQuestion, stored.receipt == nil,
              let item = estimatedItems.first(where: { $0.id == stored.question.itemID }),
              (try? PlanFingerprint.make(item)) == stored.question.itemFingerprint else { return nil }
        return stored.question
    }
    @StateObject private var review: MealReviewSaveSession
    @State private var confirmingDiscard = false
    private var estimatedItems: [FoodItem] { review.items }
    private var isSaving: Bool { review.isSaving }
    private var saveError: String? { review.errorMessage }

    private var mealName: String { review.mealName }
    private let source: String
    private let isAIEstimate: Bool
    private let reviewTitle: String
    private let photoReview: MealPhotoReviewContext?
    private let onSelectFoods: (([FoodItem]) -> Bool)?

    init(
        estimatedItems: [FoodItem],
        photoReview: MealPhotoReviewContext? = nil,
        mealName: String = "Dinner",
        date: Date = Date(),
        source: String = "ai_image",
        isAIEstimate: Bool = true,
        reviewTitle: String = "Review Meal", dayContext: DiaryDayContext? = nil,
        trainingFuelTarget: TrainingFuelTarget? = nil, onSelectFoods: (([FoodItem]) -> Bool)? = nil
    ) {
        _review = StateObject(wrappedValue: MealReviewSaveSession(
            items: estimatedItems, userID: DIContainer.shared.authService.currentUserID,
            date: date, mealName: mealName, source: source,
            confirmingSourceType: source == "chain_builder_components" ? .chainBuilder : isAIEstimate ? .aiImage : nil, dayContext: dayContext, trainingFuelTarget: trainingFuelTarget
        ))
        self.source = source
        self.isAIEstimate = isAIEstimate
        self.reviewTitle = reviewTitle
        self.photoReview = photoReview
        self.onSelectFoods = onSelectFoods
    }

    private var destinationDateLabel: String {
        let formatter = DateFormatter()
        let day = review.checkpoint.draft.dayContext
        formatter.calendar = day?.calendar ?? .current; formatter.timeZone = day?.timeZone ?? .current
        formatter.dateStyle = .medium
        return formatter.string(from: day?.displayDate ?? review.date)
    }

    var body: some View {
        NavigationStack {
            List {
                if let target = review.checkpoint.trainingFuelTarget { TrainingFuelTargetContextView(target: target, onDismiss: review.isLocked ? nil : { _ = review.removeFuelContext() }) }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                    Text("\(review.mealName) · \(destinationDateLabel)")
                        .appTextRole(.secondary).accessibilityIdentifier("ai_review_destination")
                    if review.restoredReview { Text("Unfinished review restored").appTextRole(.caption).foregroundStyle(.secondary) }
                    if review.isSubmitted { Text("Your reviewed foods are kept for retry").appTextRole(.caption).foregroundStyle(.secondary) }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if !review.isLocked, let question, estimatedItems.contains(where: { $0.id == question.itemID }) {
                    Section {
                        if let item = estimatedItems.first(where: { $0.id == question.itemID }) {
                            UsefulMealQuestionCard(question: question, item: item) { answer in
                                _ = review.answerPortionQuestion(answer)
                            }
                        }
                    }.listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                if let questionResponse {
                    Text(questionResponse).appTextRole(.secondary).foregroundStyle(.secondary)
                        .accessibilityIdentifier("meal_question_response")
                }

                Section {
                    AIReviewOverview(
                        eyebrow: source == "chain_builder_components" ? "Restaurant Reference" : isAIEstimate ? "Maia Photo Estimate" : "Matched Products",
                        title: source == "chain_builder_components" ? "Review Your Order" : isAIEstimate ? "Review Your Meal" : "Review Scanned Items",
                        subtitle: source == "chain_builder_components" ? "These catalog components will log together as separate diary foods after your review." : isAIEstimate
                            ? "Maia separated the photo into foods. Nothing is logged until you confirm this list."
                            : "Each matched product will log as its own entry after you confirm this list.",
                        reviewTitle: isAIEstimate ? "Review Needed" : "Serving Check",
                        reviewMessage: source == "chain_builder_components" ? "Confirm the portions you ate. Catalog values are reference estimates and local preparation may differ." : isAIEstimate
                            ? "Confirm the foods and portions, especially oils, sauces, and ingredients the camera cannot measure."
                            : "Database matches can still use a different serving than the amount you ate.",
                        items: estimatedItems,
                        photoReview: photoReview
                    )
                    .accessibilityIdentifier("ai_summary_overview")
                }
                .listRowInsets(
                    EdgeInsets(
                        top: AppSpacing.compact,
                        leading: AppSpacing.screenHorizontal,
                        bottom: AppSpacing.row,
                        trailing: AppSpacing.screenHorizontal
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    ForEach(estimatedItems) { item in
                        NavigationLink {
                            foodDetailDestination(for: item)
                        } label: {
                            AIReviewItemRow(
                                item: item,
                                showsEditIndicator: false,
                                photoReview: photoReview?.itemReviews[item.id]
                            )
                        }
                        .accessibilityIdentifier("ai_review_item_\(item.id)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    AppSectionHeader(
                        title: onSelectFoods == nil ? "Items to log" : "Foods to select",
                        subtitle: "Tap an item to edit it, or swipe to remove it."
                    )
                    .textCase(nil)
                    .padding(.bottom, AppSpacing.compact)
                }
                .listRowInsets(
                    EdgeInsets(
                        top: AppSpacing.row,
                        leading: AppSpacing.screenHorizontal,
                        bottom: AppSpacing.row,
                        trailing: AppSpacing.screenHorizontal
                    )
                )
                .listRowBackground(AppPalette.control)
                .disabled(review.isLocked)
            }
            .appFormStyle()
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle(reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(isSaving)
                        .tint(AppPalette.brand)
                }
                ToolbarItem(placement: .primaryAction) {
                    if !review.isSubmitted {
                        Button("Discard", role: .destructive) { confirmingDiscard = true }.disabled(isSaving)
                    }
                }
            }
            .confirmationDialog("Discard this meal review?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard review", role: .destructive) { if review.discard() { dismiss() } }
            } message: { Text("These foods have not been logged.") }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let saveError {
                        Text(saveError).appTextRole(.secondary).foregroundStyle(AppPalette.critical)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppSpacing.screenHorizontal)
                            .accessibilityIdentifier("ai_summary_save_error")
                    }
                    Button(action: logAllItems) {
                        Label(logButtonTitle, systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(estimatedItems.isEmpty || isSaving)
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.row)
                    .padding(.bottom, AppSpacing.compact)
                    .background(AppPalette.canvas.opacity(0.98).ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppPalette.separator)
                            .frame(height: 1)
                    }
                    .accessibilityIdentifier("ai_summary_log_action")
                }
                .background(AppPalette.canvas)
            }
        }
        .task { offerQuestionIfUseful() }
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("ai_summary_review")
        .accessibilityElement(children: .contain)
    }

    private var logButtonTitle: String {
        if isSaving { return "Saving…" }
        if review.isSubmitted { return "Retry saving" }
        if onSelectFoods != nil { return "Select \(review.selectedItems.count) \(review.selectedItems.count == 1 ? "food" : "foods")" }
        let noun = estimatedItems.count == 1 ? "Item" : "Items"
        return "Log \(estimatedItems.count.formatted()) \(noun)"
    }

    private func foodDetailDestination(for item: FoodItem) -> some View {
        FoodDetailView(
            initialFoodItem: item,
            dailyLog: .constant(nil),
            date: review.date,
            source: source == "chain_builder_components" ? "chain_builder_component_edit" : "image_result_edit",
            onLogUpdated: {},
            onUpdate: { updatedItem in
                _ = review.updateItem(updatedItem)
            }
        )
    }

    private func delete(_ item: FoodItem) {
        if review.removeItem(id: item.id) { HapticManager.instance.feedback(.light) }
    }

    private func logAllItems() {
        if let onSelectFoods {
            if review.moveToMeal(onSelectFoods) { dismiss() }
            return
        }
        review.save(using: dailyLogService) { accepted in
            if accepted { dismiss() }
        }
    }

    private func offerQuestionIfUseful() {
        guard !didOfferQuestion, !review.isSubmitted, review.checkpoint.portionQuestion == nil else { return }
        didOfferQuestion = true
        guard let photoReview, isAIEstimate else { return }
        let evidence = photoReview.itemReviews.values.compactMap { review -> MealPortionEvidence? in
            guard let low = review.portionLowGrams, let high = review.portionHighGrams, low.isFinite, high.isFinite, low <= 100_000, high <= 100_000 else { return nil }
            guard let item = estimatedItems.first(where: { $0.id == review.itemID }) else { return nil }
            let anchors = item.sourceMetadata?.portionAnchors ?? []
            return MealPortionEvidence(itemID: review.itemID, lowGrams: low, highGrams: high,
                anchors: anchors, uncertainty: MealQuestionUncertaintyRules.kind(for: item, hasUnresolvedPreparation: !review.hiddenIngredientRisks.isEmpty),
                canUseMeasuredGrams: false)
        }
        let current = dailyLogService.currentDailyLog.flatMap { log in
            Calendar.current.isDate(log.date, inSameDayAs: review.date) ? log : nil
        }
        if let question = UsefulMealQuestionRules.choose(items: estimatedItems, evidence: evidence,
            loggedCalories: current?.totalCalories(), calorieGuide: goalSettings.calories) {
            _ = review.offerPortionQuestion(question)
        }
    }
}

struct AIReviewOverview: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var reviewTitle: String = "Review Needed"
    let reviewMessage: String
    let items: [FoodItem]
    var photoReview: MealPhotoReviewContext?

    private var totalCalories: Double {
        items.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        items.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Double {
        items.reduce(0) { $0 + $1.carbs }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow).appTextRole(.caption).foregroundStyle(.secondary)
                Spacer(minLength: AppSpacing.compact)
                Text("\(items.count) \(items.count == 1 ? "food" : "foods")").appTextRole(.caption).foregroundStyle(.secondary)
            }
            AppMetricStrip(items: [
                AppMetricItem(label: "Calories", value: "\(Int(totalCalories.rounded()).formatted()) cal", accent: AppPalette.energy),
                AppMetricItem(label: "Protein", value: "\(Int(totalProtein.rounded()).formatted()) g", accent: .accentProtein),
                AppMetricItem(label: "Carbs", value: "\(Int(totalCarbs.rounded()).formatted()) g", accent: .accentCarbs)
            ]).appSurface(.interpreted)
            Label(reviewMessage, systemImage: "info.circle")
                .appTextRole(.secondary).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("About this review") {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    Text(subtitle).appTextRole(.secondary).foregroundStyle(.secondary)
                    if let photoReview { MealPhotoEvidenceSummary(review: photoReview) }
                }.padding(.top, AppSpacing.compact)
            }.appTextRole(.secondary).tint(AppPalette.text)
        }.accessibilityLabel(title)
    }
}

struct AIReviewItemRow: View {
    let item: FoodItem
    let showsEditIndicator: Bool
    var photoReview: MealPhotoItemReview?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 5) {
                        itemName
                        AIReviewStatusPill(item: item)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                        itemName
                        AIReviewStatusPill(item: item)
                    }
                }

                Text(item.servingSize.isEmpty ? "Serving needs review" : item.servingSize)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Int(item.calories.rounded()).formatted()) calories")
                        Text(
                            "Protein \(Int(item.protein.rounded()).formatted()) g, carbs \(Int(item.carbs.rounded()).formatted()) g, fat \(Int(item.fats.rounded()).formatted()) g"
                        )
                    }
                    .appTextRole(.secondary)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(
                        "\(Int(item.calories.rounded()).formatted()) cal  |  P \(Int(item.protein.rounded()).formatted()) g  |  C \(Int(item.carbs.rounded()).formatted()) g  |  F \(Int(item.fats.rounded()).formatted()) g"
                    )
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                AIItemTrustNotes(item: item)

                if let photoReview {
                    MealPhotoItemEvidence(review: photoReview)
                }
            }

            if showsEditIndicator {
                Spacer(minLength: AppSpacing.compact)
                Image(systemName: "pencil")
                    .foregroundStyle(AppPalette.brandText)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var itemName: some View {
        Text(item.name)
            .appTextRole(.control)
            .foregroundStyle(AppPalette.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MealPhotoEvidenceSummary: View {
    let review: MealPhotoReviewContext

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Label("What the photo can tell us", systemImage: "camera.metering.center.weighted")
                .appTextRole(.control).foregroundStyle(AppPalette.text)

            Text(evidenceSummary)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !review.analysisNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(review.analysisNotes)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .appSurface(.quiet)
        .accessibilityElement(children: .combine)
    }

    private var evidenceSummary: String {
        let grounded = review.groundedItemCount
        let confirmation = review.needsConfirmationCount
        let referenceText = grounded == 0
            ? "No close food-composition match was found."
            : "\(grounded) \(grounded == 1 ? "item uses" : "items use") a food-composition reference."
        let confirmationText = confirmation == 0
            ? "All items still need a quick serving check."
            : "\(confirmation) \(confirmation == 1 ? "item needs" : "items need") a closer look."
        return "\(referenceText) \(confirmationText) Identity and portion remain photo estimates."
    }
}

private struct MealPhotoItemEvidence: View {
    let review: MealPhotoItemReview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                review.requiresConfirmation ? "Portion needs a closer look" : "Portion estimated from photo",
                systemImage: review.requiresConfirmation ? "exclamationmark.circle" : "camera.metering.center.weighted"
            )
            .foregroundStyle(review.requiresConfirmation ? AppPalette.caution : .secondary)

            if let rangeText {
                Label(rangeText, systemImage: "scalemass")
                    .foregroundStyle(.secondary)
            }

            if let source = review.referenceSourceName {
                Label("Composition scaled from \(source)", systemImage: "books.vertical")
                    .foregroundStyle(AppPalette.brandText)
            } else {
                Label("Nutrition is still a model estimate", systemImage: "sparkles")
                    .foregroundStyle(AppPalette.caution)
            }

            if !review.hiddenIngredientRisks.isEmpty {
                Label(
                    "Check for \(review.hiddenIngredientRisks.prefix(3).joined(separator: ", "))",
                    systemImage: "eye.slash"
                )
                .foregroundStyle(AppPalette.caution)
            }

        }
        .appTextRole(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var rangeText: String? {
        guard let low = review.portionLowGrams, let high = review.portionHighGrams, low.isFinite, high.isFinite, low <= 100_000, high <= 100_000 else { return nil }
        let orderedLow = Int(min(low, high).rounded())
        let orderedHigh = Int(max(low, high).rounded())
        guard orderedLow > 0, orderedHigh > 0 else { return nil }
        return orderedLow == orderedHigh
            ? "Photo-estimated portion: \(orderedLow) g"
            : "Photo-estimated range: \(orderedLow)-\(orderedHigh) g"
    }
}

struct AIReviewStatusPill: View {
    let item: FoodItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusText: String {
        switch item.sourceMetadata?.reviewStatus {
        case .userEdited:
            return "Edited"
        case .userConfirmed:
            return "Reviewed"
        default:
            return "Needs Review"
        }
    }

    private var tint: Color {
        switch item.sourceMetadata?.reviewStatus {
        case .userEdited, .userConfirmed:
            return .accentPositive
        default:
            return AppPalette.caution
        }
    }

    var body: some View {
        Text(statusText)
            .appTextRole(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : AppSpacing.compact)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 0 : 3)
            .background {
                if !dynamicTypeSize.isAccessibilitySize {
                    Capsule().fill(tint.opacity(0.10))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AIItemTrustNotes: View {
    let item: FoodItem

    var body: some View {
        if item.hasMeaningfulCalorieMacroMismatch {
            Label("Calories and macros need review", systemImage: "exclamationmark.triangle.fill")
                .appTextRole(.caption)
                .foregroundStyle(AppPalette.caution)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AIEstimateReviewBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: "info.circle")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(AppPalette.caution)
                .frame(width: 28, height: 28)
                .background(
                    AppPalette.caution.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Text(message)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .combine)
    }
}
