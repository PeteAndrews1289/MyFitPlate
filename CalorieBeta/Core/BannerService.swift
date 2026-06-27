
import SwiftUI
import Combine

@MainActor
class BannerService: ObservableObject {
    @Published var currentBanner: BannerData?
    
    func showBanner(title: String, message: String, iconName: String = "checkmark.circle.fill", iconColor: Color = .green) {
        self.currentBanner = BannerData(title: title, message: message, iconName: iconName, iconColor: iconColor)
    }
}
