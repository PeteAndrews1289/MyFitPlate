import SwiftUI

struct SpotlightModifier: ViewModifier {
    var isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
                    .shadow(color: .white, radius: 8)
                    .opacity(isActive ? 1 : 0)
                    .scaleEffect(isActive ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 0.35), value: isActive)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func featureSpotlight(isActive: Bool) -> some View {
        self.modifier(SpotlightModifier(isActive: isActive))
    }
}
