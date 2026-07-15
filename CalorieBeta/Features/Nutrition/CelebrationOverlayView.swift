import Combine
import SwiftUI

public enum CelebrationType: Equatable {
    case proteinGoal
    case ayceWin
    case routePR
    case workoutPR

    var title: String {
        switch self {
        case .proteinGoal: "Protein Goal Reached"
        case .ayceWin: "Buffet Beaten"
        case .routePR: "New Route Record"
        case .workoutPR: "New Workout Record"
        }
    }

    var subtitle: String {
        switch self {
        case .proteinGoal:
            "You reached today's protein target. Keep your next meal aligned with recovery and appetite."
        case .ayceWin:
            "Your estimated menu value passed the price you paid."
        case .routePR:
            "You completed this route faster than your previous best."
        case .workoutPR:
            "This session moved beyond your previous best performance."
        }
    }

    var icon: String {
        switch self {
        case .proteinGoal: "bolt.heart.fill"
        case .ayceWin: "trophy.fill"
        case .routePR: "timer"
        case .workoutPR: "trophy.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .proteinGoal: AppPalette.achievement
        case .ayceWin: AppPalette.achievement
        case .routePR: AppPalette.effort
        case .workoutPR: AppPalette.brand
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var rotation: Double
    var xSpeed: CGFloat
    var ySpeed: CGFloat
    var rotationSpeed: Double
}

public struct CelebrationOverlayView: View {
    let type: CelebrationType
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var particles: [ConfettiParticle] = []
    @State private var cardScale: CGFloat = 0.96
    @State private var cardOpacity = 0.0
    @State private var timerSubscription: AnyCancellable?

    private let particleColors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink, .teal
    ]

    public init(type: CelebrationType, onDismiss: @escaping () -> Void) {
        self.type = type
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: dismissWithAnimation)

            if !reduceMotion {
                confettiLayer
            }

            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    celebrationCard
                        .padding(.vertical, AppSpacing.section)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                celebrationCard
            }
        }
        .onAppear(perform: appear)
        .onDisappear {
            timerSubscription?.cancel()
            timerSubscription = nil
        }
    }

    private var celebrationCard: some View {
        VStack(spacing: AppSpacing.section) {
            Image(systemName: type.icon)
                .appFont(size: 32, weight: .bold)
                .foregroundStyle(type.accentColor)
                .frame(width: 72, height: 72)
                .background(
                    type.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AppRadius.surface)
                )
                .accessibilityHidden(true)

            VStack(spacing: AppSpacing.compact) {
                Text(type.title)
                    .appTextRole(.screenTitle)
                    .foregroundStyle(AppPalette.text)
                    .multilineTextAlignment(.center)
                Text(type.subtitle)
                    .appTextRole(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: dismissWithAnimation) {
                Text("Continue")
            }
            .buttonStyle(AppActionButtonStyle(.primary))
            .accessibilityIdentifier("celebration_continue_button")
        }
        .padding(AppSpacing.section)
        .frame(maxWidth: 380)
        .appSurface(.emphasized, padding: 0, radius: AppRadius.hero)
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("celebration_overlay")
    }

    private var confettiLayer: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(particle.color.opacity(0.85))
                        .frame(width: particle.size, height: particle.size * 1.35)
                        .position(x: particle.x, y: particle.y)
                        .rotationEffect(.degrees(particle.rotation))
                }
            }
            .onAppear {
                setupParticles(in: geometry.size)
                startTimer(in: geometry.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func appear() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? .linear(duration: 0.1) : AppMotion.standard) {
            cardScale = 1
            cardOpacity = 1
        }
    }

    private func setupParticles(in size: CGSize) {
        particles = (0..<28).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: 0...max(size.width, 300)),
                y: CGFloat.random(in: -160...(-20)),
                size: CGFloat.random(in: 6...10),
                color: particleColors.randomElement() ?? .orange,
                rotation: Double.random(in: 0...360),
                xSpeed: CGFloat.random(in: -1.2...1.2),
                ySpeed: CGFloat.random(in: 3...7),
                rotationSpeed: Double.random(in: -6...6)
            )
        }
    }

    private func startTimer(in size: CGSize) {
        timerSubscription = Timer.publish(every: 0.025, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                for index in particles.indices {
                    particles[index].x += particles[index].xSpeed
                    particles[index].y += particles[index].ySpeed
                    particles[index].rotation += particles[index].rotationSpeed

                    if particles[index].y > size.height + 40 {
                        particles[index].y = -20
                        particles[index].x = CGFloat.random(in: 0...max(size.width, 300))
                    }
                }
            }
    }

    private func dismissWithAnimation() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .linear(duration: 0.1) : AppMotion.visibility) {
            cardScale = 0.98
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.1 : 0.18)) {
            onDismiss()
        }
    }
}

public extension View {
    func celebrationOverlay(
        type: CelebrationType?,
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue, let celebrationType = type {
                CelebrationOverlayView(type: celebrationType) {
                    isPresented.wrappedValue = false
                    onDismiss?()
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
    }
}

#if DEBUG
struct CelebrationOverlayDemoView: View {
    @State private var isPresented = true

    var body: some View {
        AppPalette.canvas
            .ignoresSafeArea()
            .celebrationOverlay(type: .ayceWin, isPresented: $isPresented)
    }
}
#endif
