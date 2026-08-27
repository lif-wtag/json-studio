import Foundation
import Testing
@testable import JSONKit

// Phase 2, Task 13. Nicolas Seriot's JSONTestSuite — an adversarial corpus whose value is that it
// is *someone else's*: cases nobody on this project would have thought to write.
//
// Vendored at upstream commit 1ef36fa — see `Fixtures/JSONTestSuite/SOURCE.txt`. The tests are
// gated on the corpus being present, so they report as *skipped* rather than failed if it is ever
// removed; an absent conformance suite must not read as coverage.
//
// # Results, measured 2026-08-27 against 318 cases
//
//   95 `y_` (must accept)  — all 95 accepted.
//  188 `n_` (must reject)  — all 188 rejected.
//   35 `i_` (our choice)   — 12 accepted, 10 rejected, 13 not decodable as UTF-8.
//
// **Recovery is not acceptance**, which is what makes this measurable at all: JSONKit returns a
// partial tree for nearly every `n_` case, because a live editor must not go blank mid-keystroke
// (ADR-02) — but `isValid` requires an empty error list, so recovering from a document is still
// rejecting it.
//
// # Every `i_` decision, and the rule it follows from
//
// **Accepted (12).** Eleven are extreme numbers — `i_number_huge_exp`, `i_number_too_big_pos_int`,
// `i_number_real_neg_overflow` and friends — accepted because `.number` keeps its **source text**
// and is never converted to `Double`. Converting is the one thing the model exists to prevent, so
// there is nothing here to overflow. The twelfth is `i_structure_500_nested_arrays`, accepted
// because `Parser.maxDepth` (512) was chosen to clear it.
//
// **Rejected (10).** Every one is a lone `\u` surrogate, reported as `loneSurrogate`. Silently
// emitting an unpaired surrogate would put an unrepresentable character into the tree and from
// there into the clipboard.
//
// **Not decodable as UTF-8 (13).** Invalid sequences, overlong encodings, UTF-16 without a BOM.
// These never reach JSONKit, which takes a `String`: the failure is in whatever reads the file,
// and DC-09's encoding detection is where it belongs (Phase 3a).
//
// # One result that is not what it looks like
//
// `i_structure_UTF-8_BOM_empty_object` is accepted — but **not because JSONKit accepts a BOM**.
// The file's bytes are `EF BB BF 7B 7D`, and Foundation's `String(data:encoding:)` strips the BOM
// while decoding, so the parser only ever sees `{}`. Handed an actual `U+FEFF`, JSONKit **rejects**
// it with `invalidLiteral`. Pinned by a test below, because the distinction matters for 3a: the
// document layer has to strip the BOM, since the parser will not.

/// One corpus file and what the corpus expects of it.
struct ConformanceCase {
    enum Expectation: String { case accept = "y", reject = "n", implementationDefined = "i" }

    let name: String
    let expectation: Expectation
    let bytes: Data

    /// The corpus encodes its expectation in the filename's first character.
    init?(url: URL) {
        guard let bytes = try? Data(contentsOf: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        guard let prefix = name.first,
              let expectation = Expectation(rawValue: String(prefix))
        else { return nil }
        self.name = name
        self.expectation = expectation
        self.bytes = bytes
    }

    /// Corpus files are deliberately not all valid UTF-8 — several exist to see what a parser does
    /// with lone surrogates, BOMs and invalid encodings. A file we cannot decode is *rejected*,
    /// which is the honest answer: JSONKit takes a `String`, so the encoding failure happens above
    /// it, in whatever reads the file.
    var text: String? { String(data: bytes, encoding: .utf8) }
}

enum Conformance {
    static var directory: URL {
        TestFixture.repositoryRoot
            .appendingPathComponent("Packages/JSONKit/Tests/JSONKitTests/Fixtures/JSONTestSuite")
    }

    static var cases: [ConformanceCase] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(ConformanceCase.init(url:))
    }

    /// JSONKit's verdict. **Recovery is not acceptance**: `isValid` requires an empty error list,
    /// so a document we return a partial tree for is still rejected.
    static func accepts(_ item: ConformanceCase) -> Bool {
        guard let text = item.text else { return false }
        return Parser().parse(text).isValid
    }

    /// Whether the corpus has been fetched. Drives `.enabled(if:)`, so the conformance tests are
    /// reported as **skipped** rather than failed when it is absent — a red build for everyone who
    /// has not run a network fetch would be worse than useless, and a *passing* one would be a lie.
    static var isAvailable: Bool { !cases.isEmpty }

    static let fetchInstructions = """
        The JSONTestSuite corpus is not present, so conformance was not measured.
          git clone --depth 1 https://github.com/nst/JSONTestSuite /tmp/JSONTestSuite
          cp /tmp/JSONTestSuite/test_parsing/*.json \
        Packages/JSONKit/Tests/JSONKitTests/Fixtures/JSONTestSuite/
        See that directory's README for the deviations decided in advance.
        """
}

