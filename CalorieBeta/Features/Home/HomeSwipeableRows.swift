import SwiftUI

struct SwipeableExerciseRowView: View {
    let exercise: LoggedExercise
    let onDelete: (String) -> Void
    let onTap: (LoggedExercise) -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if isSwiped {
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
                    .buttonStyle(PlainButtonStyle()).background(Color.red).contentShape(Rectangle()).cornerRadius(8)
                }
                .padding(.vertical, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Text(ExerciseEmojiMapper.getEmoji(for: exercise.name))
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                        .foregroundColor(.accentPositive)
                    Text("cal")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture {
                if !isSwiped {
                    onTap(exercise)
                } else {
                    withAnimation(.easeInOut) { offset = 0; isSwiped = false }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
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

struct SwipeableFoodItemView: View {
    let initialFoodItem: FoodItem
    @Binding var dailyLog: DailyLog?
    let onDelete: (String) -> Void
    let onLogUpdated: () -> Void
    let date: Date
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
                    .background(Color.red)
                    .contentShape(Rectangle())
                    .cornerRadius(12)
                }
                .padding(.vertical, 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                Text(FoodEmojiMapper.getEmoji(for: initialFoodItem.name))
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(initialFoodItem.name)
                        .lineLimit(1)
                        .appFont(size: 16, weight: .semibold)
                        .foregroundColor(.textPrimary)

                    Text(macroSummary)
                        .appFont(size: 12)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(initialFoodItem.calories.rounded()))")
                        .appFont(size: 16, weight: .bold)
                        .foregroundColor(.textPrimary)
                    Text("cal")
                        .appFont(size: 11)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Image(systemName: "chevron.right")
                    .appFont(size: 11, weight: .bold)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.backgroundSecondary.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -70)
                        } else if isSwiped && value.translation.width > 0 {
                            offset = -70 + value.translation.width
                        }
                    }
                    .onEnded { value in
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
        }
        .navigationDestination(isPresented: $showDetailView) {
            FoodDetailView(
                initialFoodItem: initialFoodItem,
                dailyLog: $dailyLog,
                date: date,
                source: "log_swipe",
                onLogUpdated: onLogUpdated
            )
        }
        .padding(.bottom, 1)
    }

    private var macroSummary: String {
        "P \(Int(initialFoodItem.protein.rounded()))g • C \(Int(initialFoodItem.carbs.rounded()))g • F \(Int(initialFoodItem.fats.rounded()))g"
    }
}
