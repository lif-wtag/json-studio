import Testing
@testable import JSONKit

// Phase 2, step 3. **This is the suite that tests the product.** Phase 0 found that every
// competing tool reports where its parser noticed a problem rather than where the problem is;
// these tests assert the opposite for each error that has a cause distinct from its detection.
// A parser that classified every error correctly but attributed it to the detection point would
// pass ParserTests and fail here — and would be worth nothing.

@Suite("Parser · cause vs detection")
struct ParserAttributionTests {

    @Test("a missing comma is reported after the completed value, not at the next property")
    func missingCommaInObject() {
        //             0        1          2
        //             1234567890123456789012
        let source = "{\n  \"a\": 1\n  \"b\": 2\n}"
        let result = parse(source)
        let error = try? #require(result.firstError(.missingComma))
        guard let error else { return }

        // The cause is the insertion point immediately after `1`, on line 2 — where the comma
        // goes. Not line 3, where the parser found out.
        #expect(error.span.isEmpty)
        #expect(result.lineIndex.position(at: error.span.start).line == 2)
        #expect(result.lineIndex.position(at: error.detectedAt?.start ?? -1).line == 3)
        #expect(error.wasDetectedElsewhere)

        // And the copy names both positions, which is the whole point.
        #expect(error.copy.title == "Add a comma after this value.")
        #expect(error.copy.body == "The next property starts on line 3 without one.")
    }

    @Test("the array wording says element, not property")
    func missingCommaInArray() {
        let result = parse("[\n  1\n  2\n]")
        let error = try? #require(result.firstError(.missingComma))
        #expect(error?.context.container == .array)
        #expect(error?.copy.title == "Add a comma after this element.")
        #expect(error?.copy.body == "The next element starts on line 3 without one.")
    }

    @Test("an unclosed object is reported at its opening brace, never at EOF")
    func unclosedObjectPointsAtTheBrace() {
        //             0         1
        //             0123456789012345
        let source = "{\n  \"a\": {\n    \"b\": 1\n"
        let result = parse(source)
        let errors = result.errors.filter { $0.kind == .missingClosingBrace }
        #expect(errors.count == 2, "both open braces are unmatched")

        // Sorted in cause order, so the outer brace comes first — offset 0, line 1.
        #expect(errors[0].span == SourceSpan(start: 0, end: 1))
        #expect(errors[0].context.openLine == 1)
        #expect(errors[0].copy.body == "Add } to match the { on line 1.")

        // The inner one names its own line, and both were detected at EOF, which alone would
        // tell the reader nothing in a 4,000-line file.
        #expect(errors[1].context.openLine == 2)
        #expect(errors[1].copy.body == "Add } to match the { on line 2.")
        for error in errors {
            #expect(error.detectedAt?.start == source.utf16.count)
            #expect(error.wasDetectedElsewhere)
        }
    }

    @Test("a closer for the wrong container blames the opener that never closed")
    func mismatchedCloser() {
        //             0         1
        //             01234567890
        let result = parse("{\"a\": [1}")
        // The `[` is what never closes; the `}` legitimately closes the object.
        #expect(result.kinds == [.missingClosingBracket])
        #expect(result.errors[0].span == SourceSpan(start: 6, end: 7))
        #expect(result.errors[0].context.openLine == 1)
        // And the tree is intact either side of it.
        #expect(result.tree?.value.member("a")?.node.kind == .array)
    }

