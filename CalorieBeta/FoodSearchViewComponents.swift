import SwiftUI
import FirebaseAnalytics

struct FoodSearchRow: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    @State private var offset: CGFloat = 0
    @State private var isSwipedRight = false
    @State private var isSwipedLeft = false

    private var servingText: String {
        let trimmed = food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Usual serving" : trimmed
    }

    private var detailText: String {
        let cal = Int(food.calories.rounded())
        let pro = Int(food.protein.rounded())
        return "\(cal) cal • \(pro)g P"
    }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())

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
                            .font(.system(size: 23))
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.textPrimary)
                                .lineLimit(2)

                            Text(servingText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                                .lineLimit(1)

                            Text(detailText)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.brandPrimary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onQuickLog {
                    Button(action: { onQuickLog(food) }) {
                        Image(systemName: isQuickLogged ? "checkmark" : "plus")
                            .font(.system(size: 16, weight: .bold))
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
                            .font(.system(size: 14, weight: .semibold))
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

struct FoodHorizontalScroller: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(foods) { food in
                            FoodCard(
                                food: food,
                                isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                                onSelect: onSelect,
                                onQuickLog: onQuickLog
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -4)
            }
        }
    }
}

struct FoodCard: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?

    private var servingText: String {
        let trimmed = food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Usual serving" : trimmed
    }

    var body: some View {
        Button(action: { onSelect(food) }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(FoodEmojiMapper.getEmoji(for: food.name))
                        .font(.system(size: 32))

                    Spacer()

                    if let onQuickLog = onQuickLog {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            onQuickLog(food)
                        }) {
                            Image(systemName: isQuickLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(isQuickLogged ? .accentPositive : .brandPrimary)
                        }
                        .disabled(isQuickLogged)
                        .accessibilityLabel(isQuickLogged ? "\(food.name) logged" : "Quick log \(food.name)")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(servingText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Text("\(Int(food.calories.rounded())) cal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.brandPrimary)
                }
            }
            .padding(14)
            .frame(width: 146, height: 150)
            .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FoodSearchLoadingState: View {
    let query: String

    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Searching foods")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct FoodSearchEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 48, height: 48)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
