import SwiftUI

struct GroceryUndoBanner: View {
    let itemName: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: "trash")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.caution)
                .accessibilityHidden(true)

            Text("\(itemName) removed")
                .appTextRole(.body)
                .foregroundStyle(AppPalette.text)
                .lineLimit(2)

            Spacer(minLength: AppSpacing.compact)

            Button("Undo", action: onUndo)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.brandText)
        }
        .appSurface(.emphasized)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grocery_delete_undo")
    }
}

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
                .foregroundStyle(AppPalette.brandText)
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

struct GroceryListLoadErrorState: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "icloud.slash")
                .appTextRole(.screenTitle)
                .foregroundStyle(AppPalette.caution)
                .frame(width: 64, height: 64)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.surface, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Grocery List Unavailable")
                    .appTextRole(.sectionTitle)
                    .foregroundStyle(AppPalette.text)

                Text("Your saved list was not changed. Check your connection and try loading it again.")
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
        .accessibilityIdentifier("grocery_load_error")
    }
}
