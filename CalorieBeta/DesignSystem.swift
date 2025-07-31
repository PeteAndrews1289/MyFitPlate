import SwiftUI


struct AppFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: .rounded, relativeTo: .body))
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
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
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
