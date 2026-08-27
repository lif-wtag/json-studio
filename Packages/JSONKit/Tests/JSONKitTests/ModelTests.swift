import Testing
@testable import JSONKit

// Phase 2, step 1: the model types. Spans assert exact offsets rather than shapes, because
// off-by-one span arithmetic is the failure mode that silently corrupts everything above.

@Suite("SourceSpan")
struct SourceSpanTests {

    @Test("half-open: start included, end excluded")
    func halfOpen() {
        let span = SourceSpan(start: 4, end: 7)
        #expect(span.length == 3)
        #expect(!span.isEmpty)
        #expect(span.contains(4))
        #expect(span.contains(6))
        #expect(!span.contains(7))   // exclusive
        #expect(!span.contains(3))
    }

    @Test("an empty span contains nothing but touches its own offset")
    func emptySpan() {
        let caret = SourceSpan.empty(at: 12)
        #expect(caret.isEmpty)
        #expect(caret.length == 0)
        #expect(!caret.contains(12))
        #expect(caret.touches(12))
    }

    @Test("touches accepts both boundaries, so a caret on a closing brace stays inside")
    func touchesBoundaries() {
        let span = SourceSpan(start: 10, end: 20)
        #expect(span.touches(10))
        #expect(span.touches(20))
        #expect(!span.touches(21))
        #expect(!span.contains(20))
    }

    @Test("overlap is symmetric and excludes mere adjacency")
    func overlap() {
        let a = SourceSpan(start: 0, end: 5)
        let b = SourceSpan(start: 3, end: 9)
        let adjacent = SourceSpan(start: 5, end: 8)

        #expect(a.overlaps(b))
        #expect(b.overlaps(a))
        #expect(!a.overlaps(adjacent))
        #expect(!adjacent.overlaps(a))
    }

    @Test("containment of a span, including self")
    func spanContainment() {
        let outer = SourceSpan(start: 0, end: 100)
        let inner = SourceSpan(start: 10, end: 20)

        #expect(outer.contains(inner))
        #expect(!inner.contains(outer))
        #expect(outer.contains(outer))
    }

    @Test("union spans the gap between two disjoint spans")
    func union() {
        let a = SourceSpan(start: 2, end: 4)
        let b = SourceSpan(start: 40, end: 44)
        #expect(a.union(b) == SourceSpan(start: 2, end: 44))
        #expect(a.union(b) == b.union(a))
    }

    @Test("clamping a disjoint span yields an empty span at the boundary, never nil")
    func clamping() {
        let limit = SourceSpan(start: 10, end: 20)

        #expect(SourceSpan(start: 5, end: 15).clamped(to: limit) == SourceSpan(start: 10, end: 15))
        #expect(SourceSpan(start: 15, end: 30).clamped(to: limit) == SourceSpan(start: 15, end: 20))
        #expect(SourceSpan(start: 0, end: 5).clamped(to: limit).isEmpty)
        #expect(SourceSpan(start: 30, end: 40).clamped(to: limit).isEmpty)
    }

    @Test("sorting gives document order, outermost first at a shared start")
    func ordering() {
        let outer = SourceSpan(start: 0, end: 50)
        let inner = SourceSpan(start: 0, end: 10)
        let later = SourceSpan(start: 20, end: 25)

        #expect([later, inner, outer].sorted() == [outer, inner, later])
    }
}

@Suite("LineIndex")
struct LineIndexTests {

    @Test("LF line breaks, 1-based positions")
    func lineFeed() {
        //          0123 4567 89
        let index = LineIndex(source: "abc\ndef\ngh")

        #expect(index.lineCount == 3)
        #expect(index.position(at: 0) == (line: 1, column: 1))
        #expect(index.position(at: 2) == (line: 1, column: 3))
        #expect(index.position(at: 4) == (line: 2, column: 1))
        #expect(index.position(at: 8) == (line: 3, column: 1))
        #expect(index.position(at: 9) == (line: 3, column: 2))
    }

