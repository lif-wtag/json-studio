import Testing
@testable import JSONKit

// Phase 2, step 3 — the happy path and the tree shape. Recovery lives in ParserRecoveryTests,
// and the cause-vs-detection attribution in ParserAttributionTests, because that is the part
// the product is justified on and it deserves its own suite.

func parse(_ source: String) -> ParseResult {
    Parser().parse(source)
}

/// The first error of a kind, so a test can name what it is asserting rather than an index.
extension ParseResult {
    func firstError(_ kind: ParseError.Kind) -> ParseError? {
        errors.first { $0.kind == kind }
    }
    var kinds: [ParseError.Kind] { errors.map(\.kind) }
}

@Suite("Parser · valid documents")
struct ParserValidTests {

    @Test("the six value kinds parse, each spanning exactly its own text")
    func scalars() {
        let cases: [(String, JSONValue)] = [
            ("\"café\"", .string("café")),
            ("42", .number("42")),
            ("-1.5e3", .number("-1.5e3")),
            ("true", .bool(true)),
            ("false", .bool(false)),
            ("null", .null),
        ]
        for (source, expected) in cases {
            let result = parse(source)
            #expect(result.isValid, "\(source) should be valid")
            #expect(result.tree?.value == expected)
            #expect(result.tree?.span == SourceSpan(start: 0, end: source.utf16.count))
        }
    }

    @Test("leading and trailing whitespace stays outside the root span")
    func whitespaceOutsideSpan() {
        let result = parse("\n  {\"a\": 1}  \n")
        #expect(result.isValid)
        #expect(result.tree?.span == SourceSpan(start: 3, end: 11))
    }

    @Test("an empty document is not an error — it is every new window's state")
    func emptyDocument() {
        for source in ["", "   ", "\n\t\r\n"] {
            let result = parse(source)
            #expect(result.tree == nil)
            #expect(result.errors.isEmpty)
            #expect(result.isEmpty)
            #expect(!result.isValid)
        }
    }

    @Test("object members keep document order and their own key spans")
    func objectMembers() {
        //             0123456789...
        let result = parse("{\"a\": 1, \"bb\": true}")
        #expect(result.isValid)
        guard case .object(let members)? = result.tree?.value else {
            Issue.record("expected an object"); return
        }
        #expect(members.map(\.key) == ["a", "bb"])
        #expect(members[0].keySpan == SourceSpan(start: 1, end: 4))
        #expect(members[0].node.span == SourceSpan(start: 6, end: 7))
        #expect(members[1].keySpan == SourceSpan(start: 9, end: 13))
        #expect(members[1].node.span == SourceSpan(start: 15, end: 19))
        // Key through value — what "copy this property" takes.
        #expect(members[1].span == SourceSpan(start: 9, end: 19))
    }

    @Test("a container span runs from its opening to its closing delimiter, inclusive")
    func containerSpans() {
        let source = "{\"a\": [1, 2]}"
        let result = parse(source)
        #expect(result.isValid)
        #expect(result.tree?.span == SourceSpan(start: 0, end: 13))
        #expect(result.tree?.value.member("a")?.node.span == SourceSpan(start: 6, end: 12))
    }

    @Test("empty containers parse with no members and a two-unit span")
    func emptyContainers() {
        #expect(parse("{}").tree?.value == .object([]))
        #expect(parse("[]").tree?.value == .array([]))
        #expect(parse("{}").tree?.span == SourceSpan(start: 0, end: 2))
        #expect(parse("[ ]").tree?.span == SourceSpan(start: 0, end: 3))
        #expect(parse("{}").isValid)
        #expect(parse("[]").isValid)
    }

    @Test("duplicate keys both survive — a dictionary would discard the evidence VA-10 needs")
    func duplicateKeys() {
        let result = parse("{\"a\": 1, \"a\": 2}")
        #expect(result.isValid, "duplicate keys are legal JSON; the warning is Phase 4's, not the parser's")
        #expect(result.tree?.value.members("a").count == 2)
        #expect(result.tree?.value.member("a")?.node.value == .number("1"))
    }

    @Test("a big integer keeps its source text rather than rounding through Double")
    func bigIntegerFidelity() {
        let result = parse("{\"id\": 9007199254740993}")
        #expect(result.isValid)
        #expect(result.tree?.value.member("id")?.node.value == .number("9007199254740993"))
        // The reason the text is stored at all: Double cannot represent this value.
        #expect(Double("9007199254740993") == 9007199254740992.0)
    }

    @Test("nesting resolves to the right depth and the innermost node at an offset")
    func nesting() {
        //                  0         1         2
        //                  012345678901234567890123
        let result = parse("{\"a\": {\"b\": [1, {\"c\": 2}]}}")
        #expect(result.isValid)
        // object → object → array → object → number, counting the root as 0.
        #expect(result.tree?.depth == 4)
        // Offset 22 is the `2` inside the innermost object.
        #expect(result.tree?.innermostNode(at: 22)?.value == .number("2"))
        // Offset 0 is the outer brace, so the innermost containing node is the root.
        #expect(result.tree?.innermostNode(at: 0)?.kind == .object)
    }

    @Test("the sample payload parses clean — every fixture in this project is that file")
    func samplePayload() throws {
        let result = parse(try sampleJSON())
        #expect(result.errors.isEmpty, "unexpected: \(result.errors.map(\.kind))")
        #expect(result.isValid)
        #expect(result.tree?.kind == .object)
    }

    @Test("the line index comes back with the result, so the UI never rescans the document")
    func lineIndexIsCarried() {
        let result = parse("{\n  \"a\": 1\n}")
        #expect(result.lineIndex.lineCount == 3)
        #expect(result.lineIndex.position(at: 6).line == 2)
    }
}

@Suite("Parser · the depth limit")
struct ParserDepthTests {

    private func nested(_ depth: Int) -> String {
        String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    }

    @Test("500 nested arrays parse — JSONTestSuite's i_structure_500_nested_arrays is accepted")
    func atFiveHundred() {
        let result = parse(nested(500))
        #expect(result.isValid)
        // 500 arrays, counting the outermost as 0.
        #expect(result.tree?.depth == 499)
    }

    // Every test in this file runs on a Swift concurrency thread, which is the point: that is
    // where the app parses (ADR-09) and it gets a 512 KB stack, not the main thread's 8 MB.
    // A recursive version of the parser died here at 96 levels of objects in a debug build.
    @Test("deep nesting survives the 512 KB stack a concurrency thread actually gets")
    func deepOnConcurrencyThread() {
        let objects = String(repeating: "{\"a\":", count: 500) + "1" + String(repeating: "}", count: 500)
        let result = parse(objects)
        #expect(result.isValid)
        #expect(result.tree?.depth == 500)
    }

    @Test("past the limit the parse is reported, once, and does not overflow the stack")
    func pastTheLimit() {
        let result = parse(nested(Parser.maxDepth + 50))
        #expect(result.kinds.filter { $0 == .nestingTooDeep }.count == 1,
                "one fact about the document, not one per level")
        #expect(result.tree != nil, "everything above the limit is still parsed")
        // The cause is the opener at the limit, and the copy names the limit, not a literal.
        #expect(result.firstError(.nestingTooDeep)?.context.limit == Parser.maxDepth)
        #expect(result.firstError(.nestingTooDeep)?.copy.title.contains("512") == true)
    }

    @Test("100,000 opening arrays terminate instead of crashing")
    func hostilePayload() {
        let result = parse(String(repeating: "[", count: 100_000))
        #expect(result.firstError(.nestingTooDeep) != nil)
        #expect(result.tree != nil)
    }
}
