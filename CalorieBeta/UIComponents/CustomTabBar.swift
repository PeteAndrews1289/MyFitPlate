import SwiftUI

struct QuickLogActionButton: View {
    let isActive: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var buttonWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 150 : 112
    }

    private var buttonHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 50 : 42
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .appFont(size: 15, weight: .bold)
                    .foregroundColor(.brandForeground)
                    .rotationEffect(Angle(degrees: isActive ? 45 : 0))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.brandForeground, lineWidth: 1.6)
                    )

                Text("Quick Log")
                    .appFont(size: 15, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .background(
                Capsule()
                    .fill(AppPalette.canvas)
            )
            .overlay(
                Capsule()
                    .stroke(AppPalette.separator, lineWidth: 1)
            )
            .contentShape(Capsule())
            .scaleEffect(!reduceMotion && isActive ? 0.96 : 1.0)
            .animation(reduceMotion ? nil : AppMotion.standard, value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick Log")
        .accessibilityHint("Opens logging options")
    }
}

struct CustomTabBar: View {
    @Binding var selectedIndex: Int
    @Binding var showingAddOptions: Bool
    let centerButtonAction: () -> Void

    let tabs: [(icon: String, name: String)] = [
        ("house", "Home"),
        ("message", "Maia"),
        ("dumbbell", "Train"),
        ("calendar", "Meal Plan"),
        ("chart.bar.xaxis", "Reports")
    ]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 76 : 64
    }

    private var totalHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 118 : 104
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            AppPalette.canvas
                .frame(height: totalHeight + 12)
                .ignoresSafeArea(edges: .bottom)

            RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                        .stroke(AppPalette.separator, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 12)
                .frame(height: barHeight)
                .padding(.bottom, 4)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    let item = tabs[index]
                    let isSelected = selectedIndex == index && !showingAddOptions
                    Button {
                        if showingAddOptions {
                            withAnimation(reduceMotion ? nil : AppMotion.visibility) {
                                showingAddOptions = false
                            }
                        }
                        withAnimation(reduceMotion ? nil : AppMotion.standard) {
                            self.selectedIndex = index
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .symbolVariant(isSelected ? .fill : .none)
                                .font(.system(size: 21, weight: isSelected ? .bold : .medium))
                                .frame(width: 38, height: 24)

                            Capsule()
                                .fill(isSelected ? Color.brandPrimary : Color.clear)
                                .frame(width: 18, height: 2)

                            Text(item.name)
                                .appFont(size: 10.5, weight: isSelected ? .bold : .medium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: 64)
                        }
                        .foregroundColor(isSelected ? Color.brandForeground : Color(UIColor.secondaryLabel))
                        .animation(reduceMotion ? nil : AppMotion.visibility, value: isSelected)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("tab_\(item.name.lowercased().replacingOccurrences(of: " ", with: "_"))")
                }
            }
            .frame(height: barHeight - 8)
            .padding(.bottom, 10)
            .padding(.horizontal, 14)

            QuickLogActionButton(isActive: showingAddOptions, action: centerButtonAction)
                .accessibilityIdentifier("quick_log_button")
                .frame(maxWidth: .infinity)
                .padding(.bottom, barHeight)
        }
        // The lifted control stays inside this layout region so its visible and tappable
        // frames are identical and touches cannot fall through to Home content.
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .animation(reduceMotion ? nil : AppMotion.visibility, value: showingAddOptions)
    }
}
