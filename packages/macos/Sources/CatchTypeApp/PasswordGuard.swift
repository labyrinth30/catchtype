#if os(macOS)
import AppKit
import ApplicationServices
import Carbon

/// AX failures suppress correction rather than risking writes into an unknown focused control.
enum CTPasswordGuard {
    struct Focus {
        let element: AXUIElement
        let role: String
        let subrole: String
        let description: String
        let title: String
    }

    static func focusedControl() -> Focus? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let value = copyAttr(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.05)
        guard let role = copyAttr(element, kAXRoleAttribute) as? String else { return nil }
        return Focus(element: element, role: role,
                     subrole: copyAttr(element, kAXSubroleAttribute) as? String ?? "",
                     description: copyAttr(element, kAXDescriptionAttribute) as? String ?? "",
                     title: copyAttr(element, kAXTitleAttribute) as? String ?? "")
    }

    static func isSecure(role: String, subrole: String, description: String, title: String) -> Bool {
        role == kAXSecureTextFieldSubrole || subrole == kAXSecureTextFieldSubrole ||
        (description + " " + title).range(of: "password|passphrase|비밀번호|암호", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func terminalLine(_ focus: Focus) -> String? {
        guard let value = copyAttr(focus.element, kAXValueAttribute) as? String else { return nil }
        return String(value.suffix(4096)).split(whereSeparator: \.isNewline).last.map(String.init)
    }

    private static func copyAttr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func terminalPromptLooksLikePassword(_ line: String) -> Bool {
        line.range(of: #"(?i)(password|passphrase|pass phrase|비밀번호|암호|\bpin)\b[^\n]*[:：]\s*$"#,
                   options: .regularExpression) != nil
    }
}
#endif