    @Test("CRLF counts as ONE break — the Windows-payload off-by-one")
    func carriageReturnLineFeed() {
        //                        0123  4 5678
        let index = LineIndex(source: "abc\r\ndef")

        #expect(index.lineCount == 2)
        #expect(index.position(at: 3) == (line: 1, column: 4))   // the CR itself
        #expect(index.position(at: 5) == (line: 2, column: 1))   // 'd'
        #expect(index.position(at: 7) == (line: 2, column: 3))
    }

    @Test("a lone CR is a line break too")
    func loneCarriageReturn() {
        let index = LineIndex(source: "abc\rdef")

        #expect(index.lineCount == 2)
        #expect(index.position(at: 4) == (line: 2, column: 1))
    }

    @Test("a trailing newline does not invent an extra line")
    func trailingNewline() {
        #expect(LineIndex(source: "a\n").lineCount == 1)
        #expect(LineIndex(source: "a\nb\n").lineCount == 2)
        #expect(LineIndex(source: "").lineCount == 1)
    }

    @Test("offset(line:column:) round-trips against position(at:)")
    func roundTrip() {
        let source = "{\n  \"a\": 1,\n  \"b\": [2, 3]\n}\n"
        let index = LineIndex(source: source)

        for offset in 0...source.utf16.count {
            let p = index.position(at: offset)
            #expect(index.offset(line: p.line, column: p.column) == offset,
                    "offset \(offset) round-tripped through \(p)")
        }
    }

    @Test("out-of-range lookups clamp rather than trap")
    func clamping() {
        let index = LineIndex(source: "abc")

        #expect(index.position(at: -5) == (line: 1, column: 1))
        #expect(index.position(at: 999) == (line: 1, column: 4))
        #expect(index.offset(line: 0, column: 0) == 0)
        #expect(index.offset(line: 99, column: 99) == 3)
    }

    @Test("line spans include the terminator")
    func lineSpans() {
        let index = LineIndex(source: "ab\ncd")

        #expect(index.span(ofLine: 1) == SourceSpan(start: 0, end: 3))
        #expect(index.span(ofLine: 2) == SourceSpan(start: 3, end: 5))
        #expect(index.span(ofLine: 3) == nil)
    }

    @Test("astral-plane characters count as TWO UTF-16 units")
    func surrogatePairsAreTwoUnits() {
        // 🧊 is U+1F9CA — one Character, two UTF-16 code units. The fixture contains it.
        let source = "\"🧊\"\nnext"
        let index = LineIndex(source: source)

        #expect(source.utf16.count == 9)          // " + 2 + " + \n + next
        #expect(index.position(at: 5) == (line: 2, column: 1))
    }
}

@Suite("JSONValue and JSONNode")
struct ValueTests {

    /// `{"a": 1, "a": 2}` — a duplicate key, spans made up but internally consistent.
    private func duplicateKeyObject() -> JSONNode {
        JSONNode(
            value: .object([
                JSONMember(key: "a", keySpan: SourceSpan(start: 1, end: 4),
                           node: JSONNode(value: .number("1"), span: SourceSpan(start: 6, end: 7))),
                JSONMember(key: "a", keySpan: SourceSpan(start: 9, end: 12),
                           node: JSONNode(value: .number("2"), span: SourceSpan(start: 14, end: 15))),
            ]),
            span: SourceSpan(start: 0, end: 16)
        )
    }

    @Test("numbers compare by source text, so 1 and 1.0 differ")
    func numberIdentity() {
        #expect(JSONValue.number("1") != JSONValue.number("1.0"))
        #expect(JSONValue.number("9007199254740993") == JSONValue.number("9007199254740993"))
    }

    @Test("an integer beyond Double's range survives as text")
    func bigIntegerSurvives() {
        guard case .number(let text) = JSONValue.number("9007199254740993") else {
            Issue.record("expected a number"); return
        }
        #expect(text == "9007199254740993")

        // This is the whole reason .number stores a String. Double silently rounds the value
        // down to 9007199254740992; Int64 holds it exactly. A parser that eagerly produced
        // Double would corrupt the fixture and never say so.
        #expect(Double(text) == 9_007_199_254_740_992)
        #expect(Int64(text) == 9_007_199_254_740_993)
        #expect(String(Int64(text) ?? 0) == text)
    }

