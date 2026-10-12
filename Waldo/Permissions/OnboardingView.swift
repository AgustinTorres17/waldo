import SwiftUI

/// Explains why Waldo needs Accessibility access and sends the user to the right pane.
struct OnboardingView: View {
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var settings: SettingsStore
    @ObservedObject var launchAtLogin: LaunchAtLogin
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                Text("Welcome to Waldo")
                    .font(Theme.current == .editorial ? Theme.display(28, weight: .regular) : Theme.display(24, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Correct, translate and rephrase what you write, in any app.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 44)
            .padding(.bottom, 24)

            SettingsSection(title: "Waldo needs Accessibility access") {
                feature(symbol: "text.bubble.fill", tint: Theme.rgb(0x0A84FF),
                        title: "The popup",
                        detail: "Appears when you select text in another app. Waldo reads the selection and where it is on screen.")
                SettingsDivider()
                feature(symbol: "command", tint: Theme.rgb(0xFF375F),
                        title: "The hotkeys",
                        detail: "⌥⌘T, ⌥⌘R and the others press ⌘A, ⌘C and ⌘V for you.")
                SettingsDivider()
                feature(symbol: "lock.fill", tint: Theme.rgb(0x30D158),
                        title: "Private by design",
                        detail: "The model runs on this Mac. Your text never leaves it.")
            }

            SettingsSection {
                SettingsRow(title: "Open Waldo at login", detail: "It lives in the menu bar.") {
                    Toggle(isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) })) { EmptyView() }
                        .toggleStyle(.mono)
                }
            }
            .padding(.top, 14)

            status
                .padding(.top, 18)

            HStack {
                if !permission.isGranted {
                    Button("Later", action: close)
                        .buttonStyle(.monoGhost)
                }
                Spacer()
                if permission.isGranted {
                    Button("Get Started", action: close)
                        .buttonStyle(.monoPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") { permission.request() }
                        .buttonStyle(.monoPrimary)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 26)
        .frame(width: 500)
        .surface(.window)
        .tint(Theme.accent)
        .id(settings.appTheme)
    }

    @ViewBuilder private var status: some View {
        if permission.isGranted {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                Text("Accessibility access is on. You're all set.")
                    .foregroundStyle(Theme.text)
            }
            .font(.system(size: 12.5, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Click Open System Settings, then turn on Waldo in Privacy & Security › Accessibility. This window updates by itself.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func feature(symbol: String, tint: NSColor, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, color: tint, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                SettingsCaption(detail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}
