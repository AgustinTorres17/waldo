import ApplicationServices

/// Thin typed wrapper over AXUIElement. Every call is synchronous IPC to the
/// target app, so callers keep these off the main thread; a global messaging
/// timeout (see `configureTimeout`) bounds how long a hung app can block us.
struct AXElement: @unchecked Sendable, Equatable {
    let ref: AXUIElement

    static let systemWide = AXElement(ref: AXUIElementCreateSystemWide())

    static func application(_ pid: pid_t) -> AXElement {
        AXElement(ref: AXUIElementCreateApplication(pid))
    }

    /// The default timeout is several seconds; a hung renderer shouldn't cost us that.
    static func configureTimeout(seconds: Float = 0.5) {
        AXUIElementSetMessagingTimeout(systemWide.ref, seconds)
    }

    static func == (lhs: AXElement, rhs: AXElement) -> Bool {
        CFEqual(lhs.ref, rhs.ref)
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func element(_ attribute: String) -> AXElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(ref: value as! AXUIElement)
    }

    func range(_ attribute: String) -> CFRange? {
        guard let value = value(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// Position + size, in AX (top-left origin) screen coordinates.
    var frame: CGRect? {
        guard let positionValue = value(kAXPositionAttribute), let sizeValue = value(kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func parameterized(_ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(ref, attribute as CFString, parameter, &value) == .success else { return nil }
        return value
    }

    func rect(_ attribute: String, _ parameter: CFTypeRef) -> CGRect? {
        guard let value = parameterized(attribute, parameter), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    func string(forRange range: CFRange) -> String? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        return parameterized(kAXStringForRangeParameterizedAttribute, parameter) as? String
    }

    func bounds(forRange range: CFRange) -> CGRect? {
        var range = range
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        return rect(kAXBoundsForRangeParameterizedAttribute, parameter)
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(ref, attribute as CFString, &settable) == .success && settable.boolValue
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(ref, attribute as CFString, value) == .success
    }

    @discardableResult
    func setRange(_ attribute: String, _ range: CFRange) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return set(attribute, value)
    }

    var children: [AXElement] {
        (value(kAXChildrenAttribute) as? [AXUIElement])?.map(AXElement.init) ?? []
    }

    /// Depth-first search with a node budget, for apps that don't answer
    /// kAXFocusedUIElement reliably (Chromium/Electron).
    func firstDescendant(maxNodes: Int = 1_500, where matches: (AXElement) -> Bool) -> AXElement? {
        var stack = [self]
        var visited = 0
        while let element = stack.popLast(), visited < maxNodes {
            visited += 1
            if matches(element) { return element }
            stack.append(contentsOf: element.children.reversed())
        }
        return nil
    }

    var attributeNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(ref, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
}
