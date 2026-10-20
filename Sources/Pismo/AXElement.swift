import ApplicationServices
import PismoCore

extension ElementAttributes {
    init(_ element: AXUIElement) {
        self.init(
            role: AX.string(element, kAXRoleAttribute),
            subrole: AX.string(element, kAXSubroleAttribute),
            roleDescription: AX.string(element, kAXRoleDescriptionAttribute),
            title: AX.string(element, kAXTitleAttribute),
            description: AX.string(element, kAXDescriptionAttribute),
            placeholder: AX.string(element, kAXPlaceholderValueAttribute),
            help: AX.string(element, kAXHelpAttribute),
            identifier: AX.string(element, kAXIdentifierAttribute),
            domIdentifier: AX.string(element, "AXDOMIdentifier"),
            domClasses: AX.strings(element, "AXDOMClassList")
        )
    }
}

extension ElementSnapshot {
    private static let maxAncestors = 8
    private static let stopRoles: Set<String> = [kAXWindowRole, kAXApplicationRole]

    init(_ element: AXUIElement) {
        var ancestors: [ElementAttributes] = []
        var current = AX.element(element, kAXParentAttribute)
        while let parent = current, ancestors.count < Self.maxAncestors {
            let parentAttributes = ElementAttributes(parent)
            if let role = parentAttributes.role, Self.stopRoles.contains(role) { break }
            ancestors.append(parentAttributes)
            current = AX.element(parent, kAXParentAttribute)
        }
        self.init(attributes: ElementAttributes(element), ancestors: ancestors)
    }
}

enum AX {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let string = copyValue(element, attribute) as? String, !string.isEmpty else { return nil }
        return string
    }

    static func strings(_ element: AXUIElement, _ attribute: String) -> [String] {
        (copyValue(element, attribute) as? [String]) ?? []
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
