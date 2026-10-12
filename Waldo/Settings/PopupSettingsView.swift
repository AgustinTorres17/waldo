import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PopupSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPage(title: "Popup", subtitle: "The bar that appears when you select text.") {
            SettingsSection(title: "Behavior") {
                SettingsRow(title: "Show popup on selection",
                            detail: "Appears when you select text in an editable field.") {
                    Toggle(isOn: $settings.popupEnabled) { EmptyView() }.toggleStyle(.mono)
                }
                SettingsDivider()
                SettingsRow(title: "Keyboard selections",
                            detail: "Also show it after Shift+arrows or ⌘A.") {
                    Toggle(isOn: $settings.keyboardSelectionEnabled) { EmptyView() }.toggleStyle(.mono)
                }
                .disabled(!settings.popupEnabled)
            }

            SettingsSection(title: "Excluded apps",
                            footer: "The popup never appears in these apps. The hotkeys still work.") {
                VStack(spacing: 0) {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            AppRow(bundleID: bundleID)
                            Spacer()
                            Button {
                                settings.excludedBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.icon)
                            .help("Remove")
                        }
                        .padding(.vertical, 6)
                        SettingsDivider()
                    }
                    HStack {
                        Button(action: addApp) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                                Text("Add app")
                            }
                        }
                        .buttonStyle(.monoGhost)
                        .padding(.leading, -9)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .disabled(!settings.popupEnabled)

            let browsers = ChromiumBrowsers.installedBundleIDs
            SettingsSection(title: "Browsers",
                            footer: browsers.isEmpty
                                ? "Chrome, Brave and other Chromium browsers don't report selections unless Waldo turns on their full accessibility support. None is installed."
                                : "Chromium browsers only report selections when Waldo turns on their full accessibility support. This can make window moves and animations slower in that browser. The hotkeys work either way.") {
                if browsers.isEmpty {
                    Text("No Chromium browsers installed.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.vertical, 11)
                }
                ForEach(browsers, id: \.self) { bundleID in
                    HStack {
                        AppRow(bundleID: bundleID)
                        Spacer()
                        Toggle(isOn: browserBinding(bundleID)) { EmptyView() }.toggleStyle(.mono)
                    }
                    .padding(.vertical, 7)
                    if bundleID != browsers.last { SettingsDivider() }
                }
            }
            .disabled(!settings.popupEnabled)
        }
    }

    private func browserBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.accessibleBrowserBundleIDs.contains(bundleID) },
            set: { enabled in
                settings.accessibleBrowserBundleIDs.removeAll { $0 == bundleID }
                if enabled { settings.accessibleBrowserBundleIDs.append(bundleID) }
            }
        )
    }

    private func addApp() {
        let ids = AppRow.chooseApps()
        settings.excludedBundleIDs.append(contentsOf: ids.filter { !settings.excludedBundleIDs.contains($0) })
    }
}

/// An app's icon and name.
struct AppRow: View {
    let bundleID: String

    /// Asks for apps in /Applications and returns their bundle IDs.
    static func chooseApps() -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
        }
    }
}
