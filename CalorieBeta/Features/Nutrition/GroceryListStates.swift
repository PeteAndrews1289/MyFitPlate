import SwiftUI

struct GroceryAllCompleteState: View {
    let onShowCompleted: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 30, weight: .bold)
                .foregroundColor(.accentPositive)
                .frame(width: 58, height: 58)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            VStack(spacing: 4) {
                Text("Everything visible is checked off")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Completed items are hidden for a cleaner shopping run.")
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
            }

            Button("Show Checked Items", action: onShowCompleted)
                .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .glassCard()
    }
}

struct GroceryListLoadingState: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Loading grocery list")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Pulling together your planned ingredients.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

struct GroceryListEmptyState: View {
    let onScan: () -> Void
    let onAddManual: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.fill")
                .appFont(size: 39, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 76, height: 76)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(spacing: 5) {
                Text("No grocery list yet")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Generate a meal plan to build one automatically, add an item, or scan as you shop.")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onAddManual) {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onScan) {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 40)
        .glassCard()
    }
}
