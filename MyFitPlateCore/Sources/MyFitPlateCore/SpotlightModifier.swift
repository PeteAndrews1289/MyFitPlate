import SwiftUI

/// Published by the currently-active spotlight target so the tour overlay can punch a
/// bright hole exactly there and anchor its tooltip next to it. Inactive targets
/// contribute nil; the reduce keeps whichever child is active.
public struct SpotlightBoundsKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil
    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

public struct SpotlightModifier: ViewModifier {
    public var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white, lineWidth: 3)
                                        .opacity(isActive ? 1 : 0)
                                        .animation(reduceMotion ? nil : AppMotion.standard, value: isActive)
                    .allowsHitTesting(false)
            )
            // Only the active target reports its frame, so the tour overlay knows where to
            // cut its spotlight hole and place the tooltip.
            .anchorPreference(key: SpotlightBoundsKey.self, value: .bounds) { isActive ? $0 : nil }
    }
}

public extension View {
    func featureSpotlight(isActive: Bool) -> some View {
        self.modifier(SpotlightModifier(isActive: isActive))
    }
}
