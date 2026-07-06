import SwiftUI
import Combine

public enum CelebrationType: Equatable {
    case proteinGoal
    case ayceWin
    case routePR
    case workoutPR
    
    var title: String {
        switch self {
        case .proteinGoal: return "Protein Goal Hit!"
        case .ayceWin: return "Buffet Beaten!"
        case .routePR: return "New Route PR!"
        case .workoutPR: return "New Workout PR!"
        }
    }
    
    var subtitle: String {
        switch self {
        case .proteinGoal: return "Anabolic muscle building unlocked for today. Keep fueling your recovery!"
        case .ayceWin: return "You consumed more actual menu protein value than the kitchen charged for this meal!"
        case .routePR: return "You crushed your previous ghost pace and set a new personal record on this loop!"
        case .workoutPR: return "You crushed your previous best and set a new personal record in today's workout!"
        }
    }
    
    var icon: String {
        switch self {
        case .proteinGoal: return "bolt.heart.fill"
        case .ayceWin: return "trophy.fill"
        case .routePR: return "timer"
        case .workoutPR: return "trophy.fill"
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .proteinGoal: return [Color.orange, Color.red]
        case .ayceWin: return [Color.yellow, Color.orange]
        case .routePR: return [Color.teal, Color.blue]
        case .workoutPR: return [Color.purple, Color.indigo]
        }
    }
}

struct ConfettiParticle: Identifiable {
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
    
    @State private var particles: [ConfettiParticle] = []
    @State private var badgeScale: CGFloat = 0.3
    @State private var badgeOpacity: Double = 0.0
    @State private var badgeRotation: Double = -15.0
    @State private var glowPulse: Bool = false
    @State private var timer: Publishers.Autoconnect<Timer.TimerPublisher>?
    @State private var timerSubscription: AnyCancellable?
    
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .teal]
    
    public init(type: CelebrationType, onDismiss: @escaping () -> Void) {
        self.type = type
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { dismissWithAnimation() }
            
            // Confetti Layer
            GeometryReader { geometry in
                ZStack {
                    ForEach(particles) { particle in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(particle.color)
                            .frame(width: particle.size, height: particle.size * 1.4)
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
            
            // Trophy / Medal Card
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: type.gradientColors.map { $0.opacity(glowPulse ? 0.6 : 0.3) } + [.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 110
                            )
                        )
                        .frame(width: 220, height: 220)
                        .scaleEffect(glowPulse ? 1.15 : 0.95)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowPulse)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: type.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: type.gradientColors.first?.opacity(0.5) ?? .clear, radius: 20, x: 0, y: 10)
                    
                    Image(systemName: type.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .rotation3DEffect(.degrees(badgeRotation), axis: (x: 0, y: 1, z: 0))
                
                VStack(spacing: 10) {
                    Text(type.title)
                        .appFont(size: 28, weight: .heavy)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    
                    Text(type.subtitle)
                        .appFont(size: 15, weight: .medium)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                Button(action: { dismissWithAnimation() }) {
                    Text("Awesome!")
                        .appFont(size: 17, weight: .bold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: type.gradientColors, startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: type.gradientColors.first?.opacity(0.4) ?? .clear, radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(colors: type.gradientColors.map { $0.opacity(0.8) }, startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                    )
            )
            .padding(.horizontal, 32)
            .scaleEffect(badgeScale)
            .opacity(badgeOpacity)
        }
        .onAppear {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.success)
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.2)) {
                badgeScale = 1.0
                badgeOpacity = 1.0
                badgeRotation = 0.0
            }
            glowPulse = true
        }
        .onDisappear {
            timerSubscription?.cancel()
            timerSubscription = nil
        }
    }
    
    private func setupParticles(in size: CGSize) {
        var newParticles: [ConfettiParticle] = []
        for _ in 0..<60 {
            let p = ConfettiParticle(
                x: CGFloat.random(in: 0...max(size.width, 300)),
                y: CGFloat.random(in: -200...(-20)),
                size: CGFloat.random(in: 8...14),
                color: colors.randomElement() ?? .orange,
                rotation: Double.random(in: 0...360),
                xSpeed: CGFloat.random(in: -2...2),
                ySpeed: CGFloat.random(in: 4...10),
                rotationSpeed: Double.random(in: -8...8)
            )
            newParticles.append(p)
        }
        particles = newParticles
    }
    
    private func startTimer(in size: CGSize) {
        let newTimer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()
        timer = newTimer
        timerSubscription = newTimer.sink { _ in
            for i in 0..<particles.count {
                particles[i].x += particles[i].xSpeed
                particles[i].y += particles[i].ySpeed
                particles[i].rotation += particles[i].rotationSpeed
                
                if particles[i].y > size.height + 50 {
                    particles[i].y = -20
                    particles[i].x = CGFloat.random(in: 0...max(size.width, 300))
                }
            }
        }
    }
    
    private func dismissWithAnimation() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
        
        withAnimation(.easeIn(duration: 0.25)) {
            badgeScale = 0.8
            badgeOpacity = 0.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
