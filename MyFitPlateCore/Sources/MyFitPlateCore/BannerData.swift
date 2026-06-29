import SwiftUI

public struct BannerData: Equatable {
    public var title: String
    public var message: String
    public var iconName: String
    public var iconColor: Color
    
    public init(title: String, message: String, iconName: String = "checkmark.circle.fill", iconColor: Color = .green) {
        self.title = title
        self.message = message
        self.iconName = iconName
        self.iconColor = iconColor
    }
}
