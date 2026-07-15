import SwiftUI

struct GroceryListDisplayControls: View {
    let completedCount: Int
    @Binding var hideCompletedItems: Bool

    private var detail: String {
        if completedCount == 0 {
            return "No checked items yet."
        }
        return hideCompletedItems
            ? "\(completedCount.formatted()) checked item\(completedCount == 1 ? "" : "s") hidden."
            : "\(completedCount.formatted()) checked item\(completedCount == 1 ? "" : "s") visible."
    }

    var body: some View {
        Toggle(isOn: $hideCompletedItems) {
            HStack(alignment: .top, spacing: AppSpacing.row) {
                Image(systemName: hideCompletedItems ? "eye.slash.fill" : "eye.fill")
                    .appTextRole(.control)
                    .foregroundStyle(completedCount == 0 ? Color.secondary : AppPalette.brandText)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Hide Checked Items")
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)

                    Text(detail)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(AppPalette.brand)
        .disabled(completedCount == 0)
        .onChange(of: hideCompletedItems) { _, _ in
            HapticManager.instance.feedback(.light)
        }
        .padding(.vertical, AppSpacing.compact)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityIdentifier("grocery_display_controls")
    }
}
