import SwiftUI

/// Phosphor Icons v2.1.0, https://github.com/phosphor-icons/swift.
/// The asset catalog contains only the glyphs used in MyFitPlate.
public enum PlateIcon: String, View {
    case search = "magnifying-glass-bold"
    case plus = "plus-bold"
    case check = "check-bold"
    case adjustments = "sliders-horizontal-bold"
    case scales

    public var body: some View {
        Image(rawValue, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}
