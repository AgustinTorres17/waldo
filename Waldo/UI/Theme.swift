import AppKit
import SwiftUI

/// Design tokens for the theme the user picked (see AppTheme). Every color adapts
/// to light and dark mode. Colors are resolved when drawn, so views that change
/// theme are rebuilt with `.id(settings.appTheme)`.
enum Theme {
    /// Set by SettingsStore before any view draws.
    nonisolated(unsafe) static var current = AppTheme.glass

    static var isGlass: Bool { current == .glass }

    // MARK: Text

    static let text = token {
        switch $0 {
        case .glass: (rgb(0x1D1D1F), white(0.92))
        case .mono: (rgb(0x111111), rgb(0xEDEDED))
        case .editorial: (rgb(0x2B2722), rgb(0xE9E3D7))
        }
    }
    static let secondaryText = token {
        switch $0 {
        case .glass: (black(0.56), white(0.6))
        case .mono: (black(0.55), white(0.55))
        case .editorial: (ink(0.64), paper(0.6))
        }
    }
    static let tertiaryText = token {
        switch $0 {
        case .glass: (black(0.36), white(0.38))
        case .mono: (black(0.36), white(0.36))
        case .editorial: (ink(0.42), paper(0.38))
        }
    }

    // MARK: Lines and states

    static let divider = token {
        switch $0 {
        case .glass: (black(0.07), white(0.08))
        case .mono: (black(0.08), white(0.09))
        case .editorial: (ink(0.1), paper(0.1))
        }
    }
    static let border = token {
        switch $0 {
        case .glass: (black(0.09), white(0.11))
        case .mono: (black(0.12), white(0.13))
        case .editorial: (ink(0.16), paper(0.14))
        }
    }
    static let hover = token {
        switch $0 {
        case .glass: (black(0.05), white(0.07))
        case .mono: (black(0.05), white(0.06))
        case .editorial: (ink(0.06), paper(0.07))
        }
    }
    static let pressed = token {
        switch $0 {
        case .glass: (black(0.09), white(0.12))
        case .mono: (black(0.1), white(0.11))
        case .editorial: (ink(0.11), paper(0.12))
        }
    }
    /// The selected sidebar item.
    static let selection = token {
        switch $0 {
        case .glass: (black(0.075), white(0.1))
        case .mono: (black(0.07), white(0.09))
        case .editorial: (ink(0.08), paper(0.09))
        }
    }

    // MARK: Surfaces

    /// The settings content area. Glass lays it over vibrancy, so it's see-through.
    static let background = token {
        switch $0 {
        case .glass: (white(0.55), rgba(0x1C1C1F, 0.45))
        case .mono: (rgb(0xFFFFFF), rgb(0x141414))
        case .editorial: (rgb(0xFBF8F2), rgb(0x1C1A17))
        }
    }
    static let sidebar = token {
        switch $0 {
        case .glass: (white(0.12), rgba(0x000000, 0.08))
        case .mono: (rgb(0xF6F6F6), rgb(0x1A1A1A))
        case .editorial: (rgb(0xF2EDE3), rgb(0x221F1B))
        }
    }
    /// Grouped settings rows.
    static let card = token {
        switch $0 {
        case .glass: (white(0.75), white(0.055))
        case .mono: (rgb(0xFFFFFF), rgb(0x1B1B1B))
        case .editorial: (rgb(0xFFFDF9), rgb(0x24211D))
        }
    }
    /// Text fields and editors.
    static let field = token {
        switch $0 {
        case .glass: (white(0.9), rgba(0x000000, 0.22))
        case .mono: (rgb(0xFFFFFF), rgb(0x101010))
        case .editorial: (rgb(0xFFFEFB), rgb(0x1A1815))
        }
    }
    /// Outlined controls: pickers and secondary buttons.
    static let control = token {
        switch $0 {
        case .glass: (white(0.85), white(0.08))
        case .mono: (rgb(0xFFFFFF), white(0.05))
        case .editorial: (rgb(0xFFFDF8), paper(0.05))
        }
    }
    static let popupBackground = token {
        switch $0 {
        case .glass: (white(0.5), rgba(0x1C1C20, 0.4))
        case .mono: (rgb(0xFFFFFF), rgb(0x191919))
        case .editorial: (rgb(0xFCF9F3), rgb(0x201D1A))
        }
    }
    static let popupFooter = token {
        switch $0 {
        case .glass: (black(0.025), white(0.03))
        case .mono: (rgb(0xFAFAFA), rgb(0x1E1E1E))
        case .editorial: (ink(0.03), paper(0.03))
        }
    }

