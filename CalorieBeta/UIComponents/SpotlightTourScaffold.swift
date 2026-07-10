import SwiftUI
import MyFitPlateCore

/// One step of a screen's feature tour: a stable spotlight id plus the copy shown next to it.
struct SpotlightTourStep {
    let id: String
    let title: String
    let text: String
}

/// Reusable driver for a screen's first-visit feature tour. Wrap a screen's content in it and
/// mark the elements to highlight with `.featureSpotlight(isActive: isActive("<id>"))`; the
/// scaffold owns the shown-state, step machine, dimmed overlay, and the appear/replay triggers.
///
/// This is the same behavior HomeView/MealPlannerView implement inline, factored out so adding a
/// tour to another screen is just a list of steps rather than a copy of the whole state machine.
struct SpotlightTourScaffold<Content: View>: View {
    @EnvironmentObject private var spotlightManager: SpotlightManager

    let steps: [SpotlightTourStep]
    @ViewBuilder let content: (_ isActive: (String) -> Bool) -> Content

    @State private var activeIDs: [String] = []
    @State private var index: Int = 0
    @State private var running = false

    var body: some View {
        content(isActive)
            .overlayPreferenceValue(SpotlightBoundsKey.self) { anchor in
                GeometryReader { proxy in
                    if running, index < activeIDs.count,
                       let step = steps.first(where: { $0.id == activeIDs[index] }) {
                        SpotlightTourOverlay(
                            targetRect: anchor.map { proxy[$0] },
                            containerSize: proxy.size,
                            content: (title: step.title, text: step.text),
                            currentIndex: index,
                            total: activeIDs.count,
                            onNext: advance,
                            onSkip: skip
                        )
                        .animation(.easeInOut(duration: 0.25), value: index)
                    }
                }
            }
            .onAppear(perform: startIfNeeded)
            .onChange(of: spotlightManager.replayToken) { _, _ in startIfNeeded() }
    }

    private func isActive(_ id: String) -> Bool {
        running && index < activeIDs.count && activeIDs[index] == id
    }

    private func startIfNeeded() {
        let needed = steps.map(\.id).filter { !spotlightManager.isShown(id: $0) }
        guard !needed.isEmpty else { return }
        activeIDs = needed
        index = 0
        // Mark the first step shown immediately so it doesn't replay if the user leaves now.
        spotlightManager.markAsShown(id: needed[0])
        withAnimation { running = true }
    }

    private func advance() {
        if index < activeIDs.count {
            spotlightManager.markAsShown(id: activeIDs[index])
        }
        if index < activeIDs.count - 1 {
            withAnimation { index += 1 }
        } else {
            finish()
        }
    }

    private func skip() {
        activeIDs.forEach { spotlightManager.markAsShown(id: $0) }
        finish()
    }

    private func finish() {
        withAnimation { running = false }
    }
}
