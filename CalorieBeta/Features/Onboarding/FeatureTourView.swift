import SwiftUI

/// A short, optional introduction. The final page leads into the app without queuing another tour.
struct FeatureTourView: View {
    @Binding var isPresented: Bool
    @State private var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page {
        let title: String
        let subtitle: String
        let preview: FirstLookPreviewKind
        let takeaway: String
        let icon: String
    }

    private let pages = [
        Page(title: "Meet Maia", subtitle: "Snap, scan or describe a meal. Review the estimate, adjust the portion and get on with your day.",
             preview: .food, takeaway: "You always review AI estimates before saving.", icon: "checkmark.shield"),
        Page(title: "Make every set count", subtitle: "Your program, previous sets and next workout stay together. Less searching. More training.",
             preview: .training, takeaway: "Start with a ready-made program or build your own.", icon: "dumbbell"),
        Page(title: "Life happens. Your plan adapts.", subtitle: "Missed a workout or short on time? Rescue my week helps you adjust what comes next while keeping your progress.",
             preview: .adapt, takeaway: "Preview your changes. Apply them when you're ready. Undo if plans change again.", icon: "arrow.uturn.backward")
    ]

    init(isPresented: Binding<Bool>, initialSelection: Int = 0) {
        _isPresented = isPresented
        _selection = State(initialValue: min(max(initialSelection, 0), 2))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("First look").appTextRole(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Skip tour") { isPresented = false }
                    .buttonStyle(OnboardingTextButtonStyle(fillsWidth: false))
                    .accessibilityIdentifier("feature_tour_skip")
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.compact)

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(index <= selection ? AppPalette.brand : AppPalette.control).frame(height: 4)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .accessibilityLabel("Tour progress")
            .accessibilityValue("Step \(selection + 1) of \(pages.count)")

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    OnboardingHeadline(eyebrow: "Step \(selection + 1) of \(pages.count)",
                                       title: pages[selection].title, subtitle: pages[selection].subtitle)
                    FirstLookPreview(kind: pages[selection].preview)
                    Label(pages[selection].takeaway, systemImage: pages[selection].icon)
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
            .id(selection)
            .scrollIndicators(.hidden)
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingActionDock {
                Button {
                    if selection == pages.count - 1 { isPresented = false } else { withAnimation(reduceMotion ? nil : AppMotion.standard) { selection += 1 } }
                } label: {
                    Label(selection == pages.count - 1 ? "Open MyFitPlate" : "Continue", systemImage: "arrow.right")
                }
                .buttonStyle(AppActionButtonStyle(.primary))
                .accessibilityIdentifier("feature_tour_next")
                if selection > 0 {
                    Button("Back") { withAnimation(reduceMotion ? nil : AppMotion.standard) { selection -= 1 } }
                        .buttonStyle(OnboardingTextButtonStyle())
                        .accessibilityIdentifier("feature_tour_back")
                }
            }
        }
        .background(AppPalette.canvas.ignoresSafeArea())
    }
}
