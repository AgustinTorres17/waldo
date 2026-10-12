import AppKit
import SwiftUI

/// Monochrome, Notion-like palette. Every token adapts to light and dark mode.
enum Theme {
    static let background = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x191919))
    static let sidebar = dynamic(light: rgb(0xF7F7F5), dark: rgb(0x202020))
    static let text = dynamic(light: rgb(0x37352F), dark: white(0.81))
    static let secondaryText = dynamic(light: ink(0.65), dark: white(0.46))
    static let tertiaryText = dynamic(light: ink(0.45), dark: white(0.28))
    static let divider = dynamic(light: ink(0.09), dark: white(0.094))
    static let border = dynamic(light: ink(0.16), dark: white(0.13))
    static let hover = dynamic(light: ink(0.06), dark: white(0.055))
    static let pressed = dynamic(light: ink(0.12), dark: white(0.1))
    /// Filled buttons and "on" switches: black in light mode, white in dark mode.
    static let solid = dynamic(light: rgb(0x191919), dark: rgb(0xEDEDED))
    static let onSolid = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x191919))
    static let danger = dynamic(light: NSColor(srgbRed: 0.88, green: 0.24, blue: 0.24, alpha: 1),
                                dark: NSColor(srgbRed: 1, green: 0.45, blue: 0.42, alpha: 1))

    /// The only color: what a correction added and removed.
    static let insertedBackground = dynamic(light: NSColor(srgbRed: 0.16, green: 0.62, blue: 0.36, alpha: 0.16),
                                            dark: NSColor(srgbRed: 0.3, green: 0.8, blue: 0.5, alpha: 0.2))
    static let removedText = dynamic(light: NSColor(srgbRed: 0.75, green: 0.25, blue: 0.22, alpha: 0.85),
                                     dark: NSColor(srgbRed: 1, green: 0.5, blue: 0.45, alpha: 0.8))

    static let radius: CGFloat = 6

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    /// Notion's warm ink (#37352F) at an opacity.
    private static func ink(_ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 55 / 255, green: 53 / 255, blue: 47 / 255, alpha: alpha)
    }

    private static func white(_ alpha: CGFloat) -> NSColor {
        NSColor(white: 1, alpha: alpha)
    }
}

// MARK: Buttons

struct MonoButtonStyle: ButtonStyle {
    enum Kind {
        /// Filled black (white in dark mode).
        case primary
        /// Outlined.
        case secondary
        /// Text only, gray background on hover.
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

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: kind == .primary ? .medium : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay {
                    if kind == .secondary || kind == .destructive {
                        RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.onSolid
            case .destructive: Theme.danger
            case .secondary, .ghost: Theme.text
            }
        }

        private var background: Color {
            let active = isEnabled && (isHovered || configuration.isPressed)
            switch kind {
            case .primary:
                return Theme.solid.opacity(configuration.isPressed ? 0.75 : active ? 0.87 : 1)
            case .secondary, .ghost, .destructive:
                return configuration.isPressed ? Theme.pressed : active ? Theme.hover : .clear
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
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
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

/// A small black-and-white switch.
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
                Capsule()
                    .fill(configuration.isOn ? Theme.solid : Theme.border)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Theme.onSolid : Color.white)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
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

/// A dropdown that shows the current value and a chevron, like Notion's.
/// SwiftUI's `Menu` ignores custom labels on macOS, so this opens an `NSMenu` itself.
struct MonoMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    @State private var isHovered = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6) {
                Text(title(selection))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isHovered ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
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

// MARK: Settings layout

/// A settings page: big title, then sections.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A group of rows under a small heading and a hairline.
struct SettingsSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.bottom, 8)
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
            content
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
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
