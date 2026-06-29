import Foundation

public protocol HapticsServiceProtocol {
    func playSuccess()
    func playSelection()
    func playImpact(style: HapticStyle)
}

public enum HapticStyle {
    case light, medium, heavy, soft, rigid
}

public class HapticsService: HapticsServiceProtocol {
    public static let shared = HapticsService()
    public init() {}
    public func playSuccess() {}
    public func playSelection() {}
    public func playImpact(style: HapticStyle) {}
}
