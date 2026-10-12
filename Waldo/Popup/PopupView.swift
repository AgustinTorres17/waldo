import SwiftUI

@MainActor
final class PopupModel: ObservableObject {
    enum State: Equatable {
        case compact
        /// The result so far, unvalidated: shown, not copyable. Starts empty on click.
        case streaming(String)
        /// `changes` is nil when a diff wouldn't help (a translation, a full rewrite).
        case result(text: String, summary: String, changed: Bool, changes: [TextDiff.Segment]?)
        case error(String)
        /// A short outcome with nothing to replace ("Already correct").
        case note(String)
    }

    @Published var state = State.compact
    @Published var isReplacing = false
    /// The app the selection is in, which picks its mode.
    @Published var appBundleID: String?
    /// A hotkey run: the popup only shows progress, the hotkey replaces the text itself.
    @Published var isHotkeyRun = false

    var onProcess: (ProcessingMode) -> Void = { _ in }
    var onReplace: (String) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var onClose: () -> Void = {}
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        content
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .compact:
            HStack(spacing: 2) {
                MonoMenuPicker(selection: languageBinding, options: TargetLanguage.allCases) { $0.displayName }
                    .help(settings.hasRule(for: model.appBundleID) ? "Language for this app" : "Default language")
                if !settings.customModes.isEmpty {
                    MonoMenuPicker(selection: modeBinding,
                                   options: [nil] + settings.customModes.map(\.id)) { id in
                        settings.customModes.first { $0.id == id }?.name ?? "No mode"
                    }
                    .help(settings.hasRule(for: model.appBundleID) ? "Mode for this app" : "Default mode")
                    .padding(.leading, 2)
                }
                Spacer().frame(width: 2)
                actionButton("Translate / Correct", icon: "character.bubble", mode: .automatic)
                actionButton("Rephrase", icon: "wand.and.stars", mode: .rephrase)
                closeButton
            }
            .padding(4)
        case .streaming(let text):
            card(text: AttributedString(text), copyText: text, canReplace: false, isStreaming: true) {
                Text("Writing…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
        case .result(let text, let summary, let changed, let changes):
            let shown = settings.showChanges ? changes.map(Self.highlighted) ?? AttributedString(text) : AttributedString(text)
            card(text: shown, copyText: text, canReplace: changed, isStreaming: false) {
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if changes != nil {
                    Button { settings.showChanges.toggle() } label: {
                        Image(systemName: "plusminus")
                    }
                    .buttonStyle(.icon)
                    .opacity(settings.showChanges ? 1 : 0.5)
                    .help(settings.showChanges ? "Hide changes" : "Show changes")
                }
            }
        case .error(let message):
            messageRow(message, icon: "exclamationmark.circle")
        case .note(let message):
            messageRow(message, icon: "checkmark.circle")
        }
    }

    private func messageRow(_ message: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 3)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .lineSpacing(2)
                .frame(width: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            closeButton
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .padding(.trailing, 6)
    }

    /// The result layout, also used while it's being written so the panel doesn't
    /// jump when it finishes. Copy and Replace wait for the validated text.
    private func card<Header: View>(text: AttributedString, copyText: String, canReplace: Bool, isStreaming: Bool,
                                    @ViewBuilder header: () -> Header) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                header()
                Spacer(minLength: 8)
                closeButton
            }
            .padding(.leading, 14)
            .padding([.top, .trailing], 6)

            ResultText(text: text, isStreaming: isStreaming)

            if model.isHotkeyRun {
                Spacer().frame(height: 10)
            } else {
                Rectangle().fill(Theme.divider).frame(height: 1)
                    .padding(.top, 10)

                HStack(spacing: 6) {
                    Spacer()
                    Button("Copy") { model.onCopy(copyText) }
                        .buttonStyle(.monoGhost)
                        .disabled(isStreaming)
                    Button("Replace") { model.onReplace(copyText) }
                        .buttonStyle(.monoPrimary)
                        .disabled(isStreaming || !canReplace || model.isReplacing)
                }
                .padding(8)
            }
        }
        .frame(width: 360)
    }


    /// Added words on a tint, removed words struck through. A space only on screen
    /// keeps "was" and "were" from reading as one word; Copy and Replace use `text`.
    private static func highlighted(_ segments: [TextDiff.Segment]) -> AttributedString {
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .same: break
            case .inserted: part.backgroundColor = Theme.insertedBackground
            case .removed:
                part.foregroundColor = Theme.removedText
                part.strikethroughStyle = .single
                let next = segments.indices.contains(index + 1) ? segments[index + 1] : nil
                if next?.kind == .inserted, segment.text.last?.isWhitespace == false { part += AttributedString(" ") }
            }
            result += part
        }
        return result
    }

    private var languageBinding: Binding<TargetLanguage> {
        Binding(
            get: { settings.language(for: model.appBundleID) },
            set: { settings.setLanguage($0, for: model.appBundleID) }
        )
    }

    private var modeBinding: Binding<UUID?> {
        Binding(
            get: { settings.modeID(for: model.appBundleID) },
            set: { settings.setModeID($0, for: model.appBundleID) }
        )
    }

    private func actionButton(_ title: String, icon: String, mode: ProcessingMode) -> some View {
        Button { model.onProcess(mode) } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
                Text(title)
            }
        }
        .buttonStyle(.monoGhost)
    }

    private var closeButton: some View {
        Button(action: model.onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.icon)
        .help("Close (Esc)")
    }
}

/// The result text. While it's written it follows the end, unless the user
/// scrolls up to read; scrolling back to the end follows again.
private struct ResultText: View {
    let text: AttributedString
    let isStreaming: Bool

    @State private var followsText = true
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollMonitor: Any?

    private static let end = "end"
    private static let space = "resultText"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // A blinking caret marks where the text is being written; the
                    // finished result doesn't tick.
                    TimelineView(.periodic(from: .now, by: isStreaming ? 0.5 : 3_600)) { context in
                        let caretOn = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                        Text(isStreaming ? text + Self.caret(visible: caretOn) : text)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    Color.clear.frame(height: 1).id(Self.end)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: EndOffsetKey.self,
                                                   value: geometry.frame(in: .named(Self.space)).maxY)
                        })
                }
            }
            .coordinateSpace(name: Self.space)
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { viewportHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { viewportHeight = $0 }
            })
            // Growing text only pushes the end out of view, so this never resumes
            // following by itself: only the user reaching the end does.
            .onPreferenceChange(EndOffsetKey.self) { endY in
                if endY <= viewportHeight + 4 { followsText = true }
            }
            .onChange(of: text) { _ in
                if isStreaming, followsText { proxy.scrollTo(Self.end, anchor: .bottom) }
            }
        }
        .onAppear(perform: watchScrolling)
        .onDisappear(perform: stopWatchingScrolling)
    }

    /// Scrolling up in the popup stops following the text.
    private func watchScrolling() {
        guard isStreaming, scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.window is PopupPanel, event.scrollingDeltaY > 0 { followsText = false }
            return event
        }
    }

    private func stopWatchingScrolling() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private static func caret(visible: Bool) -> AttributedString {
        var caret = AttributedString("▍")
        caret.foregroundColor = visible ? Theme.secondaryText : .clear
        return caret
    }
}

private struct EndOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
