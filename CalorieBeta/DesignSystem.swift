import SwiftUI

struct AppFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
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
            .background(Color.brandPrimary)
            .foregroundColor(Color.white)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
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
            .background(Color.backgroundPrimary)
            .foregroundColor(.brandPrimary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.brandPrimary, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
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
        .background(Color("ControlBackground"))
        .cornerRadius(16)
    }
}

struct CardViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func asCard() -> some View {
        self.modifier(CardViewModifier())
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
