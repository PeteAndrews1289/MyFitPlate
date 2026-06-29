import SwiftUI

struct FoodSearchActionGrid: View {
    let manualAction: () -> Void
    let quickAddAction: () -> Void
    let cameraAction: () -> Void
    let menuAction: () -> Void
    let barcodeAction: () -> Void
    let textAction: () -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            FoodSearchActionTile(title: "Quick Macros", subtitle: "Instant numbers", icon: "bolt.fill", action: quickAddAction)
            FoodSearchActionTile(title: "Manual Food", subtitle: "Custom entries", icon: "square.and.pencil", action: manualAction)
            FoodSearchActionTile(title: "Barcode", subtitle: "Scan package", icon: "barcode.viewfinder", action: barcodeAction)
            FoodSearchActionTile(title: "Camera", subtitle: "Snap meal", icon: "camera.fill", action: cameraAction)
            FoodSearchActionTile(title: "Menu", subtitle: "Scan menu", icon: "list.bullet.rectangle.portrait.fill", action: menuAction)
            FoodSearchActionTile(title: "Describe", subtitle: "Use text", icon: "text.bubble.fill", action: textAction)
        }
    }
}

struct FoodSearchActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct YesterdayLogActions: View {
    let selectedMeal: String
    let mealItemCount: Int
    let mealCalories: Double
    let dayItemCount: Int
    let dayCalories: Double
    let onLogMeal: () -> Void
    let onLogDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copy Yesterday")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 10) {
                yesterdayButton(
                    title: selectedMeal,
                    detail: detailText(count: mealItemCount, calories: mealCalories),
                    icon: "clock.arrow.circlepath",
                    isEnabled: mealItemCount > 0,
                    action: onLogMeal
                )

                yesterdayButton(
                    title: "Full Day",
                    detail: detailText(count: dayItemCount, calories: dayCalories),
                    icon: "calendar.badge.plus",
                    isEnabled: dayItemCount > 0,
                    action: onLogDay
                )
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailText(count: Int, calories: Double) -> String {
        guard count > 0 else { return "No items" }
        return "\(count) items • \(Int(calories.rounded())) cal"
    }

    private func yesterdayButton(title: String, detail: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(isEnabled ? .brandPrimary : Color(UIColor.tertiaryLabel))
                    .frame(width: 30, height: 30)
                    .background((isEnabled ? Color.brandPrimary : Color(UIColor.tertiaryLabel)).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .appFont(size: 14, weight: .bold)
                        .foregroundColor(isEnabled ? .textPrimary : Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Text(detail)
                        .appFont(size: 11, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(12)
            .background(Color.backgroundPrimary.opacity(isEnabled ? 0.78 : 0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
