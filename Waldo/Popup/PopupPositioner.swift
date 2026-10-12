import AppKit

/// Converts AX rects to AppKit coordinates and places the popup next to them
/// (RESEARCH popup P4).
@MainActor
enum PopupPositioner {
    enum Placement {
        case below
        case above
    }

    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 4

    /// AX uses a top-left origin on the primary (menu bar) screen; AppKit uses bottom-left.
    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Selection bounds if plausible, else where the mouse selection ended,
    /// else the field's frame, else the current mouse location.
    static func anchor(for snapshot: SelectionSnapshot, mouseLocation: NSPoint?) -> CGRect {
        for candidate in snapshot.selectionRects {
            let rect = appKitRect(fromAX: candidate)
            if isPlausible(rect) { return rect }
        }
        if let mouseLocation {
            return lineRect(around: mouseLocation)
        }
        if let frame = snapshot.fieldFrame.map(appKitRect(fromAX:)), isPlausible(frame) {
            return frame
        }
        return lineRect(around: NSEvent.mouseLocation)
    }

    /// A mouse point sits mid-line; pad it to roughly one line so the popup doesn't cover the text.
    private static func lineRect(around point: NSPoint) -> CGRect {
        CGRect(x: point.x, y: point.y - 10, width: 0, height: 20)
    }

    /// Rejects empty rects, absurdly tall ones and rects that aren't on any screen
    /// (Electron without accessibility reports a bogus rect at the screen's edge).
    private static func isPlausible(_ rect: CGRect) -> Bool {
        guard rect.height > 0, rect.height < 2_000, rect.width >= 0 else { return false }
        return NSScreen.screens.contains { $0.frame.contains(rect.origin) }
    }

    static func screen(for anchor: CGRect) -> NSScreen? {
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Below the anchor if it fits, otherwise above.
    static func placement(for size: CGSize, anchor: CGRect) -> Placement {
        guard let visible = screen(for: anchor)?.visibleFrame else { return .below }
        return anchor.minY - gap - size.height >= visible.minY ? .below : .above
    }

    /// Keeps the edge nearest the selection fixed so the popup grows away from it.
    static func frame(for size: CGSize, anchor: CGRect, placement: Placement) -> CGRect {
        var origin = CGPoint(
            x: anchor.minX,
            y: placement == .below ? anchor.minY - gap - size.height : anchor.maxY + gap)
        if let visible = screen(for: anchor)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
            origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        }
        return CGRect(origin: origin, size: size)
    }
}
