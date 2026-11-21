import SwiftUI
import MyFitPlateCore

struct FoodSearchHeader: View {
    @Binding var searchText: String
    let placeholder: String
    let onClear: () -> Void
    let onSubmit: () -> Void
    var onMic: (() -> Void)?
    var isRecording: Bool = false
    var onFocusChange: ((Bool) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "magnifyingglass")
                    .appTextRole(.control)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            TextField(
                dynamicTypeSize.isAccessibilitySize ? "Search" : placeholder,
                text: $searchText
            )
                .appTextRole(.body)
                .lineLimit(1)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? (isFocused ? 4 : AppSpacing.row) : 0)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in onFocusChange?(focused) }
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .accessibilityLabel("Search foods")
                .accessibilityIdentifier("food_search_field")

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if let onMic = onMic {
                Button(action: onMic) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isRecording ? Color.accentProtein : AppPalette.brandText)
                        .frame(width: 44, height: 44)
                        .background(isRecording ? Color.accentProtein.opacity(0.15) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice search")
                .accessibilityValue(isRecording ? "Recording" : "Not recording")
            }
        }
        .padding(.horizontal, AppSpacing.row)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? (isFocused ? 72 : 104) : 54)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator.opacity(0.7), lineWidth: 0.5)
        }
    }
}
