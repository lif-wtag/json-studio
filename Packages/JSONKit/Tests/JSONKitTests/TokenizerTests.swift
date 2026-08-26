import Testing
@testable import JSONKit

// Phase 2, step 2. Spans assert exact offsets throughout: a tokenizer that classifies correctly
// but reports spans one unit out corrupts every feature above it, silently.

private func tokenize(_ source: String) -> Tokenizer.Result {
    Tokenizer().tokenize(source)
}

/// Kinds only, with the trailing `.endOfInput` dropped — for tests about shape rather than spans.
private func kinds(_ source: String) -> [Token.Kind] {
    tokenize(source).tokens.dropLast().map(\.kind)
}

@Suite("Tokenizer · structure")
struct TokenizerStructureTests {

    @Test("the six structural characters, with exact one-unit spans")
    func structural() {
        let result = tokenize("{}[],:")
        #expect(result.errors.isEmpty)
        #expect(result.tokens.map(\.kind) == [
            .beginObject, .endObject, .beginArray, .endArray, .comma, .colon, .endOfInput,
        ])
        for (i, token) in result.tokens.dropLast().enumerated() {
            #expect(token.span == SourceSpan(start: i, end: i + 1))
        }
    }

    @Test("endOfInput is always last and is a zero-width span at the end")
    func endOfInput() {
        for source in ["", "  ", "{}", "\"a\""] {
            let tokens = tokenize(source).tokens
            #expect(tokens.last?.kind == .endOfInput)
            #expect(tokens.last?.span == SourceSpan.empty(at: source.utf16.count))
        }
    }

    @Test("only RFC 8259 whitespace is skipped — a non-breaking space is not whitespace")
    func whitespace() {
        #expect(tokenize(" \t\r\n{} ").errors.isEmpty)
        #expect(kinds(" \t\r\n{} ") == [.beginObject, .endObject])

        // U+00A0. Legal in a string, never between tokens.
        let nbsp = tokenize("{\u{00A0}}")
        #expect(nbsp.tokens.map(\.kind) == [.beginObject, .invalid, .endObject, .endOfInput])
    }

    @Test("the three literals, and near-misses that are not literals")
    func literals() {
        #expect(kinds("true false null") == [.literalTrue, .literalFalse, .literalNull])
        // Case matters, and a prefix is not a literal.
        #expect(kinds("True nul nullish") == [.identifier, .identifier, .identifier])
        #expect(tokenize("True").tokens[0].stringValue == "True")
    }

    @Test("a bare word becomes an identifier with NO error — only the parser knows what it means")
    func bareWordIsNotAnError() {
        let result = tokenize("{region: 1}")
        #expect(result.errors.isEmpty, "the tokenizer must not guess that this is an unquoted key")
        #expect(result.tokens[1].kind == .identifier)
        #expect(result.tokens[1].stringValue == "region")
        #expect(result.tokens[1].span == SourceSpan(start: 1, end: 7))
    }

    @Test("an unclassifiable character consumes exactly one unit, so scanning always progresses")
    func alwaysProgresses() {
        let result = tokenize("@#$")
        #expect(result.tokens.map(\.kind) == [.invalid, .invalid, .invalid, .endOfInput])
        #expect(result.tokens[0].span == SourceSpan(start: 0, end: 1))
        #expect(result.tokens[2].span == SourceSpan(start: 2, end: 3))
    }

    @Test("canBeginValue marks exactly the value-starting kinds")
    func canBeginValue() {
        // Hoisted out of #expect: the macro decomposes a call like `allSatisfy(_:)` and its
        // rethrows analysis then rejects the closure.
        let starts = tokenize("{ [ \"s\" 1 true false null").tokens.dropLast()
        let everyStartCanBeginValue = starts.allSatisfy { $0.canBeginValue }
        #expect(everyStartCanBeginValue)

        let notStarts = tokenize("} ] : ,").tokens.dropLast()
        let noneCanBeginValue = notStarts.allSatisfy { !$0.canBeginValue }
        #expect(noneCanBeginValue)
    }
}

@Suite("Tokenizer · strings")
struct TokenizerStringTests {

    @Test("a plain string: span includes both quotes, payload excludes them")
    func plainString() {
        let result = tokenize("\"abc\"")
        #expect(result.errors.isEmpty)
        #expect(result.tokens[0].kind == .string)
        #expect(result.tokens[0].span == SourceSpan(start: 0, end: 5))
        #expect(result.tokens[0].stringValue == "abc")
    }

