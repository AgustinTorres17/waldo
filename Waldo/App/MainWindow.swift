import AppKit
import SwiftUI

/// Waldo's window: saved chats on the left, the chat on the right. Closing it
/// only hides it; the chats live in ChatLibrary.
final class MainWindow: NSWindow {}

/// What Waldo's window shows.
@MainActor
final class WindowRoute: ObservableObject {
    /// A Settings pane in place of the chats; nil shows the chats.
    @Published var settingsPane: SettingsPane?
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private unowned let app: AppModel
    private(set) var window: MainWindow?

    init(app: AppModel) {
        self.app = app
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let window = self.window ?? makeWindow()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> MainWindow {
        let view = MainView(app: app, library: app.library, settings: app.settings, route: app.route)
        let window = MainWindow(contentRect: CGRect(x: 0, y: 0, width: 1_000, height: 700),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "Waldo"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = CGSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("WaldoMainWindow")
        self.window = window
        return window
    }
}

struct MainView: View {
    let app: AppModel
    @ObservedObject var library: ChatLibrary
    @ObservedObject var settings: SettingsStore
    @ObservedObject var route: WindowRoute

    var body: some View {
        HStack(spacing: 0) {
            if let pane = route.settingsPane {
                SettingsSidebar(selection: Binding(get: { pane }, set: { route.settingsPane = $0 }),
                                onBack: { route.settingsPane = nil })
                Rectangle().fill(Theme.divider).frame(width: 1)
                SettingsPaneView(model: app, settings: settings, permission: app.permission, models: app.models, pane: pane)
                    .overlay(alignment: .top) { WindowDragArea().frame(height: 28) }
            } else {
                ChatSidebar(library: library, onNewChat: { app.startChat() }, onSettings: { app.openSettings(.general) })
                Rectangle().fill(Theme.divider).frame(width: 1)
                ChatScreen(library: library, settings: settings) { wholeScreen in
                    app.addCapture(wholeScreen: wholeScreen)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .ignoresSafeArea()
        .tint(Theme.accent)
        // Theme colors resolve when drawn: a new theme rebuilds the window.
        .id(settings.appTheme)
    }
}

/// Search, New chat, the chats grouped by date, Settings.
private struct ChatSidebar: View {
    @ObservedObject var library: ChatLibrary
    let onNewChat: () -> Void
    let onSettings: () -> Void

    @State private var renaming: UUID?
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                TextField("Search", text: $library.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .fieldBox()

            SidebarButton(title: "New chat", icon: "square.and.pencil", isSelected: library.selectedID == nil,
                          action: onNewChat)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(ChatGroup.groups(for: library.filteredChats), id: \.title) { group in
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 3)
                        ForEach(group.chats) { chat in
                            row(chat)
                        }
                    }
                    if library.filteredChats.isEmpty, !library.searchText.isEmpty {
                        Text("No chats match.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(8)
                    }
                }
            }

            SettingsDivider()
            SidebarButton(title: "Settings", icon: "gearshape", isSelected: false, action: onSettings)
        }
        .padding(.horizontal, 10)
        // Leaves room for the traffic lights in the transparent title bar.
        .padding(.top, 46)
        .padding(.bottom, 10)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .surface(.sidebar)
        // The strip with the traffic lights acts as the title bar.
        .overlay(alignment: .top) { WindowDragArea().frame(height: 40) }
    }

    @ViewBuilder
    private func row(_ chat: ChatConversation) -> some View {
        if renaming == chat.id {
            TextField("Title", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 8)
                .frame(height: 28)
                .fieldBox()
                .onSubmit {
                    library.rename(chat.id, to: newTitle)
                    renaming = nil
                }
                .onExitCommand { renaming = nil }
        } else {
            SidebarButton(title: chat.displayTitle, icon: nil, isSelected: library.selectedID == chat.id,
                          isBusy: library.runningID == chat.id) {
                library.select(chat.id)
            }
            .contextMenu {
                Button("Rename…") {
                    newTitle = chat.displayTitle
                    renaming = chat.id
                }
                Button("Delete", role: .destructive) { library.delete(chat.id) }
            }
        }
    }
}

private struct SidebarButton: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    var isBusy = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 16)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isSelected ? Theme.selection : isHovered ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.radius + 1, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Today, Yesterday, Previous 7 days, Older.
struct ChatGroup {
    let title: String
    let chats: [ChatConversation]

    static func groups(for chats: [ChatConversation], now: Date = .now, calendar: Calendar = .current) -> [ChatGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let week = calendar.date(byAdding: .day, value: -7, to: today)!
        let buckets: [(String, (Date) -> Bool)] = [
            ("Today", { $0 >= today }),
            ("Yesterday", { $0 >= yesterday && $0 < today }),
            ("Previous 7 days", { $0 >= week && $0 < yesterday }),
            ("Older", { $0 < week }),
        ]
        return buckets.compactMap { title, contains in
            let matching = chats.filter { contains($0.updatedAt) }
            return matching.isEmpty ? nil : ChatGroup(title: title, chats: matching)
        }
    }
}

/// A title bar stand-in for content drawn under the transparent title bar:
/// dragging moves the window, a double click does what System Settings says
/// (Desktop & Dock › "Double-click a window's title bar to").
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false } // dragging is done in mouseDown

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil) // "Maximize", "Fill", or never changed
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