    @Test("objects preserve duplicate keys — a dictionary would lose the evidence")
    func duplicateKeysPreserved() {
        let node = duplicateKeyObject()

        #expect(node.value.childCount == 2)
        #expect(node.value.members("a").count == 2)
        #expect(node.value.member("a")?.node.value == .number("1"))   // first wins
    }

    @Test("kind, isContainer and childCount")
    func kinds() {
        #expect(JSONValue.object([]).kind == .object)
        #expect(JSONValue.array([]).kind == .array)
        #expect(JSONValue.string("x").kind == .string)
        #expect(JSONValue.number("1").kind == .number)
        #expect(JSONValue.bool(true).kind == .boolean)
        #expect(JSONValue.null.kind == .null)

        #expect(JSONValue.object([]).isContainer)
        #expect(JSONValue.array([]).isContainer)
        #expect(!JSONValue.null.isContainer)
        #expect(JSONValue.null.childCount == 0)
    }

    @Test("member span covers key through value")
    func memberSpan() {
        let member = JSONMember(
            key: "a", keySpan: SourceSpan(start: 1, end: 4),
            node: JSONNode(value: .number("1"), span: SourceSpan(start: 6, end: 7))
        )
        #expect(member.span == SourceSpan(start: 1, end: 7))
    }

    @Test("innermostNode(at:) finds the deepest containing node — the caret-to-tree primitive")
    func innermostNode() {
        let node = duplicateKeyObject()

        // Inside the first value.
        #expect(node.innermostNode(at: 6)?.value == .number("1"))
        // Inside the second value.
        #expect(node.innermostNode(at: 14)?.value == .number("2"))
        // Between members — no child contains it, so the object itself.
        #expect(node.innermostNode(at: 8)?.kind == .object)
        // Outside the document.
        #expect(node.innermostNode(at: 99) == nil)
    }

    @Test("a caret on the closing delimiter still resolves to the container")
    func caretOnClosingBrace() {
        let node = duplicateKeyObject()
        #expect(node.innermostNode(at: 16)?.kind == .object)
    }

    @Test("depth counts the deepest descendant")
    func depth() {
        let leaf = JSONNode(value: .number("1"), span: .empty(at: 0))
        #expect(leaf.depth == 0)

        let nested = JSONNode(
            value: .array([JSONNode(value: .array([leaf]), span: .empty(at: 0))]),
            span: .empty(at: 0)
        )
        #expect(nested.depth == 2)
    }
}

@Suite("ParseError")
struct ParseErrorTests {

    @Test("cause and detection are separate, and the copy names both")
    func causeVersusDetection() {
        // Missing comma: the fix belongs at the end of line 29; the parser noticed on line 30.
        let error = ParseError(
            kind: .missingComma,
            span: SourceSpan(start: 100, end: 100),
            detectedAt: SourceSpan(start: 140, end: 149),
            context: .init(nextLine: 30)
        )

        #expect(error.wasDetectedElsewhere)
        #expect(error.copy.title == "Add a comma after this value.")
        #expect(error.copy.body == "The next property starts on line 30 without one.")
    }

    @Test("an error detected at its cause reports no elsewhere")
    func detectedInPlace() {
        let error = ParseError(kind: .trailingComma, span: SourceSpan(start: 10, end: 11),
                               context: .init(closer: "}"))
        #expect(!error.wasDetectedElsewhere)
        #expect(error.copy.body == "JSON doesn't allow a comma before }.")
    }

