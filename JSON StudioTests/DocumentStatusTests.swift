import Foundation
import Testing
@testable import JSON_Studio
import JSONKit

// Task 16. `Agents.md` puts tests in JSONKit wherever the logic can live in the domain; this is
// the document layer's share — the bridge from bytes and text to the four things the status bar
// reports, and the guarantee that measuring them never touches the main thread.

@Suite("Document status")
struct DocumentStatusTests {

    /// The one sample payload the contract fixes for every fixture, read from the repo rather than
    /// copied into the bundle — there is only ever one of it.
    private static let fixture: (text: String, byteCount: Int) = {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1, !FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Design/sample-payload.json").path
        ) {
            url.deleteLastPathComponent()
        }
        let data = try! Data(contentsOf: url.appendingPathComponent("Design/sample-payload.json"))
        return (String(decoding: data, as: UTF8.self), data.count)
    }()

    // MARK: - The three states

    @Test("the fixture reports the figures the artboard renders")
    func fixtureIsValid() {
        let status = DocumentStatus.make(text: Self.fixture.text, encoding: .utf8)
        #expect(status.validity == .valid)
        #expect(status.semantic == .valid)
        #expect(status.isFormattable)
        // 119 properties and depth 7 are the artboard's own numbers — the status bar's and the
        // inspector's Structure header's acceptance test, not a snapshot.
        #expect(status.statistics?.properties == 119)
        #expect(status.statistics?.maxDepth == 7)
        #expect(status.byteCount == Self.fixture.byteCount)
    }

    @Test("an empty document has no glyph — nothing is yet right or wrong")
    func emptyDocument() {
        let status = DocumentStatus.make(text: "", encoding: .utf8)
        #expect(status.validity == .empty)
        #expect(status.semantic == nil)
        #expect(!status.isFormattable)
    }

    @Test("whitespace alone is still empty, not invalid")
    func whitespaceOnly() {
        #expect(DocumentStatus.make(text: "\n  \t\n", encoding: .utf8).validity == .empty)
    }

    @Test("an invalid document names the cause line, not the line the parser noticed on")
    func invalidNamesTheCause() {
        // The missing comma belongs at the end of line 2; every tool surveyed in Phase 0 reports
        // line 3. This is the whole differentiator, so the status bar has to inherit it.
        let broken = """
            {
              "region": "eu-central-1"
              "zone": "a"
            }
            """
        let status = DocumentStatus.make(text: broken, encoding: .utf8)
        guard case .invalid(let count, let line, let column) = status.validity else {
            Issue.record("expected an invalid document, got \(status.validity)")
            return
        }
        #expect(count >= 1)
        #expect(line == 2)
        #expect(column != nil)
        #expect(status.semantic == .invalid)
    }

    @Test("an invalid document is not formattable — a recovered tree formats to a different file")
    func invalidIsNotFormattable() {
        // The parser recovers rather than throwing (ADR-02), so this document *has* a tree.
        // Formatting it would emit valid JSON that silently drops what could not be parsed.
        let status = DocumentStatus.make(text: #"{"a": 1,, "b": 2}"#, encoding: .utf8)
        #expect(!status.isFormattable)
        #expect(status.statistics == nil)
    }

    // MARK: - Size

    @Test("the byte count is what would be written back, not the character count")
    func byteCountMatchesTheEncoding() {
        // The fixture has multi-byte characters and an emoji: 3,719 UTF-16 units, 3,771 UTF-8
        // bytes. The status bar reports file size, so it must be the second one.
        let utf8 = DocumentStatus.make(text: Self.fixture.text, encoding: .utf8)
        #expect(utf8.byteCount == 3771)

        let withBOM = DocumentStatus.make(text: Self.fixture.text, encoding: .utf8WithBOM)
        #expect(withBOM.byteCount == utf8.byteCount + 3)

        let utf16 = DocumentStatus.make(text: Self.fixture.text, encoding: .utf16LittleEndian)
        #expect(utf16.byteCount > utf8.byteCount)
    }

    @Test("the fixture's size renders as the artboard's 3.7 KB")
    func fixtureSizeMatchesTheArtboard() {
        let status = DocumentStatus.make(text: Self.fixture.text, encoding: .utf8)
        #expect(ParseErrorCopy.byteSize(status.byteCount) == "3.7 KB")
    }

    // MARK: - Concurrency

    @Test("measuring a document never runs on the main actor")
    func measuringIsOffTheMainActor() async {
        // The app target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so an unannotated
        // type is main-actor isolated and this detached task would hop straight back — parsing on
        // the main thread while looking as though it did not. `nonisolated` is what prevents it,
        // and this is the assertion that would fail if the annotation were dropped.
        let onMain = await Task.detached(priority: .userInitiated) {
            _ = DocumentStatus.make(text: Self.fixture.text, encoding: .utf8)
            return Thread.isMainThread
        }.value
        #expect(!onMain)
    }
}
