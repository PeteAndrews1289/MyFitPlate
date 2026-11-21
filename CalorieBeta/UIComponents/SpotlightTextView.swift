import SwiftUI

/// Uses the same accessible card for guidance without a specific highlighted target.
struct SpotlightTextView: View {
    let content: (title: String, text: String)
    let currentIndex: Int
    let total: Int
    let onNext: () -> Void

    var body: some View {
        GeometryReader { proxy in
            SpotlightTourOverlay(targetRect: nil, containerSize: proxy.size, content: content,
                                 currentIndex: currentIndex, total: total, onNext: onNext, onSkip: onNext)
        }
    }
}
