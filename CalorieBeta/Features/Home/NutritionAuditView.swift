import SwiftUI

struct NutritionAuditLaunchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Food Trust")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Sources, cross-checks, and items to fix.")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(12)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct NutritionAuditView: View {
    let dailyLog: DailyLog
    @Binding var dailyLogBinding: DailyLog?
    let date: Date
    @Environment(\.dismiss) private var dismiss

    private var dailyStatus: NutritionCalorieConsistency.Status {
        dailyLog.calorieConsistencyStatus()
    }

    private var allFoods: [FoodItem] {
        dailyLog.meals.flatMap(\.foodItems)
    }

    private var auditItems: [NutritionAuditItem] {
        allFoods.map(NutritionAuditItem.init(food:))
    }

    private var needsReviewItems: [NutritionAuditItem] {
        auditItems
            .filter(\.needsReview)
            .sorted { $0.reviewPriority > $1.reviewPriority }
    }

    private var crossVerifiedItems: [NutritionAuditItem] {
        auditItems
            .filter(\.isCrossVerified)
            .sorted { $0.evaluation.score > $1.evaluation.score }
    }

    private var userReviewedItems: [NutritionAuditItem] {
        auditItems
            .filter(\.isUserReviewed)
            .sorted { $0.reviewedSortRank > $1.reviewedSortRank }
    }

    private var totalFoods: Int {
        allFoods.count
    }

    private var suspiciousItemCount: Int {
        auditItems.filter { FoodDataSanity.isSuspicious($0.food) }.count
    }

