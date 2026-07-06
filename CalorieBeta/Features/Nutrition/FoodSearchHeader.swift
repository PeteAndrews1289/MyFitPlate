import SwiftUI

struct FoodSearchHeader: View {
    @Binding var searchText: String
    let placeholder: String
    let onClear: () -> Void
    let onSubmit: () -> Void
    var onMic: (() -> Void)? = nil
    var isRecording: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))

            TextField(placeholder, text: $searchText)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit(onSubmit)

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(size: 18, weight: .semibold)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if let onMic = onMic {
                Button(action: onMic) {
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .appFont(size: 18, weight: .semibold)
                        .foregroundColor(isRecording ? .accentProtein : .brandPrimary)
                        .padding(6)
                        .background(isRecording ? Color.accentProtein.opacity(0.15) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voice search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
