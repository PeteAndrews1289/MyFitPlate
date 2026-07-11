import SwiftUI

struct QuickLogActionButton: View {
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.brandPrimary)
                    .rotationEffect(Angle(degrees: isActive ? 45 : 0))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.brandPrimary, lineWidth: 1.6)
                    )

                Text("Quick Log")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 108, height: 44)
            .background(
                Capsule()
                    .fill(Color.backgroundPrimary.opacity(0.96))
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .overlay(
                Capsule()
                    .stroke(Color(UIColor.separator).opacity(0.28), lineWidth: 1)
            )
            .contentShape(Capsule())
            .scaleEffect(isActive ? 0.96 : 1.0)
            .animation(.interpolatingSpring(stiffness: 250, damping: 15), value: isActive)
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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 10)
                .frame(height: 72)
                .padding(.bottom, 4)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    let item = tabs[index]
                    let isSelected = selectedIndex == index && !showingAddOptions
                    Button {
                        if showingAddOptions {
                            withAnimation { showingAddOptions = false }
                        }
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 25)) {
                            self.selectedIndex = index
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 21, weight: isSelected ? .bold : .medium))
                                .frame(width: 38, height: 28)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.brandPrimary.opacity(0.15) : Color.clear)
                                )
                                .scaleEffect(isSelected ? 1.05 : 1.0)

                            Text(item.name)
                                .appFont(size: 10, weight: isSelected ? .bold : .medium)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(isSelected ? Color.brandPrimary : Color(UIColor.secondaryLabel))
                        .animation(.easeOut(duration: 0.2), value: isSelected)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("tab_\(item.name.lowercased().replacingOccurrences(of: " ", with: "_"))")
                }
            }
            .frame(height: 54)
            .padding(.bottom, 13)
            .padding(.horizontal, 12)

            QuickLogActionButton(isActive: showingAddOptions, action: centerButtonAction)
                .accessibilityIdentifier("quick_log_button")
                .frame(maxWidth: .infinity)
                .padding(.bottom, 64)
                .opacity(showingAddOptions ? 0 : 1)
                .scaleEffect(showingAddOptions ? 0.82 : 1)
                .allowsHitTesting(!showingAddOptions)
                .accessibilityHidden(showingAddOptions)
        }
        // The lifted control stays inside this layout region so its visible and tappable
        // frames are identical and touches cannot fall through to Home content.
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .animation(.easeOut(duration: 0.16), value: showingAddOptions)
    }
}
