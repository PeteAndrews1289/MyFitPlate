import SwiftUI

/// The restrained visual language introduced with Living Day. New and migrated screens use these
/// roles instead of choosing raw sizes, radii, colors, and animation curves independently.
public enum AppTextRole: CaseIterable, Sendable {
    case display
    case screenTitle
    case sectionTitle
    case control
    case body
    case secondary
    case caption
    case metric

    public var pointSize: CGFloat {
        switch self {
        case .display: 34
        case .screenTitle, .metric: 28
        case .sectionTitle: 21
        case .control: 17
        case .body: 15
        case .secondary: 13
        case .caption: 11
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .display, .screenTitle, .metric: .bold
        case .sectionTitle: .bold
        case .control: .semibold
        case .body: .regular
        case .secondary: .regular
        case .caption: .semibold
        }
    }

    fileprivate var relativeTextStyle: Font.TextStyle {
        switch self {
        case .display: .largeTitle
        case .screenTitle, .metric: .title
        case .sectionTitle: .title3
        case .control: .body
        case .body: .subheadline
        case .secondary: .footnote
        case .caption: .caption2
        }
    }
}

public struct AppTextRoleModifier: ViewModifier {
    public let role: AppTextRole
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(role: AppTextRole) {
        self.role = role
    }

    public func body(content: Content) -> some View {
        content.font(
            .system(
                role.relativeTextStyle,
                design: dynamicTypeSize.isAccessibilitySize ? .default : .rounded,
                weight: role.weight
            )
        )
    }
}

public extension View {
    func appTextRole(_ role: AppTextRole) -> some View {
        modifier(AppTextRoleModifier(role: role))
    }
}

public enum AppSpacing {
    public static let compact: CGFloat = 8
    public static let row: CGFloat = 12
    public static let group: CGFloat = 16
    public static let section: CGFloat = 24
    public static let screenHorizontal: CGFloat = 20
}

public enum AppRadius {
    public static let control: CGFloat = 12
    public static let surface: CGFloat = 16
    public static let hero: CGFloat = 20
}

public enum AppMotion {
    public static var standard: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    public static var visibility: Animation {
        .easeOut(duration: 0.18)
    }
}

public enum AppPalette {
    public static var canvas: Color { Color("BackgroundPrimary", bundle: .main) }
    public static var surface: Color { Color("BackgroundSecondary", bundle: .main) }
    public static var control: Color { Color("ControlBackground", bundle: .main) }
    public static var brand: Color { Color("BrandPrimary", bundle: .main) }
    public static var text: Color { Color("TextPrimary", bundle: .main) }
    public static var separator: Color { Color.primary.opacity(0.10) }
}

public enum AppSurfaceRole: Sendable {
    case quiet
    case emphasized
}

public struct AppSurfaceModifier: ViewModifier {
    public let role: AppSurfaceRole
    public let padding: CGFloat
    public let radius: CGFloat

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        role: AppSurfaceRole,
        padding: CGFloat = AppSpacing.group,
        radius: CGFloat = AppRadius.surface
    ) {
        self.role = role
        self.padding = padding
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
    }

    private var backgroundColor: Color {
        switch role {
        case .quiet: AppPalette.control
        case .emphasized: AppPalette.surface
        }
    }

    private var borderColor: Color {
        switch role {
        case .quiet:
            AppPalette.separator.opacity(colorSchemeContrast == .increased ? 1 : 0.55)
        case .emphasized:
            AppPalette.separator.opacity(colorSchemeContrast == .increased ? 1 : 0.9)
        }
    }

    private var borderWidth: CGFloat {
        colorSchemeContrast == .increased || role == .emphasized ? 1 : 0.5
    }
}

public extension View {
    func appSurface(
        _ role: AppSurfaceRole = .quiet,
        padding: CGFloat = AppSpacing.group,
        radius: CGFloat = AppRadius.surface
    ) -> some View {
        modifier(AppSurfaceModifier(role: role, padding: padding, radius: radius))
    }
}

public enum AppActionRole: Sendable {
    case primary
    case secondary
    case destructive
    case ghost
}

public struct AppActionButtonStyle: ButtonStyle {
    public let role: AppActionRole
    public let fillsWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    public init(_ role: AppActionRole = .primary, fillsWidth: Bool = true) {
        self.role = role
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appTextRole(.control)
            .padding(.horizontal, AppSpacing.group)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: 50)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(AppMotion.standard, value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch role {
        case .primary, .destructive: .white
        case .secondary: AppPalette.text
        case .ghost: AppPalette.brand
        }
    }

    private var backgroundColor: Color {
        switch role {
        case .primary: AppPalette.brand
        case .secondary: AppPalette.control
        case .destructive: .red
        case .ghost: .clear
        }
    }

    private var borderColor: Color {
        switch role {
        case .primary, .destructive: .clear
        case .secondary: AppPalette.separator
        case .ghost: AppPalette.brand.opacity(0.45)
        }
    }

