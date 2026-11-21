import SwiftUI
import MyFitPlateCore

/// Keeps the explanation inside the visible screen, even when the highlighted content is
/// offscreen or Dynamic Type needs a scrolling card. Only explicit controls advance the tour.
struct SpotlightTourOverlay: View {
    let targetRect: CGRect?
    let containerSize: CGSize
    let content: (title: String, text: String)
    let currentIndex: Int
    let total: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    var onBack: (() -> Void)?

    @State private var cardHeight: CGFloat = 240
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let margin: CGFloat = 16

    private var visibleTarget: CGRect? {
        guard let targetRect, targetRect.width > 0, targetRect.height > 0 else { return nil }
        let visible = targetRect.intersection(CGRect(origin: .zero, size: containerSize))
        return visible.isNull || visible.height < 24 || visible.width < 24 ? nil : visible
    }

    private var cardY: CGFloat {
        let height = min(cardHeight, max(0, containerSize.height - margin * 2))
        let half = height / 2
        guard let target = visibleTarget else { return containerSize.height / 2 }
        if target.maxY + margin + height <= containerSize.height - margin {
            return target.maxY + margin + half
        }
        if target.minY - margin - height >= margin {
            return target.minY - margin - half
        }
        return max(margin + half, containerSize.height - margin - half)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.64))
                .mask {
                    Rectangle().overlay {
                        if let target = visibleTarget {
                            RoundedRectangle(cornerRadius: AppRadius.surface)
                                .frame(width: target.width + 8, height: target.height + 8)
                                .position(x: target.midX, y: target.midY)
                                .blendMode(.destinationOut)
                        }
                    }.compositingGroup()
                }
                .contentShape(Rectangle())
                .onTapGesture { }
                .accessibilityHidden(true)

            tooltipCard
                .frame(width: max(0, containerSize.width - AppSpacing.screenHorizontal * 2))
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SpotlightCardHeightKey.self, value: proxy.size.height)
                    }
                }
                .frame(maxHeight: max(120, containerSize.height - margin * 2))
                .position(x: containerSize.width / 2, y: cardY)
        }
        .onPreferenceChange(SpotlightCardHeightKey.self) { if $0 > 0 { cardHeight = $0 } }
        .task(id: currentIndex) { isTitleFocused = true }
        .accessibilityAction(.escape, onSkip)
        .transition(.opacity)
        .animation(reduceMotion ? nil : AppMotion.standard, value: currentIndex)
    }

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack {
                Text("Step \(currentIndex + 1) of \(total)")
                    .appTextRole(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Skip tour", action: onSkip)
                    .appTextRole(.secondary).foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("spotlight_skip")
            }
            ViewThatFits(in: .vertical) {
                explanation.fixedSize(horizontal: false, vertical: true)
                ScrollView { explanation }.scrollBounceBehavior(.basedOnSize)
            }
            HStack(spacing: AppSpacing.row) {
                if currentIndex > 0, let onBack {
                    Button("Back", action: onBack)
                        .buttonStyle(AppActionButtonStyle(.ghost))
                        .accessibilityIdentifier("spotlight_back")
                }
                Button(currentIndex == total - 1 ? "Got it" : "Next", action: onNext)
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .accessibilityIdentifier("spotlight_next")
            }
        }
        .padding(AppSpacing.group)
        .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: AppRadius.hero).stroke(AppPalette.separator, lineWidth: 1) }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            Text(content.title).appTextRole(.sectionTitle).foregroundStyle(AppPalette.text)
                .accessibilityAddTraits(.isHeader).accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("spotlight_title")
            Text(content.text).appTextRole(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpotlightCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
