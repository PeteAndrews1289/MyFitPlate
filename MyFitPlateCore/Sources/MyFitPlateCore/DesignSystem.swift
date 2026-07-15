import SwiftUI

public struct AppFont: ViewModifier {
    public var size: CGFloat
    public var weight: Font.Weight

    // Scales typography with the user's Dynamic Type setting so larger-text users aren't stuck with
    // fixed sizes. Relative to .body so it tracks the system text-size slider; clamped to a modest
    // range so the app's fixed-size tiles/cards don't overflow at the largest accessibility sizes.
    @ScaledMetric(relativeTo: .body) private var scaleReference: CGFloat = 100

    public func body(content: Content) -> some View {
        let factor = min(max(scaleReference / 100, 0.95), 1.35)
        return content.font(.system(size: size * factor, weight: weight, design: .rounded))
    }
}

public extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.modifier(AppFont(size: size, weight: weight))
    }
}

public struct AppTextFieldStyle: TextFieldStyle {
    public let iconName: String?
    
    public init(iconName: String? = nil) {
        self.iconName = iconName
    }
    
    public func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 12) {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            configuration
        }
        .padding()
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .stroke(AppPalette.separator, lineWidth: 1)
        }
    }
}

public struct AnimatedCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.96 : 1.0)
            .animation(
                reduceMotion ? nil : .interpolatingSpring(stiffness: 300, damping: 20),
                value: configuration.isPressed
            )
    }
}

/// Reusable, friendly empty state — icon in a tinted circle, title, message, and an optional CTA.
/// Use for "nothing here yet" moments, especially first-run, so screens guide rather than dead-end.
public struct GuidanceEmptyState: View {
    public let icon: String
    public let title: String
    public let message: String
    
    public init(icon: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    public var actionTitle: String? = nil
    public var action: (() -> Void)? = nil

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.brandForeground)
                .frame(width: 58, height: 58)
                .background(Color.brandPrimary.opacity(0.10), in: Circle())

            VStack(spacing: 5) {
                Text(title)
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .appFont(size: 14, weight: .bold)
                    .foregroundColor(AppPalette.onBrand)
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

public struct SkeletonModifier: ViewModifier {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.68 : (pulse ? 0.4 : 0.85))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

public extension View {
    /// Gentle pulse for skeleton placeholders while content loads.
    func skeletonPulse() -> some View { modifier(SkeletonModifier()) }
}

/// Neutral placeholder block for building skeleton screens that mirror the real layout.
public struct SkeletonBlock: View {
    public var width: CGFloat? = nil
    public var height: CGFloat = 14
    public var cornerRadius: CGFloat = 7

    public init(width: CGFloat? = nil, height: CGFloat = 14, cornerRadius: CGFloat = 7) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.3))
            .frame(width: width, height: height)
    }
}

public struct ShimmerEffect: ViewModifier {
    @State private var isInitialState = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    public func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.72)
        } else {
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
}

public extension View {
    @ViewBuilder
    func shimmering(active: Bool = true) -> some View {
        if active {
            self.modifier(ShimmerEffect())
        } else {
            self
        }
    }
}