    @Test("a trailing comma blames the comma — that is the character deleted")
    func trailingComma() {
        //             0123456789
        let result = parse("{\"a\": 1,}")
        let error = try? #require(result.firstError(.trailingComma))
        #expect(error?.span == SourceSpan(start: 7, end: 8))
        #expect(error?.detectedAt == SourceSpan(start: 8, end: 9))
        #expect(error?.copy.body == "JSON doesn't allow a comma before }.")

        let array = parse("[1, 2, ]")
        #expect(array.firstError(.trailingComma)?.copy.body
                == "JSON doesn't allow a comma before ].")
    }

    @Test("a missing colon is reported at the end of the key")
    func missingColon() {
        //             01234567
        let result = parse("{\"ab\" 1}")
        let error = try? #require(result.firstError(.missingColon))
        #expect(error?.span == SourceSpan.empty(at: 5), "right after the closing quote of the key")
        #expect(error?.detectedAt == SourceSpan(start: 6, end: 7))
        #expect(error?.copy.title == "Add a colon after this key.")
        // Recovery assumes the colon was simply omitted, so the member still lands in the tree.
        #expect(result.tree?.value.member("ab")?.node.value == .number("1"))
    }

    @Test("an unquoted key names the key and keeps its text — cause and detection coincide")
    func unquotedKey() {
        let result = parse("{region: \"eu-central-1\"}")
        let error = try? #require(result.firstError(.unquotedKey))
        #expect(error?.span == SourceSpan(start: 1, end: 7))
        #expect(error?.detectedAt == nil)
        #expect(error?.wasDetectedElsewhere == false)
        #expect(error?.copy.title == "Put double quotes around region.")
        // The fix is unambiguous — add quotes — so the key is accepted into the tree.
        #expect(result.tree?.value.member("region")?.node.value == .string("eu-central-1"))
    }

    @Test("a numeric key is an unquoted key too, because the fix is still just quotes")
    func numericKey() {
        let result = parse("{1: true}")
        #expect(result.firstError(.unquotedKey)?.copy.title == "Put double quotes around 1.")
        #expect(result.tree?.value.member("1")?.node.value == .bool(true))
    }

    @Test("content after the top-level value names the line the document ended on")
    func trailingContent() {
        let result = parse("{\"a\": 1}\n{\"b\": 2}")
        let error = try? #require(result.firstError(.trailingContent))
        #expect(error?.span.start == 9, "the first token of the second payload")
        #expect(error?.copy.title == "The document already ended on line 1.")
        #expect(error?.copy.body == "Remove this, or wrap both values in an array.")
        // Reported once for the whole run, not once per token.
        #expect(result.kinds.filter { $0 == .trailingContent }.count == 1)
        #expect(result.tree?.value.member("a") != nil, "the first payload still parsed")
    }

    @Test("a missing value points at the insertion point, and the wording differs by container")
    func missingValue() {
        //             01234567
        let object = parse("{\"a\": }")
        let objectError = try? #require(object.firstError(.missingValue))
        #expect(objectError?.span == SourceSpan.empty(at: 5), "just after the colon")
        #expect(objectError?.context.container == .object)
        #expect(objectError?.copy.title == "Add a value after the colon.")

        let array = parse("[1, , 2]")
        let arrayError = try? #require(array.firstError(.missingValue))
        #expect(arrayError?.context.container == .array)
        #expect(arrayError?.copy.title == "Add a value, or remove the comma.")
        // Recovery keeps going: both real elements are in the tree.
        #expect(array.tree?.value.childCount == 2)
    }

    @Test("a Python or JavaScript literal is named, not repaired")
    func invalidLiteral() {
        for (source, found) in [("[True]", "True"), ("[NaN]", "NaN"), ("[undefined]", "undefined")] {
            let result = parse(source)
            let error = try? #require(result.firstError(.invalidLiteral))
            #expect(error?.copy.title == "Replace \(found) with a JSON value.")
            #expect(error?.context.expectation == .value)
            // Deliberately NOT guessed at: `True` is as likely to have meant the string "True".
            #expect(result.tree?.value.childCount == 0)
        }
    }

    @Test("a brace where a key belongs is an invalid literal, not an unquoted key")
    func invalidLiteralInKeyPosition() {
        let result = parse("{[1]: 2}")
        let error = try? #require(result.firstError(.invalidLiteral))
        #expect(error?.context.expectation == .key)
        #expect(error?.copy.title == "Replace [ with a quoted key.")
    }

    @Test("single quotes come from the tokenizer and still yield a usable string")
    func singleQuotes() {
        let result = parse("{'a': 1}")
        #expect(result.firstError(.singleQuotedString)?.copy.title == "Use double quotes here.")
        #expect(result.tree?.value.member("a")?.node.value == .number("1"))
    }

    @Test("errors come back in cause order, so the status bar's 'first error' is the first one")
    func causeOrder() {
        // The unclosed brace is discovered last, at EOF, but caused first, at offset 0.
        let result = parse("{\"a\": 1 \"b\": 2")
        #expect(result.kinds == [.missingClosingBrace, .missingComma])
        let starts = result.errors.map(\.span.start)
        #expect(starts == starts.sorted())
    }
}