    // MARK: Accent

    /// Primary buttons, switches, selection marks. Mono's is black (white in dark mode).
    static let accent = token {
        switch $0 {
        case .glass: (rgb(0x5E5CE6), rgb(0x8E8CFF))
        case .mono: (rgb(0x111111), rgb(0xEDEDED))
        case .editorial: (rgb(0x284B7A), rgb(0x93B3DD))
        }
    }
    /// Where Glass's gradient ends.
    private static let accentEnd = token {
        switch $0 {
        case .glass: (rgb(0x9B4FE8), rgb(0xB88BFF))
        case .mono: (rgb(0x111111), rgb(0xEDEDED))
        case .editorial: (rgb(0x284B7A), rgb(0x93B3DD))
        }
    }
    static let onAccent = token {
        switch $0 {
        case .glass: (white(1), white(1))
        case .mono: (rgb(0xFFFFFF), rgb(0x111111))
        case .editorial: (rgb(0xFFFFFF), rgb(0x1C1A17))
        }
    }
    /// A tint for badges and highlights.
    static let accentSoft = token {
        switch $0 {
        case .glass: (rgba(0x5E5CE6, 0.12), rgba(0x8E8CFF, 0.2))
        case .mono: (black(0.06), white(0.08))
        case .editorial: (rgba(0x284B7A, 0.1), rgba(0x93B3DD, 0.16))
        }
    }

    static var accentFill: AnyShapeStyle {
        isGlass
            ? AnyShapeStyle(LinearGradient(colors: [accent, accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(accent)
    }

    // Kept for older call sites: "solid" is the accent.
    static var solid: Color { accent }
    static var onSolid: Color { onAccent }

    static let success = token { _ in
        (NSColor(srgbRed: 0.16, green: 0.6, blue: 0.36, alpha: 1), NSColor(srgbRed: 0.35, green: 0.82, blue: 0.53, alpha: 1))
    }
    static let danger = token { _ in
        (NSColor(srgbRed: 0.86, green: 0.24, blue: 0.24, alpha: 1), NSColor(srgbRed: 1, green: 0.45, blue: 0.42, alpha: 1))
    }

    /// What a correction added and removed.
    static let insertedBackground = token { _ in
        (NSColor(srgbRed: 0.16, green: 0.62, blue: 0.36, alpha: 0.16), NSColor(srgbRed: 0.3, green: 0.8, blue: 0.5, alpha: 0.2))
    }
    static let removedText = token { _ in
        (NSColor(srgbRed: 0.75, green: 0.25, blue: 0.22, alpha: 0.85), NSColor(srgbRed: 1, green: 0.5, blue: 0.45, alpha: 0.8))
    }

    // MARK: Shape and type

    /// Buttons, pickers, fields.
    static var radius: CGFloat {
        switch current {
        case .glass: 7
        case .mono: 6
        case .editorial: 5
        }
    }

    static var cardRadius: CGFloat {
        switch current {
        case .glass: 12
        case .mono: 10
        case .editorial: 8
        }
    }

    static var popupRadius: CGFloat {
        switch current {
        case .glass: 14
        case .mono: 12
        case .editorial: 10
        }
    }

    /// Titles. Editorial sets them in New York.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        current == .editorial ? .system(size: size, weight: weight, design: .serif) : .system(size: size, weight: weight)
    }

    /// Text Waldo wrote, in the popup.
    static var resultFont: Font {
        current == .editorial ? .system(size: 14, design: .serif) : .system(size: 13.5)
    }

    // MARK: Helpers

    private static func token(_ values: @escaping @Sendable (AppTheme) -> (NSColor, NSColor)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (light, dark) = values(current)
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static func rgb(_ hex: UInt32) -> NSColor { rgba(hex, 1) }

    static func rgba(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    private static func black(_ alpha: CGFloat) -> NSColor { NSColor(white: 0, alpha: alpha) }
    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
    /// Editorial's warm ink, for light mode.
    private static func ink(_ alpha: CGFloat) -> NSColor { rgba(0x2B2722, alpha) }
    /// Editorial's paper white, for dark mode.
    private static func paper(_ alpha: CGFloat) -> NSColor { rgba(0xE9E3D7, alpha) }
}

// MARK: Surfaces

/// macOS vibrancy: the desktop and windows behind show through, blurred.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var cornerRadius: CGFloat = 0
    /// Panels that never become key would otherwise look inactive (flat gray).
    var alwaysActive = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        update(view)
    }

    private func update(_ view: NSVisualEffectView) {
        view.material = material
        view.state = alwaysActive ? .active : .followsWindowActiveState
        // SwiftUI clipping doesn't reach the blur; a mask image does.
        view.maskImage = cornerRadius > 0 ? Self.mask(radius: cornerRadius) : nil
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

enum Surface {
    case window, sidebar, popup

    var material: NSVisualEffectView.Material {
        switch self {
        case .window: .underWindowBackground
        case .sidebar: .sidebar
        case .popup: .popover
        }
    }

    var tint: Color {
        switch self {
        case .window: Theme.background
        case .sidebar: Theme.sidebar
        case .popup: Theme.popupBackground
        }
    }
}

extension View {
    /// A themed background: vibrancy plus a tint for Glass, a solid color otherwise.
    func surface(_ surface: Surface, cornerRadius: CGFloat = 0) -> some View {
        background {
            ZStack {
                if Theme.isGlass {
                    VisualEffectBackground(material: surface.material, cornerRadius: cornerRadius,
                                           alwaysActive: surface == .popup)
                }
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(surface.tint)
            }
        }
    }

    /// A text field or editor's box.
    func fieldBox() -> some View {
        background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
    }
}

// MARK: Buttons

struct MonoButtonStyle: ButtonStyle {
    enum Kind {
        /// Filled with the accent.
        case primary
        /// Outlined.
        case secondary
        /// Text only, a tint on hover.
        case ghost
        case destructive
    }

    var kind = Kind.secondary

    func makeBody(configuration: Configuration) -> some View {
        MonoButton(configuration: configuration, kind: kind)
    }

    private struct MonoButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: kind == .primary ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .ghost ? 9 : 12)
                .frame(height: 27)
                .background { background }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }

        private var active: Bool { isEnabled && (isHovered || configuration.isPressed) }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onAccent
            case .destructive: Theme.danger
            case .secondary, .ghost: Theme.text
            }
        }

