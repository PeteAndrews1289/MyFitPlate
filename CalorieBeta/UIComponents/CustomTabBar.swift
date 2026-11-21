import SwiftUI

struct QuickLogActionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(AppPalette.onBrand)
                .frame(width: 48, height: 48)
                .background(AppPalette.brand, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log food")
        .accessibilityHint("Opens food search for the selected diary day")
        .accessibilityShowsLargeContentViewer {
            Label("Log food", systemImage: "plus.circle")
        }
    }
}

/// A single navigation dock. Logging keeps its own touch target without occupying
/// a second row or covering the planner's bottom controls.
struct CustomTabBar: View {
    @Binding var selectedIndex: Int
    let onLogFood: () -> Void

    private let tabs: [(icon: String, title: String, label: String, id: String)] = [
        ("house", "Home", "Home", "tab_home"),
        ("message", "Maia", "Maia", "tab_maia"),
        ("dumbbell", "Train", "Train", "tab_train"),
        ("calendar", "Plan", "Meal Plan", "tab_meal_plan"),
        ("chart.bar.xaxis", "Reports", "Reports", "tab_reports")
    ]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { index in
                    tabButton(at: index)
                }
            }
            .padding(.horizontal, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .stroke(AppPalette.separator, lineWidth: 0.5)
            }

            QuickLogActionButton(action: onLogFood)
                .accessibilityIdentifier("quick_log_button")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main_navigation_dock")
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background { AppPalette.canvas.accessibilityHidden(true) }
    }

    private func tabButton(at index: Int) -> some View {
        let item = tabs[index]
        let isSelected = selectedIndex == index
        return Button {
            withAnimation(reduceMotion ? nil : AppMotion.visibility) {
                selectedIndex = index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .frame(height: 23)
                Text(item.title)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 12 : 11,
                                  weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.brandForeground : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(minWidth: 44, minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(item.id)
        .accessibilityShowsLargeContentViewer {
            Label(item.label, systemImage: item.icon)
        }
    }
}
