import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedIndex: Int
    let centerButtonAction: () -> Void

    let tabs: [(icon: String, name: String)] = [
        ("house", "Home"),
        ("message", "Maia"),
        ("", ""),
        ("chart.xyaxis.line", "Weight"),
        ("chart.bar.xaxis", "Reports")
    ]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(Material.bar).frame(height: 85).overlay(Divider(), alignment: .top)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    if index == tabs.count / 2 {
                        Button(action: centerButtonAction) {
                            Image(systemName: "plus.circle.fill").resizable().scaledToFit()
                                .frame(width: 55, height: 55).foregroundColor(Color.white)
                                .background(Color.accentColor).clipShape(Circle()).shadow(radius: 3).offset(y: -25)
                        }.frame(maxWidth: .infinity)
                    } else {
                        let item = tabs[index]
                        Button { self.selectedIndex = index } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 22))
                                Text(item.name).font(.caption2)
                            }
                            .foregroundColor(selectedIndex == index ? Color.accentColor : Color.gray)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.frame(height: 55).padding(.bottom, 30).padding(.horizontal, 5)
        }.frame(height: 85)
    }
}
