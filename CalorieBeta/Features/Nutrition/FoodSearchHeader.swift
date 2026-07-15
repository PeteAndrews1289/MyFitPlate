import SwiftUI
import MyFitPlateCore

struct FoodSearchHeader: View {
    @Binding var searchText: String
    let placeholder: String
    let onClear: () -> Void
    let onSubmit: () -> Void
    var onMic: (() -> Void)?
    var isRecording: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: AppSpacing.compact) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "magnifyingglass")
                    .appTextRole(.control)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            TextField(dynamicTypeSize.isAccessibilitySize ? "Search foods" : placeholder, text: $searchText)
                .appTextRole(.body)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .accessibilityIdentifier("food_search_field")

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .appTextRole(.control)
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if let onMic = onMic {
                Button(action: onMic) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .appTextRole(.control)
                        .foregroundStyle(isRecording ? Color.accentProtein : AppPalette.brandText)
                        .frame(width: 36, height: 36)
                        .background(isRecording ? Color.accentProtein.opacity(0.15) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice search")
                .accessibilityValue(isRecording ? "Recording" : "Not recording")
            }
        }
        .padding(.horizontal, AppSpacing.row)
        .frame(minHeight: 54)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator.opacity(0.7), lineWidth: 0.5)
        }
    }
}
