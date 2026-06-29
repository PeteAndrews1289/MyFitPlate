import SwiftUI

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

public class HapticManager {
    public static let instance = HapticManager()
    private init() {}
    
#if os(iOS)
    public func feedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle){
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    public func notification(_ type: UINotificationFeedbackGenerator.FeedbackType){
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
#elseif os(watchOS)
    public enum FeedbackStyle {
        case light, medium, heavy
    }
    public enum NotificationType {
        case success, error, warning
    }
    
    // Polyfill for watchOS
    public func feedback(_ style: FeedbackStyle){
        let hapticType: WKHapticType
        switch style {
        case .light: hapticType = .click
        case .medium: hapticType = .success
        case .heavy: hapticType = .directionUp
        }
        WKInterfaceDevice.current().play(hapticType)
    }
    
    public func notification(_ type: NotificationType){
        let hapticType: WKHapticType
        switch type {
        case .success: hapticType = .success
        case .error: hapticType = .failure
        case .warning: hapticType = .retry
        }
        WKInterfaceDevice.current().play(hapticType)
    }
#else
    public enum FeedbackStyle {
        case light, medium, heavy
    }
    public enum NotificationType {
        case success, error, warning
    }

    public func feedback(_ style: FeedbackStyle) {}

    public func notification(_ type: NotificationType) {}
#endif
}
