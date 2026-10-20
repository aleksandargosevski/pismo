import Foundation

/// Minimal ordered JSON tree used to write rules.json in a readable, stable format:
/// small flat objects and arrays stay on one line, everything else is indented by two spaces.
enum JSONValue {
    case string(String)
    case object([(String, JSONValue)])
    case array([JSONValue])

    private static let maxInlineWidth = 100
    private static let indentUnit = "  "

    func rendered(indent: Int = 0) -> String {
        if let inline = inlineRendering(), inline.count + indent * Self.indentUnit.count <= Self.maxInlineWidth {
            return inline
        }

        let inner = String(repeating: Self.indentUnit, count: indent + 1)
        let outer = String(repeating: Self.indentUnit, count: indent)
        switch self {
        case .string(let value):
            return Self.quote(value)
        case .object(let pairs):
            let lines = pairs.map { "\(inner)\(Self.quote($0.0)): \($0.1.rendered(indent: indent + 1))" }
            return "{\n\(lines.joined(separator: ",\n"))\n\(outer)}"
        case .array(let items):
            let lines = items.map { "\(inner)\($0.rendered(indent: indent + 1))" }
            return "[\n\(lines.joined(separator: ",\n"))\n\(outer)]"
        }
    }

    /// One-line form, available only when every child is a string.
    private func inlineRendering() -> String? {
        switch self {
        case .string(let value):
            return Self.quote(value)
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            guard pairs.allSatisfy({ $0.1.isString }) else { return nil }
            return "{ " + pairs.map { "\(Self.quote($0.0)): \($0.1.rendered())" }.joined(separator: ", ") + " }"
        case .array(let items):
            if items.isEmpty { return "[]" }
            guard items.allSatisfy(\.isString) else { return nil }
            return "[" + items.map { $0.rendered() }.joined(separator: ", ") + "]"
        }
    }

    private var isString: Bool {
        if case .string = self { return true }
        return false
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
