import AppKit

/// Lets the user drag a rectangle over the screen. Every screen gets a dimmed
/// overlay; Esc or a right click cancels.
@MainActor
final class RegionSelector {
    /// Only used on the main actor; NSScreen just isn't marked Sendable.
    struct Selection: @unchecked Sendable {
        /// AppKit global coordinates.
        let rect: CGRect
        let screen: NSScreen
    }

    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<Selection?, Never>?

    func select() async -> Selection? {
        finish(nil) // a selection already running is cancelled
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            // Key events (Esc) need Waldo active; the controller gives focus back later.
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            for screen in NSScreen.screens {
                let window = OverlayWindow(screen: screen) { [weak self] rect in
                    self?.finish(rect.map { Selection(rect: $0, screen: screen) })
                }
                window.orderFrontRegardless()
                if screen.frame.contains(mouse) { window.makeKey() }
                windows.append(window)
            }
            NSCursor.crosshair.push()
        }
    }

    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        continuation.resume(returning: selection)
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        setFrame(screen.frame, display: false)
        contentView = OverlayView(onFinish: { [weak self] localRect in
            guard let self, let localRect else { return onFinish(nil) }
            onFinish(localRect.offsetBy(dx: self.frame.minX, dy: self.frame.minY))
        })
    }

    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    private let onFinish: (CGRect?) -> Void
    private var start: NSPoint?
    private var current: NSPoint?

    /// Smaller drags are taken as stray clicks.
    private static let minimumSide: CGFloat = 8

    init(onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y)).integral
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        current = NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= Self.minimumSide, selection.height >= Self.minimumSide else {
            start = nil
            current = nil
            needsDisplay = true
            return
        }
        onFinish(selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        guard let selection else {
            drawHint()
            return
        }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()
        drawSize(of: selection)
    }

    private func drawHint() {
        let text = "Drag over what you want explained  ·  Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - 120, width: size.width + 28, height: size.height + 14)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 7), withAttributes: attributes)
    }

    private func drawSize(of selection: CGRect) {
        let text = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var origin = NSPoint(x: selection.minX, y: selection.minY - size.height - 10)
        if origin.y < bounds.minY + 4 { origin.y = selection.minY + 6 }
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }
}
