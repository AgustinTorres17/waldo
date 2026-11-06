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
                for pane in SettingsPane.allCases {
                    app.route.settingsPane = pane
                    render(MainView(app: app, library: app.library, settings: settings, route: app.route)
                        .frame(width: 1_000, height: 680),
                           dark: dark, wallpaper: false, to: "\(dir)/settings-\(pane.rawValue)-\(suffix).png")
                }
                app.route.settingsPane = nil
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
                let library = Self.sampleLibrary(app: app)
                library.select(library.chats.first?.id)
                render(MainView(app: app, library: library, settings: settings, route: app.route).frame(width: 1_000, height: 680),
                       dark: dark, wallpaper: false, to: "\(dir)/window-chat-\(suffix).png")
                library.select(nil)
                render(MainView(app: app, library: library, settings: settings, route: app.route).frame(width: 1_000, height: 680),
                       dark: dark, wallpaper: false, to: "\(dir)/window-new-\(suffix).png")
                library.startNewChat(openedFrom: nil, quote: "We should circle back on this once the dust settles, per se.")
                render(MainView(app: app, library: library, settings: settings, route: app.route).frame(width: 1_000, height: 680),
                       dark: dark, wallpaper: false, to: "\(dir)/window-quote-\(suffix).png")
            }
        }
    }

    /// Three saved chats (today, yesterday, last week) in a temporary folder.
    private static func sampleLibrary(app: AppModel) -> ChatLibrary {
        let store = ChatStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("waldo-snapshot-\(UUID().uuidString)"))
        var cursor = ChatConversation()
        cursor.title = "Precio del plan Pro de Cursor"
        cursor.turns = [ChatTurn(question: "cuanto sale hoy el plan pro de cursor?",
                                 answer: "Hoy, el plan Pro de Cursor cuesta **$20 al mes** [1][3].\n\nSi necesitás más, hay Pro+ ($60) y Ultra ($200) [1].",
                                 search: SearchStep(rawQuery: "Cursor Pro price October 2026", results: [
                                     SearchResult(title: "Cursor Pricing 2026: Pro vs Pro+ vs Ultra, Real Costs", url: URL(string: "https://vibecoding.app/blog/cursor-pricing")!, snippet: ""),
                                     SearchResult(title: "Cursor Pricing (2026): Plans, Seats & Team Costs", url: URL(string: "https://www.layer3labs.io/guides/cursor-pricing")!, snippet: ""),
                                     SearchResult(title: "Cursor · Pricing", url: URL(string: "https://cursor.com/pricing")!, snippet: ""),
                                 ])),
                         ChatTurn(question: "Tengo 3 cajas con 4 manzanas y me como 5, ¿cuántas quedan?",
                                  answer: "3 × 4 = 12.\n12 − 5 = 7.\n</think>\n\nQuedan **7 manzanas**.", thinks: true)]
        var swift = ChatConversation()
        swift.title = "Error de actor en Swift"
        swift.turns = [ChatTurn(question: "¿qué significa?", answer: "Es un error de compilación.", quote: "main actor-isolated property 'items'")]
        swift.updatedAt = .now.addingTimeInterval(-86_400)
        var zed = ChatConversation()
        zed.title = "Zed vs Cursor"
        zed.turns = [ChatTurn(question: "vale la pena zed?", answer: "Depende.")]
        zed.updatedAt = .now.addingTimeInterval(-4 * 86_400)
        [cursor, swift, zed].forEach(store.save)
        return ChatLibrary(app: app, store: store)
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
