import Foundation
import Testing
@testable import JSON_Studio
import JSONKit

// Task 15. `Agents.md` says tests belong in JSONKit wherever the logic can live in the domain —
// this is the exception it allows for, because encoding detection is squarely a *document* layer
// concern: JSONKit takes a `String` and never sees bytes at all.
//
// The BOM cases carry the weight. The parser rejects U+FEFF (proven against JSONTestSuite in
// Task 13), so a byte-order mark that survives into the text makes the document unparseable —
// while one that is silently dropped rewrites a file some other tool may depend on.

@Suite("Document encoding")
struct DocumentEncodingTests {

    private let json = #"{"a":1,"café":"🧊"}"#

    @Test("plain UTF-8 round-trips byte-for-byte")
    func utf8() throws {
        let data = Data(json.utf8)
        let decoded = try DocumentEncoding.decode(data)
        #expect(decoded.encoding == .utf8)
        #expect(decoded.text == json)
        #expect(decoded.encoding.encode(decoded.text) == data)
    }

    @Test("a UTF-8 BOM is stripped from the text and restored on save")
    func utf8BOM() throws {
        // Both halves matter: leave the mark in and the parser rejects the document; drop it on
        // save and a file that arrived with one has been silently rewritten.
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)
        let decoded = try DocumentEncoding.decode(data)

        #expect(decoded.encoding == .utf8WithBOM)
        #expect(decoded.text == json, "the mark must not reach the parser")
        #expect(decoded.text.unicodeScalars.first?.value != 0xFEFF)
        #expect(decoded.encoding.encode(decoded.text) == data, "…and must come back on save")
    }

    @Test("the stripped text actually parses — the point of stripping it")
    func strippedTextParses() throws {
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8)
        let decoded = try DocumentEncoding.decode(withBOM)
        #expect(Parser().parse(decoded.text).isValid)

        // And the failure it prevents, stated rather than implied.
        #expect(!Parser().parse("\u{FEFF}{}").isValid)
    }

    @Test("UTF-16, both byte orders, round-trip with their marks")
    func utf16() throws {
        for encoding in [DocumentEncoding.utf16LittleEndian, .utf16BigEndian] {
            let data = encoding.encode(json)
            let decoded = try DocumentEncoding.decode(data)
            #expect(decoded.encoding == encoding, "\(encoding) was not detected")
            #expect(decoded.text == json)
            #expect(decoded.encoding.encode(decoded.text) == data)
        }
    }

    @Test("a UTF-16 file is detected by its mark, not guessed from content")
    func utf16Detection() throws {
        let data = DocumentEncoding.utf16LittleEndian.encode(json)
        #expect(Array(data.prefix(2)) == [0xFF, 0xFE])
        #expect(try DocumentEncoding.decode(data).encoding == .utf16LittleEndian)
    }

    @Test("bytes that are no text at all are refused rather than mangled")
    func invalidEncoding() {
        // Not valid UTF-8, no BOM, and no UTF-16 NUL pattern. An earlier version fell back to
        // UTF-16LE unconditionally and "opened" this successfully as garbage — which is why the
        // fallback now needs positive evidence.
        let binary = Data([0xC3, 0x28, 0x80, 0xFF, 0x41, 0x42, 0x43, 0x44])
        #expect(throws: (any Error).self) { try DocumentEncoding.decode(binary) }

        // An odd byte count cannot be UTF-16 at all.
        #expect(throws: (any Error).self) { try DocumentEncoding.decode(Data([0xC3, 0x28, 0x80])) }
    }

    @Test("BOM-less UTF-16 is accepted only on evidence, never assumed")
    func bomlessUTF16NeedsEvidence() throws {
        // Real UTF-16LE JSON: ASCII content puts a NUL in every second byte.
        var bytes: [UInt8] = []
        for unit in #"{"a":1}"#.utf16 { bytes += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        let decoded = try DocumentEncoding.decode(Data(bytes))
        #expect(decoded.encoding == .utf16LittleEndian)
        #expect(decoded.text == #"{"a":1}"#)

        // Big-endian is told apart by which half holds the NUL.
        let swapped = Data(stride(from: 0, to: bytes.count, by: 2).flatMap {
            [bytes[$0 + 1], bytes[$0]]
        })
        #expect(try DocumentEncoding.decode(swapped).encoding == .utf16BigEndian)
    }

    @Test("valid UTF-8 is never mistaken for UTF-16")
    func utf8IsNotMistakenForUTF16() throws {
        // The evidence test must not fire on ordinary text, which has no NULs at all.
        for text in [json, "{}", #"{"long":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#] {
            #expect(try DocumentEncoding.decode(Data(text.utf8)).encoding == .utf8)
        }
    }

    @Test("an empty file opens as an empty UTF-8 document, not an error")
    func emptyFile() throws {
        let decoded = try DocumentEncoding.decode(Data())
        #expect(decoded.text.isEmpty)
        #expect(decoded.encoding == .utf8)
        #expect(Parser().parse(decoded.text).isEmpty, "empty is not invalid — ADR-02")
    }

    @Test("the label is what the status bar shows")
    func labels() {
        #expect(DocumentEncoding.utf8.label == "UTF-8")
        #expect(DocumentEncoding.utf8WithBOM.label == "UTF-8 with BOM")
        #expect(DocumentEncoding.utf16LittleEndian.label == "UTF-16 LE")
    }
}

@Suite("JSONDocument")
struct JSONDocumentTests {

    @Test("a new document is empty and UTF-8")
    func newDocument() {
        let document = JSONDocument()
        #expect(document.text.isEmpty)
        #expect(document.encoding == .utf8)
    }

    // Task 15 asserted these three through `JSONDocument.summary`, a synchronous parse on the
    // main thread. Task 16 replaced it with `status`, published off the main actor — so the same
    // three properties are asserted through the new surface rather than dropped with the old one.

    @Test("the domain runs inside the app — the whole point of Task 15")
    @MainActor
    func domainIsLinked() async throws {
        let document = JSONDocument()
        document.text = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Design/sample-payload.json"),
            encoding: .utf8
        )
        let status = try await settledStatus(of: document) { $0.validity == .valid }
        // The design's own figures, rendered in the status bar and the Structure header.
        #expect(status.statistics?.properties == 119)
        #expect(status.statistics?.maxDepth == 7)
    }

    @Test("an invalid document reports the CAUSE line, not the detection line")
    @MainActor
    func reportsTheCause() async throws {
        let document = JSONDocument()
        document.text = "{\n  \"a\": 1\n  \"b\": 2\n}"
        // The comma belongs at the end of line 2; the parser only noticed on line 3. Every tool
        // surveyed in Phase 0 reports line 3, which is the whole reason this project exists.
        let status = try await settledStatus(of: document) {
            if case .invalid = $0.validity { return true } else { return false }
        }
        guard case .invalid(_, let line, _) = status.validity else { return }
        #expect(line == 2)
    }

    @Test("an empty document is not an error")
    @MainActor
    func emptyDocument() {
        #expect(JSONDocument().status.validity == .empty)
    }

    /// Wait for the document's off-main status parse to land. Polling rather than a Combine
    /// expectation because the point is that the value *arrives* on the main actor, which is
    /// exactly what reading it in a loop checks.
    @MainActor
    private func settledStatus(
        of document: JSONDocument,
        satisfies predicate: (DocumentStatus) -> Bool
    ) async throws -> DocumentStatus {
        for _ in 0..<300 {
            if predicate(document.status) { return document.status }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the status never settled; last was \(document.status.validity)")
        return document.status
    }
}
