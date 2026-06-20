import SwiftUI

struct AnimatedActionButton: View {
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(Angle(degrees: isActive ? 45 : 0))
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(Color.brandPrimary)
                        .shadow(color: Color.brandPrimary.opacity(0.34), radius: 14, x: 0, y: 8)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 8)
                .offset(y: -26)
        }
        .buttonStyle(.plain)
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
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: -4)
                .padding(.horizontal, 12)
                .frame(height: 74)
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
                            self.selectedIndex = index
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 21, weight: isSelected ? .semibold : .medium))
                                    .frame(width: 36, height: 28)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.brandPrimary.opacity(0.14) : Color.clear)
                                    )

                                Text(item.name)
                                    .appFont(size: 11, weight: isSelected ? .semibold : .regular)
                            }
                            .foregroundColor(isSelected ? Color.brandPrimary : Color(UIColor.secondaryLabel))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }.frame(height: 58).padding(.bottom, 24).padding(.horizontal, 16)
        }.frame(height: 92)
    }
}
