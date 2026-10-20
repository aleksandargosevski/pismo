import Foundation
import Testing
@testable import PismoCore

private let slack = "com.tinyspeck.slackmacgap"

private let configJSON = """
{
  "default": "ABC",
  "apps": {
    "com.tinyspeck.slackmacgap": {
      "fields": [
        {
          "name": "composer",
          "match": { "role": "^AXTextArea$", "domClass": "^ql-editor$", "ancestor": { "description": "^composer$" } },
          "layout": "Serbian"
        }
      ]
    },
    "com.apple.Notes": { "layout": "Serbian-Latin" }
  }
}
"""

private let composer = ElementSnapshot(
    attributes: ElementAttributes(role: "AXTextArea", description: "Message to Sasa", domClasses: ["ql-editor"]),
    ancestors: [
        ElementAttributes(role: "AXGroup", domClasses: ["c-texty_input_unstyled", "ql-container"]),
        ElementAttributes(role: "AXGroup", description: "composer"),
    ]
)

private func decide(_ bundleIdentifier: String?, _ element: ElementSnapshot?) throws -> LayoutDecision {
    let config = try Config.parse(Data(configJSON.utf8))
    return RuleEngine.decide(config: config, bundleIdentifier: bundleIdentifier, element: element)
}

@Test func matchingFieldRuleWins() throws {
    #expect(try decide(slack, composer) == LayoutDecision(layout: "Serbian", reason: .field("composer")))
}

@Test func nonMatchingFieldFallsBackToGlobalDefault() throws {
    let search = ElementSnapshot(attributes: ElementAttributes(role: "AXTextField", placeholder: "Search"))
    #expect(try decide(slack, search) == LayoutDecision(layout: "ABC", reason: .globalDefault))
}

@Test func fieldWithoutRequiredAncestorDoesNotMatch() throws {
    let editorElsewhere = ElementSnapshot(attributes: composer.attributes, ancestors: [ElementAttributes(role: "AXGroup")])
    #expect(try decide(slack, editorElsewhere).reason == .globalDefault)
}

@Test func appLayoutAppliesWithoutFieldRules() throws {
    #expect(try decide("com.apple.Notes", nil) == LayoutDecision(layout: "Serbian-Latin", reason: .app))
}

@Test func unknownAppUsesGlobalDefault() throws {
    #expect(try decide("com.apple.Safari", composer) == LayoutDecision(layout: "ABC", reason: .globalDefault))
    #expect(try decide(nil, nil).layout == "ABC")
}

@Test func referencedLayoutsIncludeEveryRule() throws {
    let config = try Config.parse(Data(configJSON.utf8))
    #expect(config.referencedLayouts == ["ABC", "Serbian", "Serbian-Latin"])
}

@Test func unknownMatchKeyIsRejected() {
    let json = #"{ "default": "ABC", "apps": { "x": { "fields": [ { "match": { "rol": "AXTextArea" }, "layout": "Serbian" } ] } } }"#
    #expect(throws: ConfigError.self) { try Config.parse(Data(json.utf8)) }
}

@Test func invalidRegexIsRejectedWithPath() {
    let json = #"{ "default": "ABC", "apps": { "x": { "fields": [ { "match": { "role": "(" }, "layout": "Serbian" } ] } } }"#
    #expect(throws: ConfigError.invalidRule(path: "apps.x.fields[0].match.role", reason: #"invalid regular expression "(""#)) {
        try Config.parse(Data(json.utf8))
    }
}

@Test func emptyMatchIsRejected() {
    let json = #"{ "default": "ABC", "apps": { "x": { "fields": [ { "match": {}, "layout": "Serbian" } ] } } }"#
    #expect(throws: ConfigError.self) { try Config.parse(Data(json.utf8)) }
}

@Test func missingDefaultIsRejected() {
    #expect(throws: ConfigError.self) { try Config.parse(Data(#"{ "apps": {} }"#.utf8)) }
}
