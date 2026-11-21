import SwiftUI

struct GrocerySummaryCard: View {
    let items: [GroceryListItem]
    let onScan: () -> Void
    let onAddManual: () -> Void

    private var completedCount: Int { items.filter(\.isCompleted).count }
    private var remainingCount: Int { max(items.count - completedCount, 0) }

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                Text(remainingCount == 0 ? "All items checked" : "\(remainingCount.formatted()) left to buy")
                    .appTextRole(.control)
                Text("\(completedCount.formatted()) of \(items.count.formatted()) checked")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .accessibilityIdentifier("grocery_summary_metrics")
            }
            Spacer(minLength: AppSpacing.compact)
            Button(action: onAddManual) { Image(systemName: "plus") }
                .buttonStyle(AppIconButtonStyle(.brand))
                .accessibilityLabel("Add grocery item")
                .accessibilityIdentifier("grocery_add_item")
            Button(action: onScan) { Image(systemName: "barcode.viewfinder") }
                .buttonStyle(AppIconButtonStyle(.neutral))
                .accessibilityLabel("Scan barcode")
                .accessibilityIdentifier("grocery_scan_item")
        }
        .padding(.vertical, AppSpacing.compact)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grocery_summary")
    }
}
