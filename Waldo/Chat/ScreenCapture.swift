import AppKit
import ScreenCaptureKit

/// Captures a region of the screen for Explain. Needs Screen Recording permission,
/// asked for the first time Explain is used (not during onboarding).
@MainActor
enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; later it only opens nothing. macOS
    /// usually applies a new grant after Waldo restarts.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// `rect` is in AppKit global coordinates and lies on `screen`. Waldo's own
    /// windows (the popup, an earlier explanation) are left out.
    @available(macOS 14.0, *)
    static func capture(_ rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        // Display-local points with a top-left origin.
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY,
                           width: rect.width, height: rect.height)
        configuration.sourceRect = local
        configuration.width = Int(local.width * screen.backingScaleFactor)
        configuration.height = Int(local.height * screen.backingScaleFactor)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? {
            "Couldn't find the screen to capture. Try again."
        }
    }
}
