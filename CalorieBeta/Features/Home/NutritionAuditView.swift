import SwiftUI

struct NutritionAuditLaunchButton: View {
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checklist")
                    .appFont(size: 13, weight: .bold)
                    .foregroundColor(AppPalette.caution)
                    .frame(width: 28, height: 28)
                    .background(AppPalette.caution.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Food Trust")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Sources, cross-checks, and items to fix.")
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .layoutPriority(dynamicTypeSize.isAccessibilitySize ? 1 : 0)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(AppPalette.caution.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review Food Trust. Sources, cross-checks, and items to fix.")
        .accessibilityHint("Opens the Trust Hub for today's foods.")
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

    private var trustCoverage: FoodTrustCoverage {
        FoodTrustCoverage.evaluate(items: allFoods)
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

    private var calorieCoveragePercent: Int {
        Int((trustCoverage.calorieFraction * 100).rounded())
    }

    private var proteinCoveragePercent: Int {
        Int((trustCoverage.proteinFraction * 100).rounded())
    }

    private var evidenceMapRows: [NutritionEvidenceMapCoverage] {
        NutritionEvidenceMapCoverage.make(from: auditItems)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trust Hub")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("See what supports today's nutrition, then fix the entries with the greatest impact.")
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                NutritionConsistencyNoticeCard(status: dailyStatus, style: .detail)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DiaryMetricPill(title: "Foods", value: "\(totalFoods)", subtitle: "logged", icon: "fork.knife", color: .brandPrimary)
                    DiaryMetricPill(title: "Review", value: "\(needsReviewItems.count)", subtitle: "items", icon: "exclamationmark.triangle.fill", color: AppPalette.caution)
                    DiaryMetricPill(title: "Calories", value: "\(calorieCoveragePercent)%", subtitle: "supported", icon: "flame.fill", color: .accentPositiveText)
                    DiaryMetricPill(title: "Protein", value: "\(proteinCoveragePercent)%", subtitle: "supported", icon: "bolt.fill", color: .accentProtein)
                }

                if totalFoods == 0 {
                    NutritionAuditEmptyState()
                } else {
                    NutritionEvidenceMap(rows: evidenceMapRows)

                    auditSection(
                        title: "Needs review",
                        subtitle: "Low-trust, estimated, or mismatched entries.",
                        items: needsReviewItems,
                        emptyMessage: "No foods need review right now.",
                        tint: AppPalette.caution,
                        icon: "exclamationmark.triangle.fill"
                    )

                    auditSection(
                        title: "Cross-database matches",
                        subtitle: "Calories and core macros agreed after serving normalization.",
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
            "trust_model_version": String(FoodTrustEvaluation.modelVersion),
            "needs_review_count": needsReviewItems.count,
            "cross_verified_count": crossVerifiedItems.count,
            "user_reviewed_count": userReviewedItems.count,
            "suspicious_count": suspiciousItemCount,
            "mismatch_count": mismatchItemCount,
            "supported_calorie_percent": calorieCoveragePercent,
            "supported_protein_percent": proteinCoveragePercent,
            "weakest_evidence_field": evidenceMapRows.min(by: { $0.fraction < $1.fraction })?.id.rawValue ?? "none"
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

private struct NutritionEvidenceMap: View {
    let rows: [NutritionEvidenceMapCoverage]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var weakestRow: NutritionEvidenceMapCoverage? {
        rows.min {
            if $0.fraction == $1.fraction {
                return $0.gapCount > $1.gapCount
            }
            return $0.fraction < $1.fraction
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            evidenceMapHeader

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppPalette.separator)
                    .frame(width: 2)
                    .padding(.leading, 17)
                    .padding(.vertical, 24)
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.row) {
                    ForEach(rows) { row in
                        NutritionEvidenceMapRow(row: row)
                    }
                }
            }

            if let weakestRow, weakestRow.gapCount > 0 {
                Label(weakestRow.insight, systemImage: "magnifyingglass")
                    .appFont(size: 13, weight: .medium)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(AppSpacing.row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        weakestRow.tint.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    )
            }
        }
        .appSurface(.interpreted)
        .accessibilityIdentifier("nutrition_evidence_map")
    }

    private var evidenceMapHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    HStack(alignment: .top, spacing: AppSpacing.row) {
                        evidenceMapTitle
                        Spacer(minLength: 0)
                        evidenceMapIcon
                    }
                    evidenceMapSubtitle
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.row) {
                    VStack(alignment: .leading, spacing: 3) {
                        evidenceMapTitle
                        evidenceMapSubtitle
                    }
                    Spacer(minLength: 0)
                    evidenceMapIcon
                }
            }
        }
    }

    private var evidenceMapTitle: some View {
        Text("Evidence Map")
            .appFont(size: 18, weight: .bold)
            .foregroundStyle(AppPalette.text)
    }

    private var evidenceMapSubtitle: some View {
        Text("Support by field. Source documentation and cross-database agreement remain separate.")
            .appFont(size: 13, weight: .medium)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var evidenceMapIcon: some View {
        Image(systemName: "scope")
            .appFont(size: 18, weight: .bold)
            .foregroundStyle(AppPalette.brandText)
            .frame(width: 42, height: 42)
            .background(
                AppPalette.brand.opacity(0.10),
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private struct NutritionEvidenceMapRow: View {
    let row: NutritionEvidenceMapCoverage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: row.icon)
                .appFont(size: 15, weight: .bold)
                .foregroundStyle(row.tint)
                .frame(width: 36, height: 36)
                .background(AppPalette.surface, in: Circle())
                .overlay {
                    Circle()
                        .stroke(row.tint.opacity(0.52), lineWidth: 1.5)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .appFont(size: 15, weight: .bold)
                                .foregroundStyle(AppPalette.text)
                            evidenceCount
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.compact) {
                            Text(row.title)
                                .appFont(size: 15, weight: .bold)
                                .foregroundStyle(AppPalette.text)
                            Spacer(minLength: 0)
                            evidenceCount
                        }
                    }
                }

                Text(row.detail)
                    .appFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView(value: row.fraction)
                    .tint(row.tint)
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(row.supportedCount) of \(row.totalCount). \(row.detail)")
    }

    private var evidenceCount: some View {
        Text("\(row.supportedCount) / \(row.totalCount) \(row.measure)")
            .appFont(size: 11, weight: .bold)
            .foregroundStyle(row.tint)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NutritionEvidenceMapCoverage: Identifiable {
    let id: FoodTrustEvidenceScope.Field
    let title: String
    let detail: String
    let measure: String
    let icon: String
    let supportedCount: Int
    let totalCount: Int

    var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(supportedCount) / Double(totalCount)
    }

    var gapCount: Int {
        max(totalCount - supportedCount, 0)
    }

    var tint: Color {
        if fraction >= 0.8 {
            return .accentPositiveText
        }
        return AppPalette.caution
    }

    var insight: String {
        switch id {
        case .identity:
            return "\(gapCount) \(foodWord) lack a durable provider record or verified barcode."
        case .serving:
            return "\(gapCount) \(foodWord) lack a comparable serving weight or a serving you reviewed."
        case .coreNutrition:
            return "\(gapCount) \(foodWord) still rely on a single source or estimate for calories and core macros."
        case .detailedNutrition:
            return "\(gapCount) \(foodWord) do not include detailed fats, fiber, vitamins, or minerals."
        case .ingredientsAndAllergens:
            return "\(gapCount) \(foodWord) do not include ingredient or allergen evidence."
        }
    }

    private var foodWord: String {
        gapCount == 1 ? "food" : "foods"
    }

    static func make(from items: [NutritionAuditItem]) -> [NutritionEvidenceMapCoverage] {
        let definitions: [(FoodTrustEvidenceScope.Field, String, String, String, String)] = [
            (
                .identity,
                "Product Identity",
                "Provider records or checksum-valid barcodes.",
                "documented",
                "barcode.viewfinder"
            ),
            (
                .serving,
                "Serving",
                "Comparable weights, label servings, or servings reviewed by you.",
                "grounded",
                "scalemass.fill"
            ),
            (
                .coreNutrition,
                "Core Nutrition",
                "Validated cross-database agreement or a correction saved by you.",
                "supported",
                "checkmark.seal.fill"
            ),
            (
                .detailedNutrition,
                "Detailed Nutrition",
                "Reported fiber, fats, vitamins, or minerals.",
                "reported",
                "list.bullet.rectangle.fill"
            )
        ]

        return definitions.map { field, title, detail, measure, icon in
            let supportedCount = items.filter { item in
                guard let scope = item.passport.scopes.first(where: { $0.field == field }) else {
                    return false
                }
                return supports(scope: scope, field: field)
            }.count

            return NutritionEvidenceMapCoverage(
                id: field,
                title: title,
                detail: detail,
                measure: measure,
                icon: icon,
                supportedCount: supportedCount,
                totalCount: items.count
            )
        }
    }

    private static func supports(
        scope: FoodTrustEvidenceScope,
        field: FoodTrustEvidenceScope.Field
    ) -> Bool {
        switch field {
        case .coreNutrition:
            return scope.state == .crossDatabaseAgreement || scope.state == .userReviewed
        case .identity, .serving, .detailedNutrition, .ingredientsAndAllergens:
            return scope.state == .crossDatabaseAgreement ||
                scope.state == .userReviewed ||
                scope.state == .sourceReported
        }
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

            Image(systemName: item.trailingIcon)
                .appFont(size: 14, weight: .bold)
                .foregroundColor(item.tint)
                .frame(width: 32, height: 32)
                .background(item.tint.opacity(0.10), in: Circle())
                .accessibilityHidden(true)
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
    let passport: FoodTrustPassport
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
        self.passport = FoodTrustPassport.evaluate(
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
        food.sourceMetadata?.hasCrossDatabaseAgreement == true
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
        let calories = food.calories.isFinite ? max(0, food.calories) : 0
        let protein = food.protein.isFinite ? max(0, food.protein) : 0
        let mismatch = consistencyStatus.mismatchAmount.isFinite
            ? max(0, consistencyStatus.mismatchAmount)
            : 0
        let nutritionImpact = calories + protein * 4
        return levelScore * 10_000 + mismatch * 10 + nutritionImpact
    }

    var tint: Color {
        switch evaluation.level {
        case .excellent, .strong:
            return .accentPositiveText
        case .review:
            return AppPalette.caution
        case .low:
            return evaluation.requiresCorrection ? AppPalette.critical : AppPalette.caution
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

    var trailingIcon: String {
        switch passport.coreNutrition.state {
        case .crossDatabaseAgreement: return "checkmark.seal.fill"
        case .userReviewed: return "person.crop.circle.badge.checkmark"
        case .sourceReported: return "doc.text.fill"
        case .estimated: return "sparkles"
        case .needsCorrection: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        case .notChecked: return "minus.circle.fill"
        }
    }
}
