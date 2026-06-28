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
                    Text("Review nutrition audit")
                        .appFont(size: 13, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Find foods where macros and calories disagree.")
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

    private var mismatchedFoods: [FoodItem] {
        dailyLog.foodsWithMeaningfulCalorieMacroMismatch()
            .sorted { $0.calorieConsistencyStatus.mismatchAmount > $1.calorieConsistencyStatus.mismatchAmount }
    }

    private var totalFoods: Int {
        dailyLog.meals.flatMap(\.foodItems).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nutrition Audit")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("Logged calories stay official, but this shows where macro math suggests a different total.")
                        .appFont(size: 14, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }

                NutritionConsistencyNoticeCard(status: dailyStatus, style: .detail)

                HStack(spacing: 10) {
                    DiaryMetricPill(title: "Foods", value: "\(totalFoods)", subtitle: "logged", icon: "fork.knife", color: .brandPrimary)
                    DiaryMetricPill(title: "Flagged", value: "\(mismatchedFoods.count)", subtitle: "items", icon: "exclamationmark.triangle.fill", color: .orange)
                }

                if mismatchedFoods.isEmpty {
                    NutritionAuditEmptyState()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Items to review")
                            .appFont(size: 18, weight: .bold)
                            .foregroundColor(.textPrimary)

                        ForEach(mismatchedFoods) { food in
                            NavigationLink {
                                FoodDetailView(
                                    initialFoodItem: food,
                                    dailyLog: $dailyLogBinding,
                                    date: date,
                                    source: "nutrition_audit",
                                    onLogUpdated: { }
                                )
                            } label: {
                                NutritionAuditFoodRow(food: food)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct NutritionAuditFoodRow: View {
    let food: FoodItem

    private var status: NutritionCalorieConsistency.Status {
        food.calorieConsistencyStatus
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(FoodEmojiMapper.getEmoji(for: food.name))
                .appFont(size: 24)
                .frame(width: 42, height: 42)
                .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text(food.servingSize)
                    .appFont(size: 12, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .lineLimit(1)

                Text("Logged \(Int(status.loggedCalories.rounded())) cal • macros imply \(Int(status.macroDerivedCalories.rounded())) cal")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("\(Int(status.mismatchAmount.rounded()))")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.orange)
        }
        .padding(12)
        .background(Color.backgroundPrimary.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NutritionAuditEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 28, weight: .bold)
                .foregroundColor(.accentPositive)
                .frame(width: 54, height: 54)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            Text("No single food stands out")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("The daily gap is likely coming from smaller rounding differences across multiple foods.")
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
