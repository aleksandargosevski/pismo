import Foundation

/// Editable, uncompiled form of rules.json. Round-trips through `parse` and `serialized()`;
/// keys are written in a fixed order and apps sorted by bundle id.
public struct ConfigDocument: Equatable {
    public var defaultLayout: String
    public var overlays: [String]
    public var apps: [String: AppDocument]

    public init(defaultLayout: String, overlays: [String] = [], apps: [String: AppDocument] = [:]) {
        self.defaultLayout = defaultLayout
        self.overlays = overlays
        self.apps = apps
    }

    public static func parse(_ data: Data) throws -> ConfigDocument {
        do {
            return try JSONDecoder().decode(ConfigDocument.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.invalidJSON(describe(error))
        } catch {
            throw ConfigError.invalidJSON(error.localizedDescription)
        }
    }

    public func compile() throws -> Config {
        var compiledApps: [String: AppRule] = [:]
        for (bundleIdentifier, app) in apps {
            compiledApps[bundleIdentifier] = try app.compile(path: "apps.\(bundleIdentifier)")
        }
        return Config(defaultLayout: defaultLayout, apps: compiledApps, extraOverlays: overlays)
    }

    public func serialized() -> String {
        jsonValue.rendered() + "\n"
    }

    // MARK: - Editing

    /// Sets the layout used for an app outside of field rules. Choosing the global default removes
    /// the app's layout, and the app itself once it has no rules left.
    public mutating func setAppLayout(_ layout: String, for bundleIdentifier: String) {
        var app = apps[bundleIdentifier] ?? AppDocument()
        app.layout = layout == defaultLayout ? nil : layout
        store(app, for: bundleIdentifier)
    }

    /// Adds a field rule in front of the app's other rules so it wins, replacing any rule with the same match.
    public mutating func addFieldRule(_ field: FieldDocument, for bundleIdentifier: String) {
        var app = apps[bundleIdentifier] ?? AppDocument()
        app.fields.removeAll { $0.match == field.match }
        app.fields.insert(field, at: 0)
        store(app, for: bundleIdentifier)
    }

    /// Removes the first field rule with the given name. Returns false when no rule has that name.
    @discardableResult
    public mutating func removeFieldRule(named name: String, for bundleIdentifier: String) -> Bool {
        guard var app = apps[bundleIdentifier],
              let index = app.fields.indices.first(where: { app.fields[$0].displayName(index: $0, bundleIdentifier: bundleIdentifier) == name })
        else { return false }
        app.fields.remove(at: index)
        store(app, for: bundleIdentifier)
        return true
    }

    private mutating func store(_ app: AppDocument, for bundleIdentifier: String) {
        apps[bundleIdentifier] = app.isEmpty ? nil : app
    }

    private var jsonValue: JSONValue {
        let sortedApps = apps.keys.sorted().map { ($0, apps[$0]!.jsonValue) }
        var pairs: [(String, JSONValue)] = [("default", .string(defaultLayout))]
        if !overlays.isEmpty { pairs.append(("overlays", .array(overlays.map { .string($0) }))) }
        pairs.append(("apps", .object(sortedApps)))
        return .object(pairs)
    }
}

public struct AppDocument: Equatable {
    public var layout: String?
    public var fields: [FieldDocument]

    public init(layout: String? = nil, fields: [FieldDocument] = []) {
        self.layout = layout
        self.fields = fields
    }

    var isEmpty: Bool { layout == nil && fields.isEmpty }

    func compile(path: String) throws -> AppRule {
        let compiledFields = try fields.enumerated().map { index, field in
            try field.compile(path: "\(path).fields[\(index)]", name: field.displayName(index: index, path: path))
        }
        return AppRule(layout: layout, fields: compiledFields)
    }

    var jsonValue: JSONValue {
        var pairs: [(String, JSONValue)] = []
        if let layout { pairs.append(("layout", .string(layout))) }
        if !fields.isEmpty { pairs.append(("fields", .array(fields.map(\.jsonValue)))) }
        return .object(pairs)
    }
}

public struct FieldDocument: Equatable {
    public var name: String?
    public var match: MatchDocument
    public var layout: String

    public init(name: String? = nil, match: MatchDocument, layout: String) {
        self.name = name
        self.match = match
        self.layout = layout
    }

    func displayName(index: Int, bundleIdentifier: String) -> String {
        displayName(index: index, path: "apps.\(bundleIdentifier)")
    }

    func displayName(index: Int, path: String) -> String {
        name ?? "\(path).fields[\(index)]"
    }

    func compile(path: String, name: String) throws -> FieldRule {
        FieldRule(name: name, matcher: try match.compile(path: "\(path).match"), layout: layout)
    }

