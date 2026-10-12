import Foundation
import os
import ServiceManagement

/// Opens Waldo when the user logs in. macOS keeps the setting (System Settings ›
/// General › Login Items), so it's read from there, not stored by Waldo. Off until
/// the user turns it on.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled = false
    /// The user turned it off in System Settings; only they can turn it back on there.
    @Published private(set) var needsApproval = false

    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "login")

    init() {
        refresh()
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
