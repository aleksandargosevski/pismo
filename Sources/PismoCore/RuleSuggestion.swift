import Foundation

/// Builds a field rule from the currently focused element, preferring attributes that identify
/// the kind of field rather than its current content (e.g. "Message to Sasa" changes per chat).
public enum RuleSuggestion {
    private static let maxNameLength = 40

    public static func fieldRule(for element: ElementSnapshot, layout: String) -> FieldDocument {
        FieldDocument(name: name(for: element.attributes), match: match(for: element.attributes), layout: layout)
    }

    static func match(for attributes: ElementAttributes) -> MatchDocument {
        var patterns: [MatchAttribute: String] = [:]
        patterns[.role] = attributes.role.map(exact)
        patterns[.subrole] = attributes.subrole.map(exact)
        patterns[.identifier] = attributes.identifier.flatMap(stableExact)
        patterns[.domId] = attributes.domIdentifier.flatMap(stableExact)
        patterns[.domClass] = attributes.domClasses.lazy.compactMap(stableExact).first

        let hasStructuralHint = patterns[.identifier] != nil || patterns[.domId] != nil || patterns[.domClass] != nil
        if !hasStructuralHint, let (attribute, text) = firstLabel(of: attributes), let word = firstWord(of: text) {
            patterns[attribute] = "^" + NSRegularExpression.escapedPattern(for: word)
        }
        return MatchDocument(patterns: patterns)
    }

    /// Names the kind of field ("Message field") rather than its current label ("Message to Sasa").
    static func name(for attributes: ElementAttributes) -> String {
        let name: String
        if let label = firstLabel(of: attributes)?.1, let word = firstWord(of: label) {
            name = "\(word) field"
        } else {
            name = attributes.domClasses.first ?? attributes.roleDescription ?? attributes.role ?? "field"
        }
        return name.count > maxNameLength ? String(name.prefix(maxNameLength - 1)) + "…" : name
    }

    private static func firstLabel(of attributes: ElementAttributes) -> (MatchAttribute, String)? {
        if let placeholder = attributes.placeholder { return (.placeholder, placeholder) }
        if let description = attributes.description { return (.description, description) }
        if let title = attributes.title { return (.title, title) }
        return nil
    }

    private static func firstWord(of text: String) -> String? {
        text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private static func exact(_ value: String) -> String {
        "^" + NSRegularExpression.escapedPattern(for: value) + "$"
    }

    /// Values with long digit runs are usually generated ids (timestamps, message ids) that change.
    private static func stableExact(_ value: String) -> String? {
        value.range(of: #"\d{3,}"#, options: .regularExpression) == nil ? exact(value) : nil
    }
}