        @ViewBuilder private var background: some View {
            switch kind {
            case .primary:
                shape.fill(Theme.accentFill)
                    .overlay {
                        // A lit top edge, like a physical key.
                        if Theme.isGlass {
                            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)],
                                                              startPoint: .top, endPoint: .center))
                        }
                    }
                    .brightness(configuration.isPressed ? -0.06 : active ? 0.05 : 0)
                    .shadow(color: Theme.isGlass ? Theme.accent.opacity(0.3) : .clear, radius: 3, y: 1)
            case .secondary, .destructive:
                shape.fill(Theme.control)
                    .overlay(shape.fill(configuration.isPressed ? Theme.pressed : active ? Theme.hover : .clear))
                    .overlay(shape.strokeBorder(Theme.border))
                    .shadow(color: Theme.isGlass ? .black.opacity(0.05) : .clear, radius: 1, y: 0.5)
            case .ghost:
                shape.fill(configuration.isPressed ? Theme.pressed : active ? Theme.hover : .clear)
            }
        }
    }
}

/// A square, borderless icon button (close, remove…).
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, size: size)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Theme.text : Theme.tertiaryText)
                .frame(width: size, height: size)
                .background(configuration.isPressed ? Theme.pressed : isHovered ? Theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.radius - 1, style: .continuous))
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == MonoButtonStyle {
    static var monoPrimary: MonoButtonStyle { MonoButtonStyle(kind: .primary) }
    static var monoSecondary: MonoButtonStyle { MonoButtonStyle(kind: .secondary) }
    static var monoGhost: MonoButtonStyle { MonoButtonStyle(kind: .ghost) }
    static var monoDestructive: MonoButtonStyle { MonoButtonStyle(kind: .destructive) }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

// MARK: Switch

/// A small switch in the theme's accent.
struct MonoSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        MonoSwitch(configuration: configuration)
    }

    private struct MonoSwitch: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: 10) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(Theme.accentFill).opacity(configuration.isOn ? 1 : 0)
                    Circle()
                        .fill(configuration.isOn ? Theme.onAccent : Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                        .padding(2)
                }
                .frame(width: 32, height: 19)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            }
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}

extension ToggleStyle where Self == MonoSwitchStyle {
    static var mono: MonoSwitchStyle { MonoSwitchStyle() }
}

// MARK: Menu picker