    @Test("every kind produces copy that obeys the three rules")
    func everyKindHasUsableCopy() {
        for kind in ParseError.Kind.allCases {
            let error = ParseError(
                kind: kind,
                span: .empty(at: 0),
                context: .init(nextLine: 2, openLine: 1, endLine: 9, closer: "]",
                               characterName: "tab", escape: "\\t", found: "region",
                               numberProblem: .leadingZero)
            )
            let (title, body) = error.copy

            #expect(!title.isEmpty, "\(kind) has no title")
            #expect(!body.isEmpty, "\(kind) has no body")
            #expect(!title.contains("?"), "\(kind) title has an unfilled placeholder")
            #expect(!body.contains("?"), "\(kind) body has an unfilled placeholder")
            #expect(!title.contains("!"), "\(kind) title exclaims")
            // No apologising, per Design/error-copy.md.
            for word in ["Oops", "Sorry", "sorry", "unfortunately"] {
                #expect(!title.contains(word) && !body.contains(word), "\(kind) apologises")
            }
        }
    }

    @Test("invalidNumber has a distinct message per sub-case")
    func numberSubcases() {
        var seen = Set<String>()
        for problem in ParseError.NumberProblem.allCases {
            let error = ParseError(kind: .invalidNumber, span: .empty(at: 0),
                                   context: .init(found: "-", numberProblem: problem))
            seen.insert(error.copy.title + "|" + error.copy.body)
        }
        #expect(seen.count == ParseError.NumberProblem.allCases.count,
                "sub-cases must not share a message")
    }

    @Test("unterminated string distinguishes end-of-document from end-of-line")
    func unterminatedVariants() {
        let onLine = ParseError(kind: .unterminatedString, span: .empty(at: 0),
                                context: .init(openLine: 12))
        let toEOF = ParseError(kind: .unterminatedString, span: .empty(at: 0),
                               context: .init(openLine: 12, endLine: 40))

        #expect(onLine.copy.body.contains("end of line 12"))
        #expect(toEOF.copy.body.contains("end of the document"))
        #expect(onLine.copy.body != toEOF.copy.body)
    }

    @Test("status summary matches the specified shapes")
    func statusSummary() {
        #expect(ParseErrorCopy.statusSummary(errorCount: 0, firstLine: nil, firstColumn: nil)
                == "Valid JSON")
        #expect(ParseErrorCopy.statusSummary(errorCount: 1, firstLine: 42, firstColumn: 18)
                == "1 error · line 42, column 18")
        #expect(ParseErrorCopy.statusSummary(errorCount: 9, firstLine: 29, firstColumn: 30)
                == "9 errors · first on line 29")
    }

    @Test("byte size renders the {size} placeholder the status bar and the CLI both use")
    func byteSize() {
        // Binary units under decimal labels — what the artboard's `3.7 KB` was measured as. The
        // fixture is 3,771 bytes, which is 3.7 KB binary and 3.8 KB decimal, so getting this wrong
        // makes the app and the CLI disagree about the one document every mockup uses.
        #expect(ParseErrorCopy.byteSize(3771) == "3.7 KB")
        #expect(ParseErrorCopy.byteSize(0) == "0 B")
        #expect(ParseErrorCopy.byteSize(1) == "1 B")
        #expect(ParseErrorCopy.byteSize(1023) == "1023 B")
        #expect(ParseErrorCopy.byteSize(1024) == "1.0 KB")
        #expect(ParseErrorCopy.byteSize(1024 * 1024 * 3) == "3.0 MB")
        #expect(ParseErrorCopy.byteSize(1024 * 1024 * 1024) == "1.0 GB")
        // The largest unit saturates rather than inventing a PB label.
        #expect(ParseErrorCopy.byteSize(1024 * 1024 * 1024 * 1024 * 2) == "2.0 TB")
    }

    @Test("control characters are named, never rendered")
    func controlCharacterNames() {
        #expect(ParseErrorCopy.characterName(forUTF16: 0x0009) == (name: "tab", escape: "\\t"))
        #expect(ParseErrorCopy.characterName(forUTF16: 0x000A) == (name: "newline", escape: "\\n"))

        let obscure = ParseErrorCopy.characterName(forUTF16: 0x0001)
        #expect(obscure.escape == "\\u0001")
        #expect(obscure.name == "control character")
    }
}
