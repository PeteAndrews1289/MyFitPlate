import SwiftUI

public extension Color {
    static var brandPrimary: Color {
        Color("BrandPrimary", bundle: .main)
    }
    /// High-contrast brand color for text, symbols, and outlines. Keep `brandPrimary`
    /// for filled actions, progress, and decorative emphasis.
    static var brandForeground: Color {
        Color("AccentPositiveText", bundle: .main)
    }
    static var accentPositive: Color {
        Color("AccentPositive", bundle: .main)
    }
    static var accentPositiveText: Color {
        Color("AccentPositiveText", bundle: .main)
    }
    static var accentEffort: Color {
        Color("AccentProtein", bundle: .main)
    }
    static var accentRecovery: Color {
        Color("AccentWater", bundle: .main)
    }
    static var accentCaution: Color {
        Color("AccentSignal", bundle: .main)
    }
    static var accentAchievement: Color {
        Color("AccentCarbs", bundle: .main)
    }
    static var accentEnergy: Color {
        Color("AccentEnergy", bundle: .main)
    }
    static var accentFat: Color {
        Color("AccentFats", bundle: .main)
    }
    static var backgroundPrimary: Color {
        Color("BackgroundPrimary", bundle: .main)
    }
    static var textPrimary: Color {
        Color("TextPrimary", bundle: .main)
    }
}
