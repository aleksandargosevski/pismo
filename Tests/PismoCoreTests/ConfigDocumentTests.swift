import Foundation
import Testing
@testable import PismoCore

private let slack = "com.tinyspeck.slackmacgap"

private let handWritten = """
{
  "default": "ABC",
  "apps": {
    "com.tinyspeck.slackmacgap": {
      "fields": [
        {
          "name": "message composer",
          "match": { "role": "^AXTextArea$", "domClass": "^ql-editor$" },
          "layout": "Serbian"
        }
      ]
    }
  }
}

"""

@Test func serializationRoundTripsHandWrittenConfig() throws {
    let document = try ConfigDocument.parse(Data(handWritten.utf8))
    #expect(document.serialized() == handWritten)
}

@Test func serializationEscapesRegexBackslashes() throws {
    var document = ConfigDocument(defaultLayout: "ABC")
    document.addFieldRule(FieldDocument(match: MatchDocument(patterns: [.placeholder: #"^Message\b"#]), layout: "Serbian"), for: slack)
    let reparsed = try ConfigDocument.parse(Data(document.serialized().utf8))
    #expect(reparsed == document)
    #expect(document.serialized().contains(#""^Message\\b""#))
}

@Test func nestedAncestorIsWrittenOnSeparateLines() throws {
    var document = ConfigDocument(defaultLayout: "ABC")
    let match = MatchDocument(patterns: [.role: "^AXTextArea$"], ancestor: MatchDocument(patterns: [.description: "^composer$"]))
    document.addFieldRule(FieldDocument(name: "composer", match: match, layout: "Serbian"), for: slack)
    #expect(try ConfigDocument.parse(Data(document.serialized().utf8)) == document)
    #expect(document.serialized().contains(#""ancestor": { "description": "^composer$" }"#))
}

@Test func newFieldRuleGoesFirstAndReplacesSameMatch() throws {
    var document = try ConfigDocument.parse(Data(handWritten.utf8))
    let other = FieldDocument(name: "search", match: MatchDocument(patterns: [.role: "^AXTextField$"]), layout: "ABC")
    document.addFieldRule(other, for: slack)
    #expect(document.apps[slack]?.fields.map(\.name) == ["search", "message composer"])

    let replacement = FieldDocument(name: "composer v2", match: document.apps[slack]!.fields[1].match, layout: "Serbian (Latin)")
    document.addFieldRule(replacement, for: slack)
    #expect(document.apps[slack]?.fields.map(\.name) == ["composer v2", "search"])
}

@Test func choosingDefaultLayoutRemovesEmptyApp() {
    var document = ConfigDocument(defaultLayout: "ABC")
    document.setAppLayout("Serbian", for: "com.apple.Notes")
    #expect(document.apps["com.apple.Notes"]?.layout == "Serbian")

    document.setAppLayout("ABC", for: "com.apple.Notes")
    #expect(document.apps["com.apple.Notes"] == nil)
}

@Test func choosingDefaultLayoutKeepsAppWithFieldRules() throws {
    var document = try ConfigDocument.parse(Data(handWritten.utf8))
    document.setAppLayout("Serbian", for: slack)
    document.setAppLayout("ABC", for: slack)
    #expect(document.apps[slack]?.layout == nil)
    #expect(document.apps[slack]?.fields.count == 1)
}

@Test func removingLastFieldRuleRemovesApp() throws {
    var document = try ConfigDocument.parse(Data(handWritten.utf8))
    let removed = document.removeFieldRule(named: "message composer", for: slack)
    #expect(removed)
    #expect(document.apps[slack] == nil)
    let removedMissing = document.removeFieldRule(named: "missing", for: slack)
    #expect(!removedMissing)
}

@Test func unnamedRuleCanBeRemovedByItsPathName() throws {
    var document = ConfigDocument(defaultLayout: "ABC")
    document.addFieldRule(FieldDocument(match: MatchDocument(patterns: [.role: "^AXTextField$"]), layout: "Serbian"), for: slack)
    let config = try document.compile()
    let name = try #require(config.apps[slack]?.fields.first?.name)
    let removed = document.removeFieldRule(named: name, for: slack)
    #expect(removed)
}

// MARK: - Suggestions

@Test func suggestionPrefersStructuralAttributes() {
    let composer = ElementAttributes(role: "AXTextArea", description: "Message to Sasa Simonovic", domClasses: ["ql-editor"])
    let match = RuleSuggestion.match(for: composer)
    #expect(match.patterns == [.role: "^AXTextArea$", .domClass: "^ql-editor$"])
    #expect(RuleSuggestion.name(for: composer) == "Message field")
}

@Test func suggestionSkipsGeneratedIds() {
    let item = ElementAttributes(role: "AXGroup", domIdentifier: "message-list_1792505105.636069", domClasses: ["c-virtual_list__item"])
    #expect(RuleSuggestion.match(for: item).patterns == [.role: "^AXGroup$", .domClass: "^c-virtual_list__item$"])
}

@Test func suggestionFallsBackToFirstWordOfLabel() {
    let search = ElementAttributes(role: "AXTextField", subrole: "AXSearchField", placeholder: "Search Acme Corp")
    #expect(RuleSuggestion.match(for: search).patterns == [.role: "^AXTextField$", .subrole: "^AXSearchField$", .placeholder: "^Search"])
}

@Test func suggestedRuleMatchesTheElementItCameFrom() throws {
    let element = ElementSnapshot(attributes: ElementAttributes(role: "AXTextField", placeholder: "Search (⌘K) here"))
    var document = ConfigDocument(defaultLayout: "ABC")
    document.addFieldRule(RuleSuggestion.fieldRule(for: element, layout: "Serbian"), for: slack)
    let decision = RuleEngine.decide(config: try document.compile(), bundleIdentifier: slack, element: element)
    #expect(decision.layout == "Serbian")
}