/// A dropdown that shows the current value and a chevron.
/// SwiftUI's `Menu` ignores custom labels on macOS, so this opens an `NSMenu` itself.
struct MonoMenuPicker<Value: Hashable>: View {
    enum Style {
        /// Outlined, for settings.
        case bordered
        /// Borderless until hovered, for the popup's toolbar.
        case chip
    }

    @Binding var selection: Value
    let options: [Value]
    var style = Style.bordered
    var icon: String?
    let title: (Value) -> String

    @State private var isHovered = false
    @State private var anchor = MenuAnchor()

    init(selection: Binding<Value>, options: [Value], style: Style = .bordered, icon: String? = nil,
         title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.style = style
        self.icon = icon
        self.title = title
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(title(selection))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, style == .chip ? 8 : 10)
            .frame(height: style == .chip ? 26 : 27)
            .background {
                switch style {
                case .bordered:
                    shape.fill(Theme.control)
                        .overlay(shape.fill(isHovered ? Theme.hover : .clear))
                        .overlay(shape.strokeBorder(Theme.border))
                        .shadow(color: Theme.isGlass ? .black.opacity(0.05) : .clear, radius: 1, y: 0.5)
                case .chip:
                    shape.fill(isHovered ? Theme.hover : .clear)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .background(MenuAnchorView(anchor: anchor))
    }

    private func showMenu() {
        let menu = NSMenu()
        let targets = options.map { option in
            MenuTarget { selection = option }
        }
        for (option, target) in zip(options, targets) {
            let item = NSMenuItem(title: title(option), action: #selector(MenuTarget.run), keyEquivalent: "")
            item.target = target
            item.state = option == selection ? .on : .off
            menu.addItem(item)
        }
        // Anchored to the picker's own view: the popup panel is never the key window.
        guard let view = anchor.view, let window = view.window else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        // Menus sit at .popUpMenu; a higher window (the popup panel) would cover them.
        let level = window.level
        if level >= .popUpMenu {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        }
        defer { window.level = level }
        let point = NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4)
        // Blocks until the menu closes, which keeps `targets` alive.
        menu.popUp(positioning: nil, at: point, in: view)
        withExtendedLifetime(targets) {}
    }
}

private final class MenuAnchor {
    weak var view: NSView?
}

/// An AppKit view behind the picker, to position the menu in whatever window hosts it.
private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

private final class MenuTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func run() {
        action()
    }
}

// MARK: Small pieces

/// A small rounded label ("Recommended", "Default").
struct Badge: View {
    let text: String
    var prominent = false

    init(_ text: String, prominent: Bool = false) {
        self.text = text
        self.prominent = prominent
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(prominent ? Theme.accent : Theme.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(prominent ? Theme.accentSoft : Theme.hover, in: Capsule())
    }
}

/// A rounded square with a white symbol, like System Settings' sidebar. Glass only:
/// Mono draws it in gray, Editorial shows the bare symbol.
struct IconTile: View {
    let symbol: String
    let color: NSColor
    var size: CGFloat = 20

    var body: some View {
        switch Theme.current {
        case .glass, .mono:
            let fill = Theme.current == .glass ? Color(nsColor: color) : Color(nsColor: Theme.rgb(0x5A5A5E))
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [fill.opacity(0.85), fill], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                )
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.52, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .frame(width: size, height: size)
        case .editorial:
            Image(systemName: symbol)
                .font(.system(size: size * 0.62))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: size, height: size)
        }
    }
}

/// A keyboard shortcut drawn as a key.
struct KeyCap: View {
    let keys: String

    init(_ keys: String) {
        self.keys = keys
    }

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(Theme.isGlass ? 0.08 : 0), radius: 0, y: 1)
    }
}

/// A hairline between rows.
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}

// MARK: Settings layout

/// A settings page: a large title, an optional subtitle, then sections.
struct SettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Theme.current == .editorial ? Theme.display(27, weight: .regular) : Theme.display(22, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if let subtitle {
                        SettingsCaption(subtitle)
                    }
                }
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Grouped rows on a card, under a small heading.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(Theme.current == .editorial ? Theme.display(14, weight: .semibold) : .system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.current == .editorial ? Theme.text : Theme.secondaryText)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.divider))
            .shadow(color: Theme.isGlass ? .black.opacity(0.04) : .clear, radius: 2, y: 1)
            if let footer {
                SettingsCaption(footer)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Title and description on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                if let detail {
                    SettingsCaption(detail)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.vertical, 11)
    }
}

/// Gray explanatory text.
struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryText)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
