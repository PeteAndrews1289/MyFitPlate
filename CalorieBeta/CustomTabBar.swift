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
                .frame(width: 55, height: 55)
                .background(Color.brandPrimary.shadow(.drop(color: .brandPrimary.opacity(0.5), radius: 5, y: 3)))
                .clipShape(Circle())
                .shadow(radius: 3)
                .offset(y: -25)
        }
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
            Rectangle().fill(Material.bar).frame(height: 85).overlay(Divider(), alignment: .top)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    if index == tabs.count / 2 {
                        AnimatedActionButton(isActive: showingAddOptions, action: centerButtonAction)
                            .frame(maxWidth: .infinity)

                    } else {
                        let item = tabs[index]
                        Button {
                            if showingAddOptions {
                                withAnimation { showingAddOptions = false }
                            }
                            self.selectedIndex = index
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 22))
                                Text(item.name).font(.caption2)
                            }
                            .foregroundColor(selectedIndex == index && !showingAddOptions ? Color.brandPrimary : Color(UIColor.secondaryLabel))
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.frame(height: 55).padding(.bottom, 30).padding(.horizontal, 5)
        }.frame(height: 85)
    }
}
