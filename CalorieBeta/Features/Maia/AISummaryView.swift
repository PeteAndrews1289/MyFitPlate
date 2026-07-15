import SwiftUI

struct AISummaryView: View {
    @EnvironmentObject private var dailyLogService: DailyLogService
    @Environment(\.dismiss) private var dismiss

    @State private var estimatedItems: [FoodItem]

    private let mealName: String
    private let source: String
    private let isAIEstimate: Bool
    private let reviewTitle: String
    private let photoReview: MealPhotoReviewContext?

    init(
        estimatedItems: [FoodItem],
        photoReview: MealPhotoReviewContext? = nil,
        mealName: String = "AI Logged Meal",
        source: String = "ai_image",
        isAIEstimate: Bool = true,
        reviewTitle: String = "Review Meal"
    ) {
        _estimatedItems = State(initialValue: estimatedItems)
        self.mealName = mealName
        self.source = source
        self.isAIEstimate = isAIEstimate
        self.reviewTitle = reviewTitle
        self.photoReview = photoReview
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AIReviewOverview(
                        eyebrow: isAIEstimate ? "Maia Photo Estimate" : "Matched Products",
                        title: isAIEstimate ? "Review Your Meal" : "Review Scanned Items",
                        subtitle: isAIEstimate
                            ? "Maia separated the photo into foods. Nothing is logged until you confirm this list."
                            : "Each matched product will log as its own entry after you confirm this list.",
                        reviewTitle: isAIEstimate ? "Review Needed" : "Serving Check",
                        reviewMessage: isAIEstimate
                            ? "Confirm the foods and portions, especially oils, sauces, and ingredients the camera cannot measure."
                            : "Database matches can still use a different serving than the amount you ate.",
                        items: estimatedItems,
                        photoReview: photoReview
                    )
                    .accessibilityIdentifier("ai_summary_overview")
                }
                .listRowInsets(
                    EdgeInsets(
                        top: AppSpacing.group,
                        leading: AppSpacing.screenHorizontal,
                        bottom: AppSpacing.section,
                        trailing: AppSpacing.screenHorizontal
                    )
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    ForEach($estimatedItems) { $item in
                        NavigationLink {
                            foodDetailDestination(for: $item)
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
                        title: "Items to Log",
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
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle(reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(AppPalette.brand)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: logAllItems) {
                    Label(logButtonTitle, systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .disabled(estimatedItems.isEmpty)
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
        }
        .accessibilityIdentifier("ai_summary_review")
    }

    private var logButtonTitle: String {
        let noun = estimatedItems.count == 1 ? "Item" : "Items"
        return "Log \(estimatedItems.count.formatted()) \(noun)"
    }

    private func foodDetailDestination(for item: Binding<FoodItem>) -> some View {
        FoodDetailView(
            initialFoodItem: item.wrappedValue,
            dailyLog: .constant(nil),
            date: dailyLogService.activelyViewedDate,
            source: "image_result_edit",
            onLogUpdated: {},
            onUpdate: { updatedItem in
                item.wrappedValue = updatedItem
            }
        )
    }

    private func delete(_ item: FoodItem) {
        estimatedItems.removeAll { $0.id == item.id }
        HapticManager.instance.feedback(.light)
    }

    private func logAllItems() {
        guard let userID = DIContainer.shared.authService.currentUserID, !estimatedItems.isEmpty else { return }

        let fallbackSourceType: FoodSourceType = isAIEstimate ? .aiImage : .unknown
        let reviewedItems = estimatedItems.map { item in
            item.markedUserConfirmed(sourceType: item.sourceMetadata?.sourceType ?? fallbackSourceType)
        }
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: mealName,
            foodItems: reviewedItems,
            source: source
        )

        dismiss()
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
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            AppScreenHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)

            AIEstimateReviewBanner(title: reviewTitle, message: reviewMessage)

            if let photoReview {
                MealPhotoEvidenceSummary(review: photoReview)
            }

            VStack(alignment: .leading, spacing: AppSpacing.row) {
                AppSectionHeader(
                    title: "Estimated Nutrition",
                    subtitle: "Totals update as you edit or remove items."
                )

                AppMetricStrip(items: [
                    AppMetricItem(
                        label: "Items",
                        value: items.count.formatted(),
                        accent: AppPalette.brand
                    ),
                    AppMetricItem(
                        label: "Calories",
                        value: "\(Int(totalCalories.rounded()).formatted()) cal",
                        accent: AppPalette.energy
                    ),
                    AppMetricItem(
                        label: "Protein",
                        value: "\(Int(totalProtein.rounded()).formatted()) g",
                        accent: .accentProtein
                    ),
                    AppMetricItem(
                        label: "Carbs",
                        value: "\(Int(totalCarbs.rounded()).formatted()) g",
                        accent: .accentCarbs
                    )
                ])
            }
            .appSurface(.emphasized)
        }
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

    private var confidenceText: String {
        switch review.overallConfidence {
        case 0.82...: return "High photo confidence"
        case 0.62...: return "Moderate photo confidence"
        default: return "Low photo confidence"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                Label(confidenceText, systemImage: "camera.metering.center.weighted")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                Spacer(minLength: AppSpacing.compact)

                Text("\(Int((review.overallConfidence * 100).rounded()))%")
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }

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

            if !review.clarificationQuestions.isEmpty {
                Divider()
                Text("Before You Log")
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)

                ForEach(Array(review.clarificationQuestions.enumerated()), id: \.offset) { _, question in
                    Label(question, systemImage: "questionmark.circle")
                        .appTextRole(.secondary)
                        .foregroundStyle(AppPalette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                "Photo confidence: \(Int((min(max(review.confidence, 0), 1) * 100).rounded()))%",
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

            if let question = review.clarificationQuestion,
               !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(question, systemImage: "questionmark.circle")
                    .foregroundStyle(AppPalette.caution)
            }
        }
        .appTextRole(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var rangeText: String? {
        guard let low = review.portionLowGrams, let high = review.portionHighGrams else { return nil }
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
            Image(systemName: "checkmark.shield")
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(AppPalette.caution)
                .frame(width: 40, height: 40)
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
