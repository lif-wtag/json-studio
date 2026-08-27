import Testing
@testable import JSONKit

// Phase 2, step 3. ADR-02's promise, tested as a property rather than case by case: a live
// editor spends most of its time on invalid input, and the tree must not go blank mid-keystroke.
// So these tests care less about *which* errors come back than about the parser always
// terminating, always making progress, and always returning as much tree as the input allows.

/// The six ways the build guide's Phase 3c command says to break the sample payload.
enum Breakage: String, CaseIterable {
    case missingComma, trailingComma, unterminatedString
    case unbalancedBrace, bareIdentifier, wrongQuoteStyle

    func applied(to source: String) -> String {
        switch self {
        case .missingComma:       source.replacingOccurrences(of: "\"method\": \"GET\",", with: "\"method\": \"GET\"")
        case .trailingComma:      source.replacingOccurrences(of: "\"authenticated\": true,", with: "\"authenticated\": true,,")
        case .unterminatedString: source.replacingOccurrences(of: "\"locale\": \"de-DE\",", with: "\"locale\": \"de-DE,")
        case .unbalancedBrace:    source.replacingOccurrences(of: "\"request\": {", with: "\"request\": {{")
        case .bareIdentifier:     source.replacingOccurrences(of: "\"x-region\": null", with: "x-region: null")
        case .wrongQuoteStyle:    source.replacingOccurrences(of: "\"accept\": \"application/json\"", with: "'accept': 'application/json'")
        }
    }
}

@Suite("Parser · error recovery")
struct ParserRecoveryTests {

    @Test("every breakage of the sample payload still yields a tree", arguments: Breakage.allCases)
    func treeSurvives(_ breakage: Breakage) throws {
        let source = try sampleJSON()
        let broken = breakage.applied(to: source)
        try #require(broken != source, "the breakage must actually change the fixture")

        let result = Parser().parse(broken)
        #expect(!result.errors.isEmpty, "\(breakage) should be reported")
        #expect(result.tree != nil, "the tree must not go blank — ADR-02")
        #expect(result.tree?.kind == .object)
        // The document is still recognisably itself: parsing did not stop at the first error.
        #expect(result.tree?.value.member("schemaVersion")?.node.value == .string("2026-08"))
    }

    @Test("every prefix of a broken document terminates, with well-formed errors")
    func everyPrefixTerminates() throws {
        // Truncation is what a document looks like while it is being typed, and it is the input
        // most likely to make a recovering parser spin. The tokenizer has the same test.
        let source = try sampleJSON()
        let units = Array(source.utf16)

        for length in stride(from: 0, through: units.count, by: 37) {
            let prefix = String(decoding: units[0..<length], as: UTF16.self)
            let result = Parser().parse(prefix)

            for error in result.errors {
                #expect(error.span.start >= 0)
                #expect(error.span.end <= length, "a span past the end of the document")
                #expect(error.span.start <= error.span.end)
                #expect(!error.copy.title.isEmpty, "\(error.kind) has no copy")
            }
            if length > 1 { #expect(result.tree != nil, "prefix of length \(length) lost its tree") }
        }
    }

    @Test("a document that opens with junk still parses the value that follows")
    func junkBeforeTheValue() {
        let result = parse("# {\"a\": 1}")
        #expect(result.firstError(.invalidLiteral) != nil)
        #expect(result.tree?.value.member("a")?.node.value == .number("1"))
    }

    @Test("an unterminated string does not swallow the line below it")
    func unterminatedStringStopsAtTheNewline() {
        //             {"a": "oops,\n "b": 2}
        let result = parse("{\n  \"a\": \"oops,\n  \"b\": 2\n}")
        #expect(result.firstError(.unterminatedString) != nil)
        // `b` is on the next line and must still have parsed — this is the tokenizer's decision
        // not to consume the newline, proven end-to-end through the parser.
        #expect(result.tree?.value.member("b")?.node.value == .number("2"))
    }

    @Test("several errors are reported at once, which throwing on the first would prevent")
    func multipleErrors() {
        let result = parse("{\"a\" 1, \"b\": , \"c\": 3,}")
        #expect(result.errors.count >= 3, "got \(result.kinds)")
        #expect(result.kinds.contains(.missingColon))
        #expect(result.kinds.contains(.missingValue))
        #expect(result.kinds.contains(.trailingComma))
        // And the two well-formed members are still in the tree.
        #expect(result.tree?.value.member("c")?.node.value == .number("3"))
    }

    @Test("junk between members is skipped rather than derailing the rest of the object")
    func junkBetweenMembers() {
        let result = parse("{\"a\": 1 @ \"b\": 2}")
        #expect(!result.errors.isEmpty)
        #expect(result.tree?.value.member("a")?.node.value == .number("1"))
        #expect(result.tree?.value.member("b")?.node.value == .number("2"))
    }

    @Test("a nested container inside junk is skipped whole, so its closers aren't miscounted")
    func junkContainerIsSkippedBalanced() {
        let result = parse("{\"a\": 1 [2, {\"x\": 3}] \"b\": 4}")
        // The stray array must not make the object think it has closed.
        #expect(result.tree?.value.member("b")?.node.value == .number("4"))
        #expect(result.kinds.contains(.missingClosingBrace) == false)
    }

    @Test("pathological input terminates instead of spinning or crashing")
    func pathologicalInput() {
        let cases = [
            String(repeating: "[", count: 100_000),
            String(repeating: "{", count: 10_000),
            String(repeating: ",", count: 10_000),
            "[" + String(repeating: ",", count: 10_000) + "]",
            "{" + String(repeating: ":", count: 5_000) + "}",
            String(repeating: "\"", count: 10_000),
        ]
        for source in cases {
            let result = Parser().parse(source)
            // The assertion is simply that we got here: no stall, no stack overflow.
            #expect(result.errors.isEmpty == false || result.tree != nil)
        }
    }

    @Test("recovery never invents a value it wasn't given")
    func noInventedValues() {
        // Each of these has an unusable value; none may appear in the tree with a guessed one.
        #expect(parse("{\"a\": True}").tree?.value.childCount == 0)
        #expect(parse("{\"a\": }").tree?.value.childCount == 0)
        #expect(parse("[NaN]").tree?.value.childCount == 0)
    }
}
