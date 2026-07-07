import SwiftUI
import MyFitPlateCore

/// The tour overlay: dims the screen, punches a bright hole around the current target,
/// and floats an explanation card next to it. Driven by a resolved target rect (from the
/// `SpotlightBoundsKey` anchor) so the highlight and the copy always line up with what's
/// actually on screen — a tap anywhere advances.
struct SpotlightTourOverlay: View {
    let targetRect: CGRect?
    let containerSize: CGSize
    let content: (title: String, text: String)
    let currentIndex: Int
    let total: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let holePadding: CGFloat = 12
    private let gap: CGFloat = 18

    /// Put the card below the target when the target sits in the top half, otherwise above —
    /// so the copy is next to what it describes and never covers it.
    private var placeBelow: Bool {
        guard let targetRect else { return true }
        return targetRect.midY < containerSize.height * 0.5
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimWithHole
                .contentShape(Rectangle())
                .onTapGesture(perform: onNext)

            tooltipLayer
            skipButton
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    private var dimWithHole: some View {
        Rectangle()
            .fill(Color.black.opacity(0.72))
            .reverseMask {
                if let targetRect {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .frame(width: targetRect.width + holePadding, height: targetRect.height + holePadding)
                        .position(x: targetRect.midX, y: targetRect.midY)
                }
            }
    }

    @ViewBuilder
    private var tooltipLayer: some View {
        if let targetRect {
            VStack(spacing: 0) {
                if placeBelow {
                    Color.clear.frame(height: min(targetRect.maxY + gap, containerSize.height - 120))
                    tooltipCard
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    tooltipCard
                    Color.clear.frame(height: max(0, containerSize.height - targetRect.minY + gap))
                }
            }
        } else {
            VStack {
                Spacer()
                tooltipCard
                Spacer()
            }
        }
    }

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.title)
                .font(.title3.bold())
                .foregroundColor(.primary)

            Text(content.text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("\(currentIndex + 1) of \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Spacer()

                Button(currentIndex == total - 1 ? "Done" : "Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : .white,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, 20)
    }

    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip tour", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 54)
        .padding(.trailing, 20)
    }
}

private extension View {
    /// Masks self everywhere EXCEPT where `mask` draws — i.e. punches a hole.
    @ViewBuilder
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            Rectangle()
                .overlay(mask().blendMode(.destinationOut))
                .compositingGroup()
        )
    }
}
