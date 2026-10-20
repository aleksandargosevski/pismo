/// Attributes of a UI element that rules can match against. The element's value is never read,
/// so typed text never ends up in logs or rules.
public struct ElementAttributes: Equatable {
    public var role: String?
    public var subrole: String?
    public var roleDescription: String?
    public var title: String?
    public var description: String?
    public var placeholder: String?
    public var help: String?
    public var identifier: String?
    public var domIdentifier: String?
    public var domClasses: [String]

    public init(
        role: String? = nil,
        subrole: String? = nil,
        roleDescription: String? = nil,
        title: String? = nil,
        description: String? = nil,
        placeholder: String? = nil,
        help: String? = nil,
        identifier: String? = nil,
        domIdentifier: String? = nil,
        domClasses: [String] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.roleDescription = roleDescription
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.help = help
        self.identifier = identifier
        self.domIdentifier = domIdentifier
        self.domClasses = domClasses
    }
}

/// A focused element together with its ancestors, nearest parent first.
public struct ElementSnapshot: Equatable {
    public let attributes: ElementAttributes
    public let ancestors: [ElementAttributes]

    public init(attributes: ElementAttributes, ancestors: [ElementAttributes] = []) {
        self.attributes = attributes
        self.ancestors = ancestors
    }
}