    private var mismatchItemCount: Int {
        auditItems.filter(\.hasCalorieMathFinding).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trust Hub")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Review sources, cross-checks, and nutrition math for today's logged foods.")
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                NutritionConsistencyNoticeCard(status: dailyStatus, style: .detail)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DiaryMetricPill(title: "Foods", value: "\(totalFoods)", subtitle: "logged", icon: "fork.knife", color: .brandPrimary)
                    DiaryMetricPill(title: "Review", value: "\(needsReviewItems.count)", subtitle: "items", icon: "exclamationmark.triangle.fill", color: .orange)
                    DiaryMetricPill(title: "Cross-Checked", value: "\(crossVerifiedItems.count)", subtitle: "foods", icon: "checkmark.seal.fill", color: .accentPositiveText)
                    DiaryMetricPill(title: "Reviewed", value: "\(userReviewedItems.count)", subtitle: "by you", icon: "person.crop.circle.badge.checkmark", color: .accentProtein)
                }

                if totalFoods == 0 {
                    NutritionAuditEmptyState()
                } else {
                    auditSection(
                        title: "Needs review",
                        subtitle: "Low-trust, estimated, or mismatched entries.",
                        items: needsReviewItems,
                        emptyMessage: "No foods need review right now.",
                        tint: .orange,
                        icon: "exclamationmark.triangle.fill"
                    )

                    auditSection(
                        title: "Cross-verified",
                        subtitle: "Calories and macros matched across independent databases.",
                        items: crossVerifiedItems,
                        emptyMessage: "No cross-verified foods logged today.",
                        tint: .accentPositiveText,
                        icon: "checkmark.seal.fill"
                    )

                    auditSection(
                        title: "Reviewed by you",
                        subtitle: "Entries you confirmed or corrected.",
                        items: userReviewedItems,
                        emptyMessage: "No user-reviewed foods logged today.",
                        tint: .accentProtein,
                        icon: "person.crop.circle.badge.checkmark"
                    )
                }
            }
            .padding(16)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: logTrustHubViewed)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func logTrustHubViewed() {
        DIContainer.shared.analyticsManager?.logEvent("trust_hub_viewed", parameters: [
            "total_foods": totalFoods,
            "trust_model_version": FoodTrustEvaluation.modelVersion,
            "needs_review_count": needsReviewItems.count,
            "cross_verified_count": crossVerifiedItems.count,
            "user_reviewed_count": userReviewedItems.count,
            "suspicious_count": suspiciousItemCount,
            "mismatch_count": mismatchItemCount
        ])
    }

    private func auditSection(
        title: String,
        subtitle: String,
        items: [NutritionAuditItem],
        emptyMessage: String,
        tint: Color,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(size: 18, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text(subtitle)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if items.isEmpty {
                NutritionAuditSectionEmptyRow(message: emptyMessage, tint: tint)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        FoodDetailView(
                            initialFoodItem: item.food,
                            dailyLog: $dailyLogBinding,
                            date: date,
                            source: "nutrition_audit",
                            onLogUpdated: { }
                        )
                    } label: {
                        NutritionAuditFoodRow(item: item, tint: tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct NutritionAuditFoodRow: View {
    let item: NutritionAuditItem
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(FoodEmojiMapper.getEmoji(for: item.food.name))
                .appFont(size: 24)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.food.name)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.descriptor.title)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Text(item.evaluation.label)
                        .appFont(size: 10, weight: .bold)
                        .foregroundColor(item.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.tint.opacity(0.10), in: Capsule())
                }

                Text(item.statusLine)
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(item.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.evaluation.score)")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(item.tint)

                Text("/99")
                    .appFont(size: 10, weight: .bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .padding(12)
        .background(Color.backgroundPrimary.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NutritionAuditSectionEmptyRow: View {
    let message: String
    let tint: Color

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(Color(UIColor.secondaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.backgroundPrimary.opacity(0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .tint(tint)
    }
}

private struct NutritionAuditEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 28, weight: .bold)
                .foregroundColor(.accentPositiveText)
                .frame(width: 54, height: 54)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            Text("Nothing to audit yet")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Log a food and this hub will show source quality, cross-checks, and anything that needs review.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct NutritionAuditItem: Identifiable {
    let food: FoodItem
    let descriptor: FoodSourceDescriptor
    let evaluation: FoodTrustEvaluation
    let consistencyStatus: NutritionCalorieConsistency.Status
    let sanityFindings: [FoodDataSanity.Finding]

    var id: String { food.id }

    init(food: FoodItem) {
        let descriptor = FoodSourceClassifier.descriptor(
            for: "nutrition_audit",
            foodID: food.id,
            metadata: food.sourceMetadata
        )
        self.food = food
        self.descriptor = descriptor
        self.evaluation = FoodTrustEvaluation.evaluate(
            item: food,
            descriptor: descriptor,
            metadata: food.sourceMetadata
        )
        self.consistencyStatus = food.calorieConsistencyStatus
        self.sanityFindings = FoodDataSanity.findings(for: food)
    }

    var needsReview: Bool {
        evaluation.level == .review ||
        evaluation.level == .low ||
        !sanityFindings.isEmpty
    }

    var isCrossVerified: Bool {
        food.sourceMetadata?.hasIndependentCrossVerification == true
    }

    var isUserReviewed: Bool {
        switch food.sourceMetadata?.reviewStatus {
        case .userConfirmed, .userEdited:
            return true
        case .notRequired, .unreviewed, nil:
            return false
        }
    }

    var reviewedSortRank: Int {
        food.sourceMetadata?.reviewStatus == .userEdited ? 2 : 1
    }

    var reviewPriority: Double {
        let levelScore: Double
        if evaluation.requiresCorrection {
            levelScore = 5
        } else {
            switch evaluation.level {
            case .low:
                levelScore = 4
            case .review:
                levelScore = 3
            case .strong:
                levelScore = 2
            case .excellent:
                levelScore = 1
            }
        }
        return levelScore * 1_000 + consistencyStatus.mismatchAmount
    }

    var tint: Color {
        switch evaluation.level {
        case .excellent, .strong:
            return .accentPositiveText
        case .review:
            return .orange
        case .low:
            return evaluation.requiresCorrection ? .red : .orange
        }
    }

    var hasCalorieMathFinding: Bool {
        sanityFindings.contains {
            $0.id == "macros_without_calories" ||
            $0.id == "calories_undercount" ||
            $0.id == "calories_below_macro_estimate" ||
            $0.id == "calories_exceed_macros"
        }
    }

    var statusLine: String {
        if let finding = sanityFindings.first {
            return finding.message
        }

        let sources = food.sourceMetadata?.validatedCrossVerifiedBy ?? []
        if !sources.isEmpty {
            return "Calories and macros matched \(sources.prefix(2).joined(separator: ", "))"
        }

        switch food.sourceMetadata?.reviewStatus {
        case .userEdited:
            return "Corrected and saved by you"
        case .userConfirmed:
            return "Reviewed by you"
        case .notRequired, .unreviewed, nil:
            return evaluation.summary
        }
    }
}
