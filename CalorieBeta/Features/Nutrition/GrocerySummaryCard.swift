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
        return CGFloat(Double(completedCount) / Double(totalCount))
    }

    private var categoryLabel: String {
        categoryCount == 1 ? "category" : "categories"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shopping Run")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("\(remainingCount) left across \(categoryCount) \(categoryLabel).")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onAddManual) {
                        Image(systemName: "plus")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add grocery item")

                    Button(action: onScan) {
                        Image(systemName: "barcode.viewfinder")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan barcode")
                }
            }

            HStack(spacing: 10) {
                GroceryMetricTile(title: "Items", value: "\(totalCount)", color: .brandPrimary)
                GroceryMetricTile(title: "Done", value: "\(completedCount)", color: .accentPositive)
                GroceryMetricTile(title: "Left", value: "\(remainingCount)", color: .orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))

                        Capsule()
                            .fill(Color.accentPositive)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 8)

                Text(completedCount == totalCount ? "All set for this list." : "\(Int((progress * 100).rounded()))% checked off")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .padding(.vertical, 2)
        .glassCard()
    }
}

struct GroceryMetricTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 21, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