@Suite("JSONTestSuite conformance")
struct JSONTestSuiteTests {

    @Test("the corpus is present and has the expected shape",
          .enabled(if: Conformance.isAvailable))
    func corpusShape() {
        let cases = Conformance.cases
        #expect(cases.count > 250,
                Comment(rawValue: "the corpus has ~300 parsing cases; found \(cases.count)"))
        // All three expectations should be represented, or the filename convention has changed
        // under us and the whole suite would be measuring nothing.
        let kinds = Set(cases.map(\.expectation))
        #expect(kinds.contains(.accept) && kinds.contains(.reject) && kinds.contains(.implementationDefined))
    }

    @Test("every y_ case is accepted", .enabled(if: Conformance.isAvailable))
    func acceptsValidDocuments() {
        let cases = Conformance.cases.filter { $0.expectation == .accept }

        let wrong = cases.filter { !Conformance.accepts($0) }
        // A built string is not a literal, so it needs wrapping — `Comment` only converts from
        // literals.
        #expect(wrong.isEmpty, Comment(rawValue: "rejected documents the corpus says are valid: "
            + wrong.map(\.name).joined(separator: ", ")))
    }

    @Test("every n_ case is rejected — recovery returns a tree but never a clean bill",
          .enabled(if: Conformance.isAvailable))
    func rejectsInvalidDocuments() {
        let cases = Conformance.cases.filter { $0.expectation == .reject }

        let wrong = cases.filter { Conformance.accepts($0) }
        #expect(wrong.isEmpty, Comment(rawValue: "accepted documents the corpus says are invalid: "
            + wrong.map(\.name).joined(separator: ", ")))
    }

    @Test("the deviations decided in advance still hold", .enabled(if: Conformance.isAvailable))
    func documentedDeviations() {
        let cases = Conformance.cases

        /// Looks up one case by name, skipping quietly if the corpus edition lacks it.
        func verdict(_ name: String) -> Bool? {
            cases.first { $0.name == name }.map(Conformance.accepts)
        }

        // 1 · the depth limit was chosen to clear this
        if let accepted = verdict("i_structure_500_nested_arrays") {
            #expect(accepted, "500 nested arrays should parse — maxDepth is 512")
        }
        // 2 · duplicate keys are kept, not collapsed
        if let accepted = verdict("y_object_duplicated_key") {
            #expect(accepted)
        }
        // 4 · non-standard syntax is diagnosed, but still rejected
        for name in ["n_object_single_quote", "n_object_unquoted_key"] {
            if let accepted = verdict(name) {
                #expect(!accepted, "\(name) has its own error message but is still an error")
            }
        }
    }

    @Test("the BOM result belongs to the decoder, not to JSONKit",
          .enabled(if: Conformance.isAvailable))
    func bomIsStrippedByTheDecoder() throws {
        let url = Conformance.directory
            .appendingPathComponent("i_structure_UTF-8_BOM_empty_object.json")
        let bytes = try Data(contentsOf: url)
        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF], "the file really does start with a BOM")

        let decoded = try #require(String(data: bytes, encoding: .utf8))
        #expect(decoded.unicodeScalars.first?.value != 0xFEFF, "Foundation strips it while decoding")
        #expect(Parser().parse(decoded).isValid, "so the parser only ever sees {}")

        // Handed the BOM, the parser rejects it — which is why 3a's document layer must strip it.
        let withBOM = Parser().parse("\u{FEFF}{}")
        #expect(!withBOM.isValid)
        #expect(withBOM.errors.first?.kind == .invalidLiteral)
    }

    @Test("no corpus case crashes, hangs, or blows the stack",
          .enabled(if: Conformance.isAvailable))
    func survivesEveryCase() {
        // The property that matters most, and the one the corpus exists to break. Every document
        // here goes through the full domain, not just the parser.
        let cases = Conformance.cases

        for item in cases {
            guard let text = item.text else { continue }
            let result = Parser().parse(text)
            guard let tree = result.tree else { continue }

            _ = try? StatisticsWalker().walk(tree)
            _ = PathResolver(root: tree).path(at: 0)
            _ = tree.structuralDigest
            _ = Formatter(options: .minified).format(tree, source: text)
        }
    }

    @Test("anything JSONKit accepts, it can format into something that parses again",
          .enabled(if: Conformance.isAvailable))
    func acceptedDocumentsRoundTrip() {
        let cases = Conformance.cases

        for item in cases {
            guard let text = item.text, Conformance.accepts(item) else { continue }
            guard let tree = Parser().parse(text).tree else { continue }
            for options: FormatOptions in [.pretty, .minified] {
                let formatted = Formatter(options: options).format(tree, source: text)
                let reparsed = Parser().parse(formatted)
                #expect(reparsed.isValid, "\(item.name) did not survive formatting")
                #expect(reparsed.tree?.isStructurallyEqual(to: tree) == true,
                        "\(item.name) changed value when formatted")
            }
        }
    }
}