    var jsonValue: JSONValue {
        var pairs: [(String, JSONValue)] = []
        if let name { pairs.append(("name", .string(name))) }
        pairs.append(("match", match.jsonValue))
        pairs.append(("layout", .string(layout)))
        return .object(pairs)
    }
}

public struct MatchDocument: Equatable {
    public var patterns: [MatchAttribute: String]
    private var ancestorStorage: [MatchDocument]

    public var ancestor: MatchDocument? {
        get { ancestorStorage.first }
        set { ancestorStorage = newValue.map { [$0] } ?? [] }
    }

    public init(patterns: [MatchAttribute: String], ancestor: MatchDocument? = nil) {
        self.patterns = patterns
        self.ancestorStorage = ancestor.map { [$0] } ?? []
    }

    func compile(path: String) throws -> ElementMatcher {
        guard !patterns.isEmpty || ancestor != nil else {
            throw ConfigError.invalidRule(path: path, reason: "match must contain at least one attribute")
        }

        var expressions: [MatchAttribute: NSRegularExpression] = [:]
        for (attribute, pattern) in patterns {
            do {
                expressions[attribute] = try NSRegularExpression(pattern: pattern)
            } catch {
                throw ConfigError.invalidRule(path: "\(path).\(attribute.rawValue)", reason: "invalid regular expression \"\(pattern)\"")
            }
        }
        return ElementMatcher(patterns: expressions, ancestor: try ancestor?.compile(path: "\(path).ancestor"))
    }

    var jsonValue: JSONValue {
        var pairs = MatchAttribute.allCases.compactMap { attribute in
            patterns[attribute].map { (attribute.rawValue, JSONValue.string($0)) }
        }
        if let ancestor { pairs.append(("ancestor", ancestor.jsonValue)) }
        return .object(pairs)
    }
}

// MARK: - Decoding

extension ConfigDocument: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case defaultLayout = "default"
        case overlays
        case apps
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultLayout = try container.decode(String.self, forKey: .defaultLayout)
        overlays = try container.decodeIfPresent([String].self, forKey: .overlays) ?? []
        apps = try container.decodeIfPresent([String: AppDocument].self, forKey: .apps) ?? [:]
    }
}

extension AppDocument: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case layout, fields
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decodeIfPresent(String.self, forKey: .layout)
        fields = try container.decodeIfPresent([FieldDocument].self, forKey: .fields) ?? []
    }
}

extension FieldDocument: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, match, layout
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        match = try container.decode(MatchDocument.self, forKey: .match)
        layout = try container.decode(String.self, forKey: .layout)
    }
}

extension MatchDocument: Decodable {
    private static let ancestorKey = "ancestor"

    public init(from decoder: Decoder) throws {
        let allowed = Set(MatchAttribute.allCases.map(\.rawValue) + [Self.ancestorKey])
        let container = try decoder.container(keyedBy: AnyKey.self)
        if let unknown = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw unknownKeyError(unknown, in: container, allowed: allowed)
        }

        var patterns: [MatchAttribute: String] = [:]
        for attribute in MatchAttribute.allCases {
            if let pattern = try container.decodeIfPresent(String.self, forKey: AnyKey(attribute.rawValue)) {
                patterns[attribute] = pattern
            }
        }
        self.init(
            patterns: patterns,
            ancestor: try container.decodeIfPresent(MatchDocument.self, forKey: AnyKey(Self.ancestorKey))
        )
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(in decoder: Decoder, allowed: Keys.Type) throws {
    let allowedNames = Set(Keys.allCases.map(\.stringValue))
    let container = try decoder.container(keyedBy: AnyKey.self)
    if let unknown = container.allKeys.first(where: { !allowedNames.contains($0.stringValue) }) {
        throw unknownKeyError(unknown, in: container, allowed: allowedNames)
    }
}

private func unknownKeyError(_ key: AnyKey, in container: KeyedDecodingContainer<AnyKey>, allowed: Set<String>) -> DecodingError {
    DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "unknown key \"\(key.stringValue)\" (allowed: \(allowed.sorted().joined(separator: ", ")))"
    )
}

private func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
        return components.isEmpty ? "root" : components.joined(separator: ".")
    }

    switch error {
    case .keyNotFound(let key, let context):
        return "missing \"\(key.stringValue)\" at \(path(context))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
        return "wrong type at \(path(context)): \(context.debugDescription)"
    case .dataCorrupted(let context):
        let reason = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
        return "\(context.debugDescription) at \(path(context))" + (reason.map { " (\($0))" } ?? "")
    @unknown default:
        return error.localizedDescription
    }
}
