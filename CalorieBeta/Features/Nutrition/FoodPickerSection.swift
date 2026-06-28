import SwiftUI

struct FoodPickerSection: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(size: 18, weight: .bold)
                    .foregroundColor(.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(size: 12, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 9) {
                    ForEach(foods) { food in
                        FoodPickerRow(
                            food: food,
                            isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                            onSelect: onSelect,
                            onQuickLog: onQuickLog,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

struct FoodPickerRow: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    @State private var offset: CGFloat = 0
    @State private var isSwipedRight: Bool = false
    @State private var isSwipedLeft: Bool = false

    private var detailText: String {
        guard food.calories > 0 || food.protein > 0 || food.carbs > 0 || food.fats > 0 else {
            return "Tap to review nutrition"
        }

        var parts: [String] = []
        if food.calories > 0 { parts.append("\(Int(food.calories.rounded())) cal") }
        if food.protein > 0 { parts.append("P \(Int(food.protein.rounded()))g") }
        if food.carbs > 0 { parts.append("C \(Int(food.carbs.rounded()))g") }
        if food.fats > 0 { parts.append("F \(Int(food.fats.rounded()))g") }
        return parts.joined(separator: "  ")
    }

    private var servingText: String {
        food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Serving details" : food.servingSize
    }

    var body: some View {
        ZStack(alignment: offset > 0 ? .leading : .trailing) {
            if isSwipedRight && onQuickLog != nil {
                HStack {
                    Button {
                        withAnimation(.easeInOut) {
                            if !isQuickLogged { onQuickLog?(food) }
                            offset = 0
                            isSwipedRight = false
                        }
                    } label: {
                        Image(systemName: isQuickLogged ? "checkmark" : "plus")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(isQuickLogged ? Color.accentPositive : Color.brandPrimary)
                    .contentShape(Rectangle())
                    .cornerRadius(18)
                    Spacer()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else if isSwipedLeft && onDelete != nil {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete?(food)
                            offset = 0
                            isSwipedLeft = false
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(Color.red)
                    .contentShape(Rectangle())
                    .cornerRadius(18)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button(action: {
                    if isSwipedRight || isSwipedLeft {
                        withAnimation(.easeInOut) {
                            offset = 0
                            isSwipedRight = false
                            isSwipedLeft = false
                        }
                    } else {
                        onSelect(food)
                    }
                }) {
                    HStack(spacing: 12) {
                        Text(FoodEmojiMapper.getEmoji(for: food.name))
                            .appFont(size: 23)
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                                .appFont(size: 15, weight: .bold)
                                .foregroundColor(.textPrimary)
                                .lineLimit(2)

                            Text(servingText)
                                .appFont(size: 12, weight: .medium)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .lineLimit(1)

                            Text(detailText)
                                .appFont(size: 11, weight: .semibold)
                                .foregroundColor(.brandPrimary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.right")
                            .appFont(size: 12, weight: .bold)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onQuickLog {
                    Button(action: { onQuickLog(food) }) {
                        Image(systemName: isQuickLogged ? "checkmark" : "plus")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(isQuickLogged ? Color.accentPositive : Color.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isQuickLogged)
                    .accessibilityLabel("Quick log \(food.name)")
                }

                if let onDelete {
                    Button(role: .destructive, action: { onDelete(food) }) {
                        Image(systemName: "trash")
                            .appFont(size: 14, weight: .semibold)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(food.name) from recent foods")
                }
            }
            .padding(12)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width > 0 && onQuickLog != nil {
                            if !isSwipedLeft {
                                offset = min(value.translation.width, 70)
                            } else {
                                offset = -70 + value.translation.width
                            }
                        } else if value.translation.width < 0 && onDelete != nil {
                            if !isSwipedRight {
                                offset = max(value.translation.width, -70)
                            } else {
                                offset = 70 + value.translation.width
                            }
                        }
                    }
                    .onEnded { value in
                        withAnimation(.easeInOut) {
                            if value.translation.width > 50 && onQuickLog != nil {
                                offset = 70
                                isSwipedRight = true
                                isSwipedLeft = false
                            } else if value.translation.width < -50 && onDelete != nil {
                                offset = -70
                                isSwipedLeft = true
                                isSwipedRight = false
                            } else {
                                offset = 0
                                isSwipedRight = false
                                isSwipedLeft = false
                            }
                        }
                    }
            )
        }
    }
}

