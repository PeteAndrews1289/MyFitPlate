import MyFitPlateCore
import SwiftUI

/// Independent list actions with the touch target inside the button's actual label.
/// Applying an outer frame alone leaves borderless text buttons with a smaller hit area.
struct AppListButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .foregroundStyle(configuration.role == .destructive ? AppPalette.critical : AppPalette.brandText)
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
    }
}