    private var borderWidth: CGFloat {
        switch role {
        case .primary, .destructive: 0
        case .secondary, .ghost: 1
        }
    }
}

public enum AppIconButtonRole: Sendable {
    case neutral
    case brand
    case plain
}

public struct AppIconButtonStyle: ButtonStyle {
    public let role: AppIconButtonRole

    public init(_ role: AppIconButtonRole = .neutral) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 17, weight: .semibold)
            .frame(width: 44, height: 44)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(AppMotion.standard, value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        role == .brand ? AppPalette.brand : AppPalette.text
    }

    private var backgroundColor: Color {
        switch role {
        case .neutral: AppPalette.control
        case .brand: AppPalette.brand.opacity(0.10)
        case .plain: .clear
        }
    }
}

public struct AppScreenHeader<Trailing: View>: View {
    public let eyebrow: String?
    public let title: String
    public let subtitle: String?
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    textBlock
                    trailing
                }
            } else {
                HStack(alignment: .top, spacing: AppSpacing.group) {
                    textBlock
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow, !dynamicTypeSize.isAccessibilitySize {
                Text(eyebrow.uppercased())
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }

            Text(title)
                .appTextRole(.screenTitle)
                .foregroundStyle(AppPalette.text)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? AppSpacing.compact : 0)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 2 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? AppSpacing.compact : 0)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 2 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

public extension AppScreenHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

public struct AppSectionHeader<Trailing: View>: View {
    public let title: String
    public let subtitle: String?
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    textBlock
                    trailing
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.row) {
                    textBlock
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)

            if let subtitle {
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public extension AppSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

public struct AppMetricItem: Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let accent: Color

    public init(id: String? = nil, label: String, value: String, accent: Color = AppPalette.brand) {
        self.id = id ?? label
        self.label = label
        self.value = value
        self.accent = accent
    }
}

/// A flat metric treatment for summaries. Standard text uses aligned columns; accessibility text
/// switches to full-width rows so values never have to shrink to remain legible.
public struct AppMetricStrip: View {
    public let items: [AppMetricItem]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(items: [AppMetricItem]) {
        self.items = items
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            metricLabel(item)
                            metricValue(item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppSpacing.compact)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.label), \(item.value)")

                        if index < items.count - 1 {
                            Divider()
                        }
                    }
                }
            } else if items.count > 3 {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: AppSpacing.group
                ) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            metricValue(item)
                            metricLabel(item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.label), \(item.value)")
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            metricValue(item)
                            metricLabel(item)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.label), \(item.value)")

                        if index < items.count - 1 {
                            Divider()
                                .padding(.horizontal, AppSpacing.row)
                        }
                    }
                }
            }
        }
    }

    private func metricLabel(_ item: AppMetricItem) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(item.accent)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(item.label)
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricValue(_ item: AppMetricItem) -> some View {
        Text(item.value)
            .appTextRole(.control)
            .foregroundStyle(AppPalette.text)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct AppListRow<Trailing: View>: View {
    public let icon: String?
    public let iconColor: Color
    public let title: String
    public let subtitle: String?
    public let hidesTextFromAccessibility: Bool
    private let trailing: Trailing

    public init(
        icon: String? = nil,
        iconColor: Color = AppPalette.text,
        title: String,
        subtitle: String? = nil,
        hidesTextFromAccessibility: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.hidesTextFromAccessibility = hidesTextFromAccessibility
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: AppSpacing.row) {
            if let icon {
                Image(systemName: icon)
                    .appFont(size: 18, weight: .semibold)
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .accessibilityHidden(hidesTextFromAccessibility)

                if let subtitle {
                    Text(subtitle)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(hidesTextFromAccessibility)
                }
            }

            Spacer(minLength: AppSpacing.compact)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .contentShape(Rectangle())
    }
}

public extension AppListRow where Trailing == EmptyView {
    init(
        icon: String? = nil,
        iconColor: Color = AppPalette.text,
        title: String,
        subtitle: String? = nil,
        hidesTextFromAccessibility: Bool = false
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            hidesTextFromAccessibility: hidesTextFromAccessibility
        ) { EmptyView() }
    }
}

public struct AppSheetScaffold<Content: View>: View {
    public let title: String
    public let subtitle: String?
    public let dismiss: () -> Void
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        title: String,
        subtitle: String? = nil,
        dismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.dismiss = dismiss
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                sheetHeader
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var sheetHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                HStack {
                    Spacer(minLength: 0)
                    closeButton
                }
                headerText
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.compact)
            .padding(.bottom, AppSpacing.group)
        } else {
            ZStack(alignment: .topTrailing) {
                headerText
                    .padding(.trailing, 44 + AppSpacing.group)
                closeButton
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.compact)
            .padding(.bottom, AppSpacing.group)
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .appTextRole(.sectionTitle)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .appTextRole(.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(AppPalette.text)
                .frame(width: 44, height: 44)
                .background(
                    AppPalette.control,
                    in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Close")
        .accessibilityIdentifier("app_sheet_close_button")
    }
}
