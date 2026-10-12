import ApplicationServices

/// Decides whether a focused element is an editable text field (RESEARCH
/// "Floating selection popup" P2). Secure fields are always rejected.
enum EditableFieldDetector {
    enum Result {
        case editable(AXElement)
        case secure
        case notEditable
    }

    private static let textRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole]

    static func classify(_ element: AXElement) -> Result {
        if isSecure(element) { return .secure }

        if let role = element.string(kAXRoleAttribute), textRoles.contains(role),
           element.isSettable(kAXValueAttribute) || element.range(kAXSelectedTextRangeAttribute) != nil {
            return .editable(element)
        }
        // Web content: focus can land on a descendant of a contenteditable root.
        if let ancestor = element.element("AXHighestEditableAncestor") ?? element.element("AXEditableAncestor") {
            return isSecure(ancestor) ? .secure : .editable(ancestor)
        }
        return .notEditable
    }

    private static func isSecure(_ element: AXElement) -> Bool {
        element.string(kAXSubroleAttribute) == kAXSecureTextFieldSubrole
    }
}
