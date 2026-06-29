
import SwiftUI
import Combine

@MainActor
public class BannerService: ObservableObject {
    @Published public var currentBanner: BannerData?
    
    public init() {}
    
    public func showBanner(title: String, message: String, iconName: String = "checkmark.circle.fill", iconColor: Color = .green) {
        self.currentBanner = BannerData(title: title, message: message, iconName: iconName, iconColor: iconColor)
    }
}
