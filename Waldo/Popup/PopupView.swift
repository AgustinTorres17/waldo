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
    var onAsk: () -> Void = {}
    var onReplace: (String) -> Void = { _ in }
    var onCopy: (String) -> Void = { _ in }
    var onClose: () -> Void = {}
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @ObservedObject var settings: SettingsStore

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.popupRadius, style: .continuous) }

    var body: some View {
        content
            .surface(.popup, cornerRadius: Theme.popupRadius)
            .overlay(shape.strokeBorder(Theme.border))
            .overlay {
                // Glass catches light along its top edge.
                if Theme.isGlass {
                    shape.inset(by: 1)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)],
                                                     startPoint: .top, endPoint: .center))
                }
            }
            .clipShape(shape)
            .fixedSize()
            .tint(Theme.accent)
            // Theme colors resolve when drawn: a new theme rebuilds the popup.
            .id(settings.appTheme)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .compact:
            HStack(spacing: 2) {
                MonoMenuPicker(selection: languageBinding, options: TargetLanguage.allCases, style: .chip,
                               icon: "globe") { $0.displayName }
                    .help(settings.hasRule(for: model.appBundleID) ? "Language for this app" : "Default language")
                if !settings.customModes.isEmpty {
                    MonoMenuPicker(selection: modeBinding, options: [nil] + settings.customModes.map(\.id),
                                   style: .chip, icon: "theatermasks") { id in
                        settings.customModes.first { $0.id == id }?.name ?? "No mode"
                    }
                    .help(settings.hasRule(for: model.appBundleID) ? "Mode for this app" : "Default mode")
                }
                Rectangle().fill(Theme.divider).frame(width: 1, height: 16)
                    .padding(.horizontal, 4)
                actionButton("Translate / Correct", icon: "character.bubble.fill") { model.onProcess(.automatic) }
                actionButton("Rephrase", icon: "wand.and.stars") { model.onProcess(.rephrase) }
                actionButton("Ask", icon: "bubble.left.and.text.bubble.right") { model.onAsk() }
                    .help("Ask Waldo about the selected text")
                closeButton
            }
            .padding(5)
        case .streaming(let text):
            card(text: AttributedString(text), copyText: text, canReplace: false, isStreaming: true) {
                PulsingDot()
                Text("Writing…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
            }
        case .result(let text, let summary, let changed, let changes):
            let shown = settings.showChanges ? changes.map(Self.highlighted) ?? AttributedString(text) : AttributedString(text)
            card(text: shown, copyText: text, canReplace: changed, isStreaming: false) {
                Image(systemName: changed ? "sparkles" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentFill)
                Text(summary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
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
            messageRow(message, icon: "exclamationmark", tint: Theme.danger)
        case .note(let message):
            messageRow(message, icon: "checkmark", tint: Theme.success)
        }
    }

    private func messageRow(_ message: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.14), in: Circle())
                .padding(.top, 1)
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
        .padding(.vertical, 8)
        .padding(.trailing, 7)
    }

    /// The result layout, also used while it's being written so the panel doesn't
    /// jump when it finishes. Copy and Replace wait for the validated text.
    private func card<Header: View>(text: AttributedString, copyText: String, canReplace: Bool, isStreaming: Bool,
                                    @ViewBuilder header: () -> Header) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                header()
                closeButton
            }
            .padding(.leading, 16)
            .padding([.top, .trailing], 7)

            ResultText(text: text, isStreaming: isStreaming)
                .padding(.top, 2)

            if model.isHotkeyRun {
                Spacer().frame(height: 12)
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    Button { model.onCopy(copyText) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.monoSecondary)
                    .disabled(isStreaming)
                    Button { model.onReplace(copyText) } label: {
                        Label("Replace", systemImage: "arrow.turn.down.left")
                    }
                    .buttonStyle(.monoPrimary)
                    .disabled(isStreaming || !canReplace || model.isReplacing)
                }
                .labelStyle(CompactLabelStyle())
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Theme.popupFooter)
                .overlay(alignment: .top) { SettingsDivider() }
                .padding(.top, 12)
            }
        }
        .frame(width: 380)
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

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.accentFill)
                Text(title)
                    .fontWeight(.medium)
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

/// Icon and title, closer together than the default.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10.5, weight: .semibold))
            configuration.title
        }
    }
}

/// A small accent dot that breathes while Waldo writes.
private struct PulsingDot: View {
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(Theme.accentFill)
            .frame(width: 7, height: 7)
            .opacity(isDim ? 0.35 : 1)
            .scaleEffect(isDim ? 0.8 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { isDim = true }
            }
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
                    .font(Theme.resultFont)
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
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
        caret.foregroundColor = visible ? Theme.accent : .clear
        return caret
    }
}

private struct EndOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
