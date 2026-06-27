import SwiftUI

struct AnimatedActionButton: View {
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .rotationEffect(Angle(degrees: isActive ? 45 : 0))
                .frame(width: 62, height: 62)
                .background(
                    Circle()
                        .fill(LinearGradient.brandGradient)
                        .shadow(color: Color.brandPrimary.opacity(0.5), radius: 16, x: 0, y: 8)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                )
                .clipShape(Circle())
                .offset(y: isActive ? -22 : -28)
                .scaleEffect(isActive ? 0.95 : 1.0)
                .animation(.interpolatingSpring(stiffness: 250, damping: 15), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick log")
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
        ("", ""),
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
                .padding(.horizontal, 12)
                .frame(height: 76)
                .padding(.bottom, 8)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    if index == tabs.count / 2 {
                        AnimatedActionButton(isActive: showingAddOptions, action: centerButtonAction)
                            .frame(maxWidth: .infinity)

                    } else {
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
                                    .font(.system(size: 22, weight: isSelected ? .bold : .medium))
                                    .frame(width: 40, height: 28)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.brandPrimary.opacity(0.15) : Color.clear)
                                    )
                                    .scaleEffect(isSelected ? 1.05 : 1.0)

                                Text(item.name)
                                    .appFont(size: 11, weight: isSelected ? .bold : .medium)
                            }
                            .foregroundColor(isSelected ? Color.brandPrimary : Color(UIColor.secondaryLabel))
                            .animation(.easeOut(duration: 0.2), value: isSelected)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tab_\(item.name.lowercased().replacingOccurrences(of: " ", with: "_"))")
                    }
                }
            }.frame(height: 60).padding(.bottom, 24).padding(.horizontal, 16)
        }.frame(height: 94)
    }
}
