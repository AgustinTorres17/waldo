import AppKit
import SwiftUI
import Testing
@testable import Waldo

/// TEMPORARY: renders every screen in every theme to PNGs (WALDO_SNAPSHOT=<dir>).
@MainActor
struct SnapshotTests {
    @Test func snapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["WALDO_SNAPSHOT"] else { return }
        let app = AppModel()
        let settings = app.settings
        let original = settings.appTheme
        defer { settings.appTheme = original }
        for theme in AppTheme.allCases {
            settings.appTheme = theme
            for dark in [false, true] {
                let suffix = "\(theme.rawValue)-\(dark ? "dark" : "light")"
                for page in SettingsView.Page.allCases {
                    render(SettingsView(model: app, settings: settings, permission: app.permission, models: app.models,
                                        initialPage: page),
                           dark: dark, wallpaper: theme == .glass, to: "\(dir)/settings-\(page.rawValue)-\(suffix).png")
                }
                render(OnboardingView(permission: app.permission, settings: settings, launchAtLogin: app.launchAtLogin) {},
                       dark: dark, wallpaper: theme == .glass, to: "\(dir)/onboarding-\(suffix).png")
                let states: [(String, PopupModel.State)] = [
                    ("compact", .compact),
                    ("streaming", .streaming("Hi Ana, I wanted to let you know that the report is")),
                    ("result", .result(text: "Hi Ana, I wanted to let you know that the report is ready. I sent it yesterday.",
                                       summary: "Corrected 2 mistakes.", changed: true,
                                       changes: TextDiff.segments(from: "Hi Ana, I wanted let you know that the report are ready. I have sent it yesterday.",
                                                                  to: "Hi Ana, I wanted to let you know that the report is ready. I sent it yesterday."))),
                    ("error", .error("Waldo couldn't process the text: the model isn't installed.")),
                ]
                for (name, state) in states {
                    let model = PopupModel()
                    model.state = state
                    render(PopupView(model: model, settings: settings).padding(30), dark: dark, wallpaper: true,
                           to: "\(dir)/popup-\(name)-\(suffix).png")
                }
            }
        }
    }

    private func render<V: View>(_ view: V, dark: Bool, wallpaper: Bool, to path: String) {
        // Vibrancy doesn't draw offscreen: a gradient stands in for the desktop behind.
        let root = ZStack {
            if wallpaper {
                LinearGradient(colors: dark ? [Color(red: 0.12, green: 0.14, blue: 0.3), Color(red: 0.25, green: 0.1, blue: 0.3)]
                                            : [Color(red: 0.8, green: 0.84, blue: 0.98), Color(red: 0.93, green: 0.85, blue: 0.96)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            view
        }
        .fixedSize()
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
