import SwiftUI

struct GroceryAllCompleteState: View {
    let onShowCompleted: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "checkmark.seal.fill")
                .appTextRole(.screenTitle)
                .foregroundStyle(Color.accentPositive)
                .frame(width: 56, height: 56)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))

            VStack(spacing: 4) {
                Text("Everything Is Checked")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text("Checked items are hidden so the remaining shopping view stays focused.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Show Checked Items", action: onShowCompleted)
                .buttonStyle(AppActionButtonStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
        .accessibilityIdentifier("grocery_all_complete")
    }
}

struct GroceryListLoadingState: View {
    var body: some View {
        VStack(spacing: AppSpacing.row) {
            ProgressView()
                .tint(AppPalette.brand)

            Text("Loading Grocery List")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)

            Text("Pulling together your planned and manually added items.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .accessibilityIdentifier("grocery_loading")
    }
}

struct GroceryListEmptyState: View {
    let onScan: () -> Void
    let onAddManual: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "cart")
                .appTextRole(.screenTitle)
                .foregroundStyle(AppPalette.brand)
                .frame(width: 64, height: 64)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))

            VStack(spacing: 4) {
                Text("No Grocery List Yet")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text("A meal plan can build this automatically, or you can add what you need now.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.row) {
                Button(action: onAddManual) {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(AppActionButtonStyle(.primary))

                Button(action: onScan) {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(AppActionButtonStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
        .accessibilityIdentifier("grocery_empty")
    }
}
