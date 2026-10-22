import Foundation

/// Compiled, ready-to-match form of rules.json.
///
/// ```json
/// {
///   "default": "ABC",
///   "overlays": ["com.1password.1password"],
///   "apps": {
///     "com.tinyspeck.slackmacgap": {
///       "layout": "ABC",
///       "fields": [
///         { "name": "composer", "match": { "role": "^AXTextArea$", "domClass": "^ql-editor$" }, "layout": "Serbian" }
///       ]
///     }
///   }
/// }
/// ```
/// Layouts are referenced by name ("Serbian") or input source id ("com.apple.keylayout.Serbian").
/// Match values are regular expressions; every listed attribute must match.
/// Overlays are apps that show a focused panel without becoming the frontmost app; the listed
/// bundle ids are added to `builtInOverlays`.
public struct Config {
    public static let builtInOverlays: Set<String> = [
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.apple.Spotlight",
    ]

    public let defaultLayout: String
    public let apps: [String: AppRule]
    /// Bundle ids of overlay apps, including the built-in ones.
    public let overlays: Set<String>

    public init(defaultLayout: String, apps: [String: AppRule] = [:], extraOverlays: [String] = []) {
        self.defaultLayout = defaultLayout
        self.apps = apps
        self.overlays = Self.builtInOverlays.union(extraOverlays)
    }

    public static func parse(_ data: Data) throws -> Config {
        try ConfigDocument.parse(data).compile()
    }

    /// Every layout the config refers to, for validating against installed input sources.
    public var referencedLayouts: Set<String> {
        var layouts: Set<String> = [defaultLayout]
        for app in apps.values {
            if let layout = app.layout { layouts.insert(layout) }
            app.fields.forEach { layouts.insert($0.layout) }
        }
        return layouts
    }
}

public struct AppRule {
    public let layout: String?
    public let fields: [FieldRule]

    public init(layout: String? = nil, fields: [FieldRule] = []) {
        self.layout = layout
        self.fields = fields
    }
}

public struct FieldRule {
    public let name: String
    public let matcher: ElementMatcher
    public let layout: String

    public init(name: String, matcher: ElementMatcher, layout: String) {
        self.name = name
        self.matcher = matcher
        self.layout = layout
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case invalidJSON(String)
    case invalidRule(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let reason): "Invalid config: \(reason)"
        case .invalidRule(let path, let reason): "Invalid rule at \(path): \(reason)"
        }
    }
}
