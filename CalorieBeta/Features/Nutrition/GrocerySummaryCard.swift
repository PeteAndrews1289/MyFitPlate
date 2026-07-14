import SwiftUI

struct GrocerySummaryCard: View {
    let items: [GroceryListItem]
    let onScan: () -> Void
    let onAddManual: () -> Void

    private var totalCount: Int {
        items.count
    }

    private var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    private var remainingCount: Int {
        max(totalCount - completedCount, 0)
    }

    private var categoryCount: Int {
        Set(items.map(\.category)).count
    }

    private var progress: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(completedCount) / CGFloat(totalCount)
    }

    private var categoryLabel: String {
        categoryCount == 1 ? "category" : "categories"
    }

    private var progressLabel: String {
        if completedCount == totalCount {
            return "All items checked"
        }
        return "\(Int((progress * 100).rounded()).formatted())% checked"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Shopping Run",
                subtitle: "\(remainingCount.formatted()) left across \(categoryCount.formatted()) \(categoryLabel)."
            ) {
                HStack(spacing: AppSpacing.compact) {
                    Button(action: onAddManual) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(AppIconButtonStyle(.brand))
                    .accessibilityLabel("Add grocery item")
                    .accessibilityIdentifier("grocery_add_item")

                    Button(action: onScan) {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .buttonStyle(AppIconButtonStyle(.neutral))
                    .accessibilityLabel("Scan barcode")
                    .accessibilityIdentifier("grocery_scan_item")
                }
            }

            AppMetricStrip(items: [
                AppMetricItem(label: "Items", value: totalCount.formatted()),
                AppMetricItem(label: "Checked", value: completedCount.formatted(), accent: .accentPositive),
                AppMetricItem(label: "Left", value: remainingCount.formatted(), accent: .orange)
            ])
            .accessibilityIdentifier("grocery_summary_metrics")

            VStack(alignment: .leading, spacing: AppSpacing.compact) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppPalette.separator.opacity(0.5))

                        Capsule()
                            .fill(Color.accentPositive)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 7)
                .accessibilityHidden(true)

                Text(progressLabel)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shopping progress, \(progressLabel)")
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grocery_summary")
    }
}
