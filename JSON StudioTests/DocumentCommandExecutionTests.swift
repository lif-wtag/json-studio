import Foundation
import Testing
@testable import JSON_Studio
import JSONKit

// Task 17. The menu bar, the toolbar and a keyboard shortcut all reach the same rule, so this is
// where the three of them are actually tested — a menu item's `.disabled` is a courtesy, and the
// check inside the rule is the one that holds.
//
// Everything here is pure: `FormattingPreferences.formatted(_:for:)` is a function of the source
// and the preferences, so none of it needs a document, an app host or a main actor.
//
// ⚠️ **Undo is NOT covered here, and that is a known gap, not an oversight.** It needs
// `JSONDocument`, which is main-actor isolated, and this hosted test bundle stops scheduling
// main-actor tests past the four that already exist in `DocumentEncodingTests.swift` — a fifth
// makes the whole run hang with the app's main thread sitting idle. Measured, not guessed. Until
// that is understood, undo is verified by running the app. See RUN_LOG 2026-08-27 (Task 17).

@Suite("Running a command", .serialized)
struct DocumentCommandExecutionTests {

    static let fixture: String = {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1, !FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Design/sample-payload.json").path
        ) {
            url.deleteLastPathComponent()
        }
        return try! String(
            contentsOf: url.appendingPathComponent("Design/sample-payload.json"), encoding: .utf8
        )
    }()

    // MARK: - Format

    @Test("Format rewrites the document and the result still parses to the same structure")
    func formatPreservesStructure() throws {
        let before = try #require(Parser().parse(Self.fixture).tree)
        let formatted = try #require(
            FormattingPreferences().formatted(Self.fixture, for: .format)
        )

        let after = Parser().parse(formatted)
        #expect(after.errors.isEmpty)
        // Never `==` on a container — it compares spans, and reformatting moves every one of them.
        let same = before.isStructurallyEqual(to: try #require(after.tree))
        #expect(same)
    }

    @Test("the indent preference reaches the output")
    func indentReachesTheOutput() throws {
        let tabs = try #require(
            FormattingPreferences(indent: .tabs).formatted(Self.fixture, for: .format)
        )
        #expect(tabs.contains("\n\t"))

        let four = try #require(
            FormattingPreferences(indent: .fourSpaces).formatted(Self.fixture, for: .format)
        )
        #expect(four.contains("\n    \""))
    }

    @Test("turning width-awareness off produces strictly more lines than leaving it on")
    func widthAwarenessChangesTheLayout() throws {
        func lines(widthAware: Bool) throws -> Int {
            var preferences = FormattingPreferences()
            preferences.widthAware = widthAware
            let text = try #require(preferences.formatted(Self.fixture, for: .format))
            return text.split(separator: "\n", omittingEmptySubsequences: false).count
        }
        #expect(try lines(widthAware: false) > lines(widthAware: true))
    }

    @Test("the trailing-newline preference reaches both verbs")
    func trailingNewlineReachesBothVerbs() throws {
        var preferences = FormattingPreferences()
        preferences.trailingNewline = true
        for command in [DocumentCommand.format, .minify] {
            let text = try #require(preferences.formatted(Self.fixture, for: command))
            #expect(text.hasSuffix("\n"), "\(command.menuTitle) dropped it")
        }
        // And is off by default, matching FormatOptions.
        let plain = try #require(FormattingPreferences().formatted(Self.fixture, for: .format))
        #expect(!plain.hasSuffix("\n"))
    }

    @Test("Minify ignores indent and width, as it must")
    func minifyIgnoresLayoutPreferences() throws {
        let preferences = FormattingPreferences(indent: .tabs, widthAware: true, printWidth: 40)
        let text = try #require(preferences.formatted(Self.fixture, for: .minify))
        #expect(!text.contains("\n"))
        #expect(!text.contains("\t"))
    }

    @Test("formatting is idempotent — running it twice changes nothing the second time")
    func formatIsIdempotent() throws {
        let once = try #require(FormattingPreferences().formatted(Self.fixture, for: .format))
        let twice = try #require(FormattingPreferences().formatted(once, for: .format))
        #expect(once == twice)
    }

    // MARK: - Refusal

    @Test("an invalid document is refused, even reached past both disabled controls")
    func invalidIsRefused() {
        // The parser recovers rather than throwing, so this document *has* a tree — which is
        // exactly why formatting it would emit valid JSON that drops what could not be parsed.
        let broken = #"{"a": 1,, "b": 2}"#
        #expect(Parser().parse(broken).tree != nil)
        #expect(FormattingPreferences().formatted(broken, for: .format) == nil)
        #expect(FormattingPreferences().formatted(broken, for: .minify) == nil)
    }

    @Test("refusal is judged on the text handed in, not on a status that may lag it")
    func refusalUsesTheTextNotAStatus() {
        // The status bar's parse is debounced and off-main, so between an edit and its next
        // status the document can be invalid while `isFormattable` still says otherwise. A
        // shortcut pressed in that window must still be refused.
        #expect(FormattingPreferences().formatted(Self.fixture, for: .format) != nil)
        #expect(FormattingPreferences().formatted(Self.fixture + "}", for: .format) == nil)
    }

    @Test("an empty document produces nothing rather than an empty file")
    func emptyIsRefused() {
        #expect(FormattingPreferences().formatted("", for: .format) == nil)
        #expect(FormattingPreferences().formatted("   \n", for: .format) == nil)
    }

    @Test("Compare is not a formatting verb and produces no text")
    func compareProducesNothing() {
        #expect(FormattingPreferences().formatted(Self.fixture, for: .compare) == nil)
    }
}
