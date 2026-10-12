import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Decides when to show or hide the popup (RESEARCH popup P1, P7). Purely
/// event-driven: global mouse/keyboard monitors detect selection gestures, and
/// one AXObserver on the frontmost app confirms selection and focus changes.
@MainActor
final class SelectionMonitor {
    private let app: AppModel
    private let popup: PopupController
    private let log = Logger(subsystem: "com.agustintorres.waldo", category: "selection")

    private var eventMonitors: [Any] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminateObserver: NSObjectProtocol?
    /// One observer per app, kept while the app runs; only the frontmost one is attached to the run loop.
    private var observers: [pid_t: AXObserver] = [:]
    private var activePid: pid_t?
    /// Apps whose accessibility tree we turn on, and the attribute that does it.
    private var forcedAttributes: [pid_t: String] = [:]
    /// Element from the frontmost app's latest AX notification (see SelectionReader.focusedElement).
    private var lastNotifiedElement: AXElement?

    private var pendingCheck: Task<Void, Never>?
    private var pendingRevalidation: Task<Void, Never>?
    private var mouseDownLocation: NSPoint?
    private var keyboardSelectionInProgress = false

    private(set) var isRunning = false

    /// Shift+these keys extends a selection: arrows, Home, End, Page Up, Page Down.
    private static let selectionKeys: Set<Int> = [
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    init(app: AppModel, popup: PopupController) {
        self.app = app
        self.popup = popup
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .keyDown, .flagsChanged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            eventMonitors.append(monitor)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.attach(to: app) }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.observers[pid] = nil
                self.forcedAttributes[pid] = nil
            }
        })
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revokeBrowserAccessibility { _ in true } }
        }
        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cancelPending()
        popup.hide(reason: "stopped")
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        terminateObserver.map(NotificationCenter.default.removeObserver)
        terminateObserver = nil
        revokeBrowserAccessibility { _ in true }
        detachFromRunLoop()
        observers.removeAll()
        activePid = nil
    }

    /// Re-applies exclusions to the frontmost app (after Settings change).
    func refresh() {
        guard isRunning else { return }
        let optedIn = Set(app.settings.accessibleBrowserBundleIDs)
        revokeBrowserAccessibility { !optedIn.contains($0) }
        attach(to: NSWorkspace.shared.frontmostApplication)
    }

    // MARK: Frontmost app

    private func attach(to runningApp: NSRunningApplication?) {
        cancelPending()
        popup.hide(reason: "app switched", keepsResult: true)
        popup.forgetDismissed()
        detachFromRunLoop()
        activePid = nil
        lastNotifiedElement = nil

        guard let runningApp, runningApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.settings.excludedBundleIDs.contains(runningApp.bundleIdentifier ?? "") else { return }
        let pid = runningApp.processIdentifier
        activePid = pid
        forceAccessibilityIfNeeded(runningApp)
        popup.resumeIfSuspended(in: pid)

        if let observer = observers[pid] {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            return
        }
        // Registration is IPC (~25 ms the first time), so it runs off the main thread.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let box = UncheckedBox(refcon)
        Task { [weak self] in
            let created = await Task.detached { Self.makeObserver(pid: pid, refcon: box.value) }.value
            guard let self, let observer = created?.value else { return }
            self.observers[pid] = observer
            if self.activePid == pid {
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
        }
    }

    private func detachFromRunLoop() {
        guard let pid = activePid, let observer = observers[pid] else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private nonisolated static func makeObserver(pid: pid_t, refcon: UnsafeMutableRawPointer) -> UncheckedBox<AXObserver>? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return nil }
        let element = AXElement.application(pid).ref
        AXObserverAddNotification(observer, element, kAXFocusedUIElementChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXSelectedTextChangedNotification as CFString, refcon)
        return UncheckedBox(observer)
    }

    /// Electron (Slack) only builds its accessibility tree when asked (RESEARCH popup P3).
    /// Chromium browsers reject AXManualAccessibility and need AXEnhancedUserInterface,
    /// which has side effects, so they're only forced when the user opted in.
    private func forceAccessibilityIfNeeded(_ runningApp: NSRunningApplication) {
        let pid = runningApp.processIdentifier
        guard forcedAttributes[pid] == nil else { return }
        let attribute: String
        if app.settings.accessibleBrowserBundleIDs.contains(runningApp.bundleIdentifier ?? "") {
            attribute = Self.browserAttribute
        } else if let bundleURL = runningApp.bundleURL, FileManager.default.fileExists(
            atPath: bundleURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) {
            attribute = "AXManualAccessibility"
        } else {
            return
        }
        forcedAttributes[pid] = attribute
        log.info("Enabling \(attribute, privacy: .public) for \(runningApp.bundleIdentifier ?? "?", privacy: .public)")
        Task.detached { AXElement.application(pid).set(attribute, kCFBooleanTrue) }
    }

    private static let browserAttribute = "AXEnhancedUserInterface"

    /// Turns AXEnhancedUserInterface back off in running browsers whose bundle ID matches.
    private func revokeBrowserAccessibility(where shouldRevoke: (String) -> Bool) {
        for (pid, attribute) in forcedAttributes where attribute == Self.browserAttribute {
            guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  shouldRevoke(bundleID) else { continue }
            forcedAttributes[pid] = nil
            log.info("Disabling \(attribute, privacy: .public) for \(bundleID, privacy: .public)")
            // Synchronous so it also completes when Waldo is quitting (bounded by the AX timeout).
            AXElement.application(pid).set(attribute, kCFBooleanFalse)
        }
    }

    // MARK: Events

    private func handle(_ event: NSEvent) {
        // Our own ⌘A/⌘C/⌘V from the hotkeys or Replace must not trigger or dismiss anything.
        guard !app.isAutomatingInput, activePid != nil else { return }

        switch event.type {
        case .leftMouseDown:
            // Global monitors never see clicks on our own panel, so this is an outside click.
            mouseDownLocation = NSEvent.mouseLocation
            cancelPending()
            popup.hide(reason: "outside click")
        case .leftMouseUp:
            let location = NSEvent.mouseLocation
            let dragged = mouseDownLocation.map { hypot($0.x - location.x, $0.y - location.y) > 3 } ?? false
            if dragged || event.clickCount >= 2 || event.modifierFlags.contains(.shift) {
                scheduleCheck(after: .milliseconds(event.clickCount == 2 ? 200 : 150), mouseLocation: location)
            }
        case .keyDown:
            handleKeyDown(event)
        case .flagsChanged:
            if keyboardSelectionInProgress, !event.modifierFlags.contains(.shift) {
                keyboardSelectionInProgress = false
                scheduleCheck(after: .milliseconds(150), mouseLocation: nil)
            }
        default:
            break
        }
    }

    /// Function keys and the Mission Control (160), Launchpad (131) and Globe (179) keys.
    private static let systemKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        160, 131, 179,
    ]

    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)
        let keyboardTrigger = app.settings.keyboardSelectionEnabled

        if keyCode == kVK_Escape {
            cancelPending()
            popup.hide(reason: "escape")
        } else if flags.contains(.shift), Self.selectionKeys.contains(keyCode) {
            cancelPending()
            popup.hide(reason: "keyboard selection changing")
            keyboardSelectionInProgress = keyboardTrigger
        } else if flags.contains(.command) {
            if keyCode == kVK_ANSI_A, keyboardTrigger {
                scheduleCheck(after: .milliseconds(150), mouseLocation: nil)
            }
        } else if flags.contains(.control) || Self.systemKeys.contains(keyCode) {
            // Ctrl+arrows switch desktops, F3 opens Mission Control: not typing. A
            // desktop switch suspends the popup instead (PopupController).
        } else {
            // Typing replaces the selection; the popup would be stale.
            keyboardSelectionInProgress = false
            cancelPending()
            popup.hide(reason: "typing")
        }
    }

    private func scheduleCheck(after delay: Duration, mouseLocation: NSPoint?) {
        guard app.settings.popupEnabled, let pid = activePid else { return }
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else { return }
            guard let snapshot = await self?.readSelection(pid: pid),
                  !Task.isCancelled, let self, self.activePid == pid, !self.app.isAutomatingInput else { return }
            let anchor = PopupPositioner.anchor(for: snapshot, mouseLocation: mouseLocation)
            self.log.debug("Showing popup: web=\(snapshot.isWebContent, privacy: .public) rects=\(snapshot.selectionRects.count, privacy: .public) anchor=\(NSStringFromRect(anchor), privacy: .public)")
            self.popup.show(snapshot, anchor: anchor)
        }
    }

    /// Reads the selection; for apps whose accessibility tree we force on (Electron,
    /// opted-in browsers) and that has gone to sleep or is still building, asks for
    /// it again and retries while it rebuilds.
    private func readSelection(pid: pid_t) async -> SelectionSnapshot? {
        // Chromium 150 (Slack 4.51) turns its tree off after a while without AX
        // clients and takes 2–4 s to rebuild it after AXManualAccessibility is set.
        let forcedAttribute = forcedAttributes[pid]
        let retries: [Duration] = forcedAttribute != nil ? [.milliseconds(1_000), .milliseconds(1_500)] : []
        for (attempt, wait) in ([Duration.zero] + retries).enumerated() {
            if attempt > 0 {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return nil }
            }
            let hint = lastNotifiedElement
            let (snapshot, hasFocus) = await Task.detached {
                (SelectionReader.read(pid: pid, hint: hint), SelectionReader.focusedElement(pid: pid, hint: hint) != nil)
            }.value
            if let snapshot { return snapshot }
            guard !hasFocus, attempt < retries.count else {
                log.debug("No editable selection to show")
                return nil
            }
            if attempt == 0, let forcedAttribute {
                log.info("Accessibility tree asleep; waking it")
                Task.detached { AXElement.application(pid).set(forcedAttribute, kCFBooleanTrue) }
            }
        }
        return nil
    }

    private func cancelPending() {
        pendingCheck?.cancel()
        pendingCheck = nil
        pendingRevalidation?.cancel()
        pendingRevalidation = nil
    }

    // MARK: AX notifications

    fileprivate func handleAXNotification(_ name: String, element: AXElement) {
        lastNotifiedElement = element
        guard !app.isAutomatingInput else { return }
        switch name {
        case kAXFocusedUIElementChangedNotification:
            // A pending selection check stays: it reads whatever is focused when it
            // runs, and Gmail in Chromium moves focus inside the body on ⌘A.
            if pendingCheck != nil { log.debug("Focus changed during a pending selection check") }
            pendingRevalidation?.cancel()
            pendingRevalidation = nil
            keyboardSelectionInProgress = false
            popup.hide(reason: "focus changed")
            popup.forgetDismissed()
        case kAXSelectedTextChangedNotification:
            // Only used to hide a visible popup when its selection goes away (settles after 300 ms).
            guard popup.isVisible, let snapshot = popup.snapshot else { return }
            pendingRevalidation?.cancel()
            pendingRevalidation = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let state = await Task.detached { SelectionReader.revalidate(snapshot) }.value
                guard !Task.isCancelled, let self, !self.app.isAutomatingInput else { return }
                if state != .unchanged, self.popup.snapshot?.identity == snapshot.identity {
                    self.popup.hide(reason: "selection changed")
                }
            }
        default:
            break
        }
    }
}

/// Delivered on the main run loop, where the observer's source is attached.
private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let name = notification as String
    let monitor = UncheckedBox(refcon)
    let source = AXElement(ref: element)
    MainActor.assumeIsolated {
        Unmanaged<SelectionMonitor>.fromOpaque(monitor.value).takeUnretainedValue()
            .handleAXNotification(name, element: source)
    }
}

/// Moves a non-Sendable CF value across a task boundary we control.
private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
