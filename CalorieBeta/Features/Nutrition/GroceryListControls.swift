import SwiftUI

struct GroceryListDisplayControls: View {
    let completedCount: Int
    @Binding var hideCompletedItems: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                hideCompletedItems.toggle()
                HapticManager.instance.feedback(.light)
            } label: {
                Label(
                    hideCompletedItems ? "Show Done" : "Hide Done",
                    systemImage: hideCompletedItems ? "eye.fill" : "eye.slash.fill"
                )
                .appFont(size: 13, weight: .bold)
                .foregroundColor(completedCount == 0 ? Color(UIColor.tertiaryLabel) : .brandPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(completedCount == 0)

            Text("\(completedCount) checked")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

