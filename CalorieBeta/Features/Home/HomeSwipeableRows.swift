import SwiftUI

struct SwipeableExerciseRowView: View {
    let exercise: LoggedExercise
    let onDelete: (String) -> Void
    let onTap: (LoggedExercise) -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwiped && exercise.source != "HealthKit" {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete(exercise.id)
                            offset = 0
                            isSwiped = false
                        }
                    } label: {
                        Image(systemName: "trash").foregroundColor(.white).frame(width: 60, height: 40, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle()).background(AppPalette.critical).contentShape(Rectangle()).cornerRadius(8)
                }
                .padding(.vertical, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                let exerciseType = RoutineEditorDefaults.inferredType(name: exercise.name, category: nil)
                Image(systemName: exerciseType.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.effort)
                    .frame(width: 38, height: 38)
                    .background(AppPalette.effort.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(exercise.name)
                            .appFont(size: 15, weight: .semibold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        if exercise.source == "HealthKit" {
                            Image("Apple_Health")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                    }

                    Text(exerciseSubtitle)
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(exercise.caloriesBurned.rounded()))")
                        .appFont(size: 16, weight: .bold)
                        .foregroundStyle(AppPalette.text)
                    Text("cal")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture {
                if !isSwiped {
                    onTap(exercise)
                } else {
                    withAnimation(.easeInOut) { offset = 0; isSwiped = false }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard exercise.source != "HealthKit" else { return }
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard exercise.source != "HealthKit" else { return }
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.easeInOut) {
                            if value.translation.width < -50 {
                                offset = -70
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("diary_activity_\(exercise.id)")
            .accessibilityAction { onTap(exercise) }
            .accessibilityHint(exercise.source == "HealthKit"
                ? "Edit the MyFitPlate copy. Delete the original workout in Apple Health to remove this import."
                : "View or edit this activity")
        }
        .padding(.bottom, 2)
    }

    private var exerciseSubtitle: String {
        var parts: [String] = []
        if let duration = exercise.durationMinutes, duration > 0 {
            parts.append("\(duration) min")
        }
        parts.append(exercise.source == "HealthKit" ? "Apple Health" : "Manual")
        return parts.joined(separator: " • ")
    }
}

struct DiaryFoodRow: View {
    private let name: String
    private let portion: String
    private let calories: String
    private let protein: String
    private let carbs: String
    private let fats: String
    private let badge: FoodTrustMiniBadge
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(food: FoodItem) {
        // FoodItem equality reflects identity. Keep the values this row displays so an edit
        // under the same diary ID refreshes the serving, nutrients and source badge together.
        name = food.name
        portion = ServingNutritionCalculator.displayPortion(food.servingSize)
        calories = food.calories.rounded().formatted()
        protein = food.protein.rounded().formatted()
        carbs = food.carbs.rounded().formatted()
        fats = food.fats.rounded().formatted()
        badge = FoodTrustMiniBadge(food: food, source: "recent_tap")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .appTextRole(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppPalette.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !portion.isEmpty {
                        Text(portion)
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        foodCalories
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize {
                    foodCalories
                        .fixedSize()
                }
            }

            // Nutrition has the row's full width, so long food names and the adjacent
            // food-options control cannot squeeze the macros or evidence into ellipses.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.compact) {
                    macroSummaryText.fixedSize()
                    Spacer(minLength: 0)
                    if badge.needsAttention { badge.fixedSize() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    macroSummaryText
                        .fixedSize(horizontal: false, vertical: true)
                    if badge.needsAttention { badge.fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var foodCalories: some View {
        Text("\(calories) cal")
            .appTextRole(.body)
            .fontWeight(.semibold)
            .foregroundStyle(AppPalette.text)
            .monospacedDigit()
    }

    private var macroSummary: String {
        "P \(protein) g · C \(carbs) g · F \(fats) g"
    }

    private var macroSummaryText: some View {
        Text(macroSummary)
            .appTextRole(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(protein) grams protein, \(carbs) grams carbohydrates, \(fats) grams fat")
    }
}

struct SwipeableFoodItemView: View {
    let initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    let onDelete: (String) -> Void
    let onLogUpdated: () -> Void
    let date: Date
    let mealName: String
    let dayContext: DiaryDayContext?
    var onMove: ((String) -> Void)?
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false
    @State private var showDetailView = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwiped {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete(initialFoodItem.id)
                            offset = 0
                            isSwiped = false
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 58, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(AppPalette.critical)
                    .contentShape(Rectangle())
                    .cornerRadius(12)
                }
                .padding(.vertical, 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            DiaryFoodRow(food: initialFoodItem)
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture {
                if !isSwiped {
                    showDetailView = true
                } else {
                    withAnimation(.easeInOut) {
                        offset = 0
                        isSwiped = false
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.easeInOut) {
                            if value.translation.width < -50 {
                                offset = -70
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
            .contextMenu {
                Button("Edit serving", systemImage: "pencil") { showDetailView = true }
                if let onMove {
                    Menu("Move to meal", systemImage: "arrow.right") {
                        ForEach(["Breakfast", "Lunch", "Dinner", "Snacks"], id: \.self) { meal in
                            Button(meal) { onMove(meal) }
                        }
                    }
                }
                Button("Delete food", systemImage: "trash", role: .destructive) { onDelete(initialFoodItem.id) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showDetailView = true }
            .accessibilityAction(named: "Delete food") { onDelete(initialFoodItem.id) }
            .accessibilityIdentifier("diary_food_\(initialFoodItem.id)")
        }
        .navigationDestination(isPresented: $showDetailView) {
            FoodDetailView(
                initialFoodItem: initialFoodItem,
                dailyLog: $dailyLog,
                date: date,
                source: "log_swipe", targetMealName: mealName,
                onLogUpdated: onLogUpdated, dayContext: dayContext
            )
        }
        .padding(.bottom, 1)
    }
}
