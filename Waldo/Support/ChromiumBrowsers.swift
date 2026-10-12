import AppKit

/// Chromium browsers only expose their web content to Accessibility when a client
/// sets AXEnhancedUserInterface (they reject AXManualAccessibility). That attribute
/// has side effects (slower window moves/animations, more CPU), so the popup in
/// these browsers is opt-in per browser.
enum ChromiumBrowsers {
    static let knownBundleIDs = [
        "com.brave.Browser",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
    ]

    /// Known browsers installed on this Mac, in list order.
    static var installedBundleIDs: [String] {
        knownBundleIDs.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }
}
