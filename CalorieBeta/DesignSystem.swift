import SwiftUI

struct AppFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight

    // Scales typography with the user's Dynamic Type setting so larger-text users aren't stuck with
    // fixed sizes. Relative to .body so it tracks the system text-size slider; clamped to a modest
    // range so the app's fixed-size tiles/cards don't overflow at the largest accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var scaleReference: CGFloat = 100

    func body(content: Content) -> some View {
        let factor = min(max(scaleReference / 100, 0.95), 1.35)
        return content.font(.system(size: size * factor, weight: weight, design: .rounded))
    }
}

extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.modifier(AppFont(size: size, weight: weight))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 18, weight: .semibold)
            .padding()
            .frame(maxWidth: .infinity)
            .background(LinearGradient.brandGradient)
            .foregroundColor(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.brandPrimary.opacity(0.4), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    HapticManager.instance.feedback(.medium)
                }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 18, weight: .semibold)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.backgroundPrimary.opacity(0.5))
            .background(.ultraThinMaterial)
            .foregroundColor(.brandPrimary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(LinearGradient.brandGradient, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    HapticManager.instance.feedback(.light)
                }
            }
    }
}

struct AppTextFieldStyle: TextFieldStyle {
    let iconName: String?
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 12) {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 20)
            }
            configuration
        }
        .padding()
        .background(Color("ControlBackground").opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.15 : 0.6), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 15, x: 0, y: 8)
    }
}

struct AnimatedCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: configuration.isPressed)
    }
}

extension View {
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
    
    // Legacy support to easily transition
    func asCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}

/// Reusable, friendly empty state — icon in a tinted circle, title, message, and an optional CTA.
/// Use for "nothing here yet" moments, especially first-run, so screens guide rather than dead-end.
struct GuidanceEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 58, height: 58)
                .background(Color.brandPrimary.opacity(0.10), in: Circle())

            VStack(spacing: 5) {
                Text(title)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Color.brandPrimary, in: Capsule())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

struct SkeletonModifier: ViewModifier {
    @State private var pulse = false
    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.4 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    /// Gentle pulse for skeleton placeholders while content loads.
    func skeletonPulse() -> some View { modifier(SkeletonModifier()) }
}

/// Neutral placeholder block for building skeleton screens that mirror the real layout.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(UIColor.tertiarySystemFill))
            .frame(width: width, height: height)
    }
}

extension LinearGradient {
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color.brandPrimary, Color.teal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var isInitialState = true

    func body(content: Content) -> some View {
        content
            .mask(
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.4), .black, .black.opacity(0.4)]),
                    startPoint: (isInitialState ? .init(x: -0.3, y: -0.3) : .init(x: 1, y: 1)),
                    endPoint: (isInitialState ? .init(x: 0, y: 0) : .init(x: 1.3, y: 1.3))
                )
            )
            .animation(.linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false), value: isInitialState)
            .onAppear {
                isInitialState = false
            }
    }
}

extension View {
    @ViewBuilder
    func shimmering(active: Bool = true) -> some View {
        if active {
            self.modifier(ShimmerEffect())
        } else {
            self
        }
    }
}
