import Foundation

public struct LayoutDecision: Equatable {
    public enum Reason: Equatable {
        case field(String)
        case app
        case globalDefault
    }

    public let layout: String
    public let reason: Reason
}

public enum RuleEngine {
    /// Picks the layout for a focused element: first matching field rule, then the app's layout,
    /// then the global default.
    public static func decide(config: Config, bundleIdentifier: String?, element: ElementSnapshot?) -> LayoutDecision {
        guard let bundleIdentifier, let app = config.apps[bundleIdentifier] else {
            return LayoutDecision(layout: config.defaultLayout, reason: .globalDefault)
        }

        if let element, let field = app.fields.first(where: { $0.matcher.matches(element) }) {
            return LayoutDecision(layout: field.layout, reason: .field(field.name))
        }

        if let layout = app.layout {
            return LayoutDecision(layout: layout, reason: .app)
        }

        return LayoutDecision(layout: config.defaultLayout, reason: .globalDefault)
    }
}

public enum MatchAttribute: String, CaseIterable {
    case role
    case subrole
    case roleDescription
    case title
    case description
    case placeholder
    case help
    case identifier
    case domId
    case domClass

    func values(in attributes: ElementAttributes) -> [String] {
        switch self {
        case .role: [attributes.role].compactMap { $0 }
        case .subrole: [attributes.subrole].compactMap { $0 }
        case .roleDescription: [attributes.roleDescription].compactMap { $0 }
        case .title: [attributes.title].compactMap { $0 }
        case .description: [attributes.description].compactMap { $0 }
        case .placeholder: [attributes.placeholder].compactMap { $0 }
        case .help: [attributes.help].compactMap { $0 }
        case .identifier: [attributes.identifier].compactMap { $0 }
        case .domId: [attributes.domIdentifier].compactMap { $0 }
        case .domClass: attributes.domClasses
        }
    }
}

/// Matches an element when every pattern matches one of its attribute values and, if set,
/// the ancestor matcher matches any of its ancestors.
public final class ElementMatcher {
    let patterns: [MatchAttribute: NSRegularExpression]
    let ancestor: ElementMatcher?

    public init(patterns: [MatchAttribute: NSRegularExpression], ancestor: ElementMatcher? = nil) {
        self.patterns = patterns
        self.ancestor = ancestor
    }

    public func matches(_ element: ElementSnapshot) -> Bool {
        let attributesMatch = patterns.allSatisfy { attribute, expression in
            attribute.values(in: element.attributes).contains { expression.matches($0) }
        }
        guard attributesMatch else { return false }
        guard let ancestor else { return true }

        return element.ancestors.indices.contains { index in
            let candidate = ElementSnapshot(
                attributes: element.ancestors[index],
                ancestors: Array(element.ancestors[(index + 1)...])
            )
            return ancestor.matches(candidate)
        }
    }
}

private extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }
}