    @Test("every two-character escape decodes")
    func simpleEscapes() {
        let result = tokenize(#""a\"b\\c\/d\be\ff\ng\rh\ti""#)
        #expect(result.errors.isEmpty)
        #expect(result.tokens[0].stringValue == "a\"b\\c/d\u{08}e\u{0C}f\ng\rh\ti")
    }

    @Test("\\u decodes, and a surrogate pair becomes one character")
    func unicodeEscapes() {
        #expect(tokenize(#""\u00e9""#).tokens[0].stringValue == "é")
        #expect(tokenize(#""\u0041\u0042""#).tokens[0].stringValue == "AB")

        // U+1F9CA — the fixture's 🧊, written as a surrogate pair.
        let pair = tokenize(#""\uD83E\uDDCA""#)
        #expect(pair.errors.isEmpty)
        #expect(pair.tokens[0].stringValue == "🧊")
        #expect(pair.tokens[0].stringValue?.count == 1, "one Character, not two")
    }

    @Test("a lone high surrogate is reported and replaced, not silently kept")
    func loneHighSurrogate() {
        let result = tokenize(#""\uD83E""#)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].kind == .loneSurrogate)
        #expect(result.errors[0].span == SourceSpan(start: 1, end: 7))
        #expect(result.tokens[0].stringValue == "\u{FFFD}")
    }

    @Test("a lone LOW surrogate is reported too")
    func loneLowSurrogate() {
        let result = tokenize(#""\uDDCA""#)
        #expect(result.errors.map(\.kind) == [.loneSurrogate])
        #expect(result.tokens[0].stringValue == "\u{FFFD}")
    }

    @Test("a high surrogate then an ordinary escape: lone surrogate, and the escape still decodes")
    func highSurrogateThenOrdinaryEscape() {
        let result = tokenize(#""\uD83E\u0041""#)
        #expect(result.errors.map(\.kind) == [.loneSurrogate])
        #expect(result.tokens[0].stringValue == "\u{FFFD}A")
    }

    @Test("a short \\u escape is invalidUnicodeEscape, not loneSurrogate")
    func shortUnicodeEscape() {
        let result = tokenize(#""\u12""#)
        #expect(result.errors.map(\.kind) == [.invalidUnicodeEscape])
        #expect(result.tokens[0].kind == .string)
    }

    @Test("an unknown escape gets its own error — the 13th kind, added for exactly this")
    func unknownEscape() {
        let result = tokenize(#""a\xb""#)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].kind == .invalidEscape)
        #expect(result.errors[0].context.found == "x")
        // Cause covers the backslash and the character, which is what gets deleted.
        #expect(result.errors[0].span == SourceSpan(start: 2, end: 4))
        // The backslash is dropped and the character kept: `\x` almost always meant a literal x.
        #expect(result.tokens[0].stringValue == "axb")
        #expect(result.errors[0].copy.title == "Remove this backslash, or finish the escape.")
    }

    @Test("a raw control character is reported by NAME and kept in the value")
    func controlCharacter() {
        let result = tokenize("\"a\tb\"")
        #expect(result.errors.map(\.kind) == [.controlCharacterInString])
        #expect(result.errors[0].context.characterName == "tab")
        #expect(result.errors[0].context.escape == "\\t")
        #expect(result.errors[0].span == SourceSpan(start: 2, end: 3))
        #expect(result.tokens[0].stringValue == "a\tb", "the tree should show what is actually there")
    }

    @Test("unterminated at a newline: cause is the OPENING quote, and the next line still tokenizes")
    func unterminatedAtNewline() {
        //             0123456 7 89
        let result = tokenize("\"abc\n{}")
        #expect(result.errors.count == 1)
        let error = result.errors[0]
        #expect(error.kind == .unterminatedString)
        #expect(error.span == SourceSpan(start: 0, end: 1), "cause = the opening quote")
        #expect(error.detectedAt?.start == 4, "noticed at the newline")
        #expect(error.wasDetectedElsewhere)
        #expect(error.context.openLine == 1)
        #expect(error.context.endLine == nil, "did not reach end of document")

        // The critical recovery property: line 2 is not swallowed.
        #expect(result.tokens.map(\.kind) == [.string, .beginObject, .endObject, .endOfInput])
    }

    @Test("unterminated at end of document reports the other variant")
    func unterminatedAtEOF() throws {
        let result = tokenize("{\"a\": \"oops")
        let error = try #require(result.errors.first)
        #expect(error.kind == .unterminatedString)
        #expect(error.context.endLine != nil)
        #expect(error.copy.body.contains("end of the document"))
    }

    @Test("single quotes get their own diagnosis, and the content still decodes")
    func singleQuoted() {
        let result = tokenize("'abc'")
        #expect(result.errors.map(\.kind) == [.singleQuotedString])
        #expect(result.errors[0].span == SourceSpan(start: 0, end: 1))
        #expect(result.tokens[0].kind == .string)
        #expect(result.tokens[0].stringValue == "abc")
        #expect(result.errors[0].copy.title == "Use double quotes here.")
    }

    @Test("astral characters written literally span TWO code units")
    func literalAstralCharacter() {
        let result = tokenize("\"🧊\"")
        #expect(result.errors.isEmpty)
        #expect(result.tokens[0].span == SourceSpan(start: 0, end: 4), "quote + 2 units + quote")
        #expect(result.tokens[0].stringValue == "🧊")
    }
}

@Suite("Tokenizer · numbers")
struct TokenizerNumberTests {

    @Test("valid numbers per RFC 8259, source text preserved exactly")
    func validNumbers() {
        for source in ["0", "-0", "1", "42", "-17", "0.5", "-3.25", "1e10", "1E10",
                       "1e+10", "1e-10", "-2.5E-3", "9007199254740993", "1e308"] {
            let result = tokenize(source)
            #expect(result.errors.isEmpty, "\(source) should be valid")
            #expect(result.tokens[0].kind == .number, "\(source)")
            #expect(result.tokens[0].numberText == source, "\(source) must round-trip as text")
        }
    }

    @Test("the big integer keeps its digits — the reason numbers are stored as text")
    func bigInteger() {
        let result = tokenize("9007199254740993")
        #expect(result.tokens[0].numberText == "9007199254740993")
        #expect(Double(result.tokens[0].numberText ?? "") == 9_007_199_254_740_992,
                "Double would have lost it")
    }

    @Test("each grammar violation is reported as its own sub-case")
    func invalidNumbers() {
        let cases: [(String, ParseError.NumberProblem)] = [
            ("01", .leadingZero),
            ("00", .leadingZero),
            ("1.", .trailingDecimalPoint),
            ("-", .missingDigits),
            ("1e", .missingDigits),
            ("1e+", .missingDigits),
        ]
        for (source, expected) in cases {
            let result = tokenize(source)
            #expect(result.errors.count == 1, "\(source): expected one error")
            #expect(result.errors.first?.kind == .invalidNumber, "\(source)")
            #expect(result.errors.first?.context.numberProblem == expected, "\(source)")
            #expect(result.tokens[0].kind == .number, "\(source): still emits a token")
            #expect(result.tokens[0].numberText == source, "\(source): text preserved")
        }
    }

    @Test("a leading decimal point is its own sub-case, distinct from a trailing one")
    func leadingDecimalPoint() {
        let result = tokenize("[.5]")
        #expect(result.errors.map(\.kind) == [.invalidNumber])
        #expect(result.errors[0].context.numberProblem == .leadingDecimalPoint)
        #expect(result.errors[0].copy.body.contains("0.5"))
    }

    @Test("trailing junk is folded into the malformed number rather than split into tokens")
    func trailingJunk() {
        let result = tokenize("0x1F")
        #expect(result.errors.map(\.kind) == [.invalidNumber])
        #expect(result.tokens.map(\.kind) == [.number, .endOfInput],
                "one bad number, not a number plus an identifier")
        #expect(result.tokens[0].numberText == "0x1F")
        #expect(result.tokens[0].span == SourceSpan(start: 0, end: 4))
    }

    @Test("`{found}` in an error is truncated so a long run can't swamp the message")
    func foundIsTruncated() throws {
        let result = tokenize("1" + String(repeating: "z", count: 200))
        let found = try #require(result.errors.first?.context.found)
        #expect(found.count <= 25)
        #expect(found.hasSuffix("…"))
    }

    @Test("numbers inside a structure get correct spans")
    func numberSpans() {
        //                     0123456789
        let result = tokenize("[1, 22, 3]")
        let numbers = result.tokens.filter { $0.kind == .number }
        #expect(numbers.map(\.span) == [
            SourceSpan(start: 1, end: 2),
            SourceSpan(start: 4, end: 6),
            SourceSpan(start: 8, end: 9),
        ])
    }
}

@Suite("Tokenizer · the real fixture")
struct TokenizerFixtureTests {

    /// A representative slice of `Design/sample-payload.json`: deep nesting, a German string,
    /// unicode, an emoji, nulls, and the unsafe integer.
    private let fixture = """
        {
          "schemaVersion": "2026-08",
          "account": {
            "externalId": 9007199254740993,
            "note": "Wichtiger Hinweis für den Betrieb — bitte prüfen.",
            "tags": ["priority", "verträge-2026"],
            "billing": null
          },
          "devices": [
            { "id": "dev-001", "battery": 0.87, "online": true },
            { "id": "dev-002", "label": "Kühlraum B — 冷蔵室 🧊", "battery": null }
          ],
          "summary": { "negativeZero": -0, "exp": 6.022e23, "empty": {}, "emptyList": [] }
        }
        """

    @Test("the fixture tokenizes with zero errors")
    func noErrors() {
        let result = tokenize(fixture)
        #expect(result.errors.isEmpty, "unexpected: \(result.errors.map(\.kind))")
    }

    @Test("every token's span slices back to text consistent with its kind")
    func spansSliceCorrectly() {
        let units = Array(fixture.utf16)
        for token in tokenize(fixture).tokens where token.kind != .endOfInput {
            let slice = String(decoding: units[token.span.start..<token.span.end], as: UTF16.self)
            switch token.kind {
            case .string:
                #expect(slice.hasPrefix("\"") && slice.hasSuffix("\""), "string span: \(slice)")
            case .number:
                #expect(slice == token.numberText, "number span: \(slice)")
            case .beginObject: #expect(slice == "{")
            case .endObject:   #expect(slice == "}")
            case .beginArray:  #expect(slice == "[")
            case .endArray:    #expect(slice == "]")
            case .colon:       #expect(slice == ":")
            case .comma:       #expect(slice == ",")
            case .literalTrue: #expect(slice == "true")
            case .literalNull: #expect(slice == "null")
            default: break
            }
        }
    }

    @Test("spans are strictly ordered and never overlap")
    func spansAreOrdered() {
        let tokens = tokenize(fixture).tokens
        for (a, b) in zip(tokens, tokens.dropFirst()) {
            #expect(a.span.end <= b.span.start, "\(a.kind) then \(b.kind) overlap")
        }
    }

    @Test("the unsafe integer and the German string survive")
    func awkwardValuesSurvive() {
        let tokens = tokenize(fixture).tokens
        #expect(tokens.contains { $0.numberText == "9007199254740993" })
        #expect(tokens.contains { $0.stringValue == "Wichtiger Hinweis für den Betrieb — bitte prüfen." })
        #expect(tokens.contains { $0.stringValue == "Kühlraum B — 冷蔵室 🧊" })
        #expect(tokens.contains { $0.numberText == "-0" }, "negative zero is a distinct literal")
    }

    @Test("the line index built during the same pass agrees with the token spans")
    func lineIndexAgrees() throws {
        let result = tokenize(fixture)
        let firstKey = try #require(result.tokens.first { $0.stringValue == "schemaVersion" })
        #expect(result.lineIndex.position(at: firstKey.span.start).line == 2)
    }
}

@Suite("Tokenizer · robustness")
struct TokenizerRobustnessTests {

    @Test("every truncation of the fixture terminates and always ends with endOfInput")
    func truncationsTerminate() {
        let source = """
            {"a": [1, "two \\u00e9", {"b": null}], "c": -3.5e2, 'd': True, "e": "x\\ty"}
            """
        for length in 0...source.utf16.count {
            let prefix = String(decoding: Array(source.utf16)[0..<length], as: UTF16.self)
            let result = tokenize(prefix)
            #expect(result.tokens.last?.kind == .endOfInput, "truncation at \(length)")
            // Progress guarantee: no token may be zero-width except endOfInput.
            for token in result.tokens.dropLast() {
                #expect(!token.span.isEmpty, "zero-width \(token.kind) at \(length)")
            }
        }
    }

    @Test("spans never exceed the source length, on any truncation")
    func spansStayInBounds() {
        let source = "{\"k\": \"\\uD83E\\uDDCA\", \"n\": 1e, \"bad\": \"\\q\"}"
        for length in 0...source.utf16.count {
            let prefix = String(decoding: Array(source.utf16)[0..<length], as: UTF16.self)
            let n = prefix.utf16.count
            for token in tokenize(prefix).tokens {
                #expect(token.span.end <= n, "span \(token.span) exceeds \(n) at \(length)")
            }
            for error in tokenize(prefix).errors {
                #expect(error.span.end <= n, "error span \(error.span) exceeds \(n) at \(length)")
            }
        }
    }

    @Test("a badly broken document still yields tokens AND multiple errors")
    func multipleErrorsAtOnce() {
        let result = tokenize("{'a': 01, \"b\": \"x\\qy\", \"c\": \"unclosed\n}")
        #expect(result.errors.count >= 4, "got \(result.errors.map(\.kind))")
        #expect(result.errors.contains { $0.kind == .singleQuotedString })
        #expect(result.errors.contains { $0.kind == .invalidNumber })
        #expect(result.errors.contains { $0.kind == .invalidEscape })
        #expect(result.errors.contains { $0.kind == .unterminatedString })
        #expect(result.tokens.count > 8, "recovery kept producing tokens")
    }

    @Test("errors are in source order, so 'first error' means the earliest one")
    func errorsAreOrdered() {
        let result = tokenize("{'a': 01, \"b\": \"x\\qy\"}")
        let starts = result.errors.map(\.span.start)
        #expect(starts == starts.sorted())
    }
}
