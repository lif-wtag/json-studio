import Testing
@testable import JSONKit

// Phase 2, step 5. Two things are being tested and they are not the same:
//
//  1. **Fidelity** — formatting must not change what the document *says*. Escapes, big
//     integers and `1.0` survive byte-for-byte because scalars are re-emitted from their spans.
//  2. **Layout** — the inline-or-break decision, which is checked against the approved artboard
//     rather than against taste.

private func formatted(_ source: String, _ options: FormatOptions = .pretty) -> String {
    guard let tree = Parser().parse(source).tree else { return "" }
    return Formatter(options: options).format(tree, source: source)
}

/// Every line of a formatted document, for layout assertions.
private func lines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

@Suite("Formatter · fidelity")
struct FormatterFidelityTests {

    @Test("a formatted document reparses to the same structure")
    func roundTrips() throws {
        let source = try sampleJSON()
        let original = Parser().parse(source)
        try #require(original.isValid)

        for options: FormatOptions in [.pretty, .uniform, .minified,
                                       FormatOptions(indent: .spaces(4)),
                                       FormatOptions(indent: .tab)] {
            let out = Formatter(options: options).format(try #require(original.tree), source: source)
            let reparsed = Parser().parse(out)
            #expect(reparsed.isValid, "output did not reparse")
            // Compare rendered paths and scalar values — not `==`, which includes spans and so
            // is guaranteed to differ once the text has moved.
            #expect(shape(try #require(reparsed.tree)) == shape(try #require(original.tree)))
        }
    }

    /// Structural fingerprint, offsets excluded. See `SpanAccuracyTests` for why `==` won't do.
    private func shape(_ node: JSONNode, path: String = "$") -> [String] {
        switch node.value {
        case .object(let members):
            return ["\(path):object"] + members.flatMap { shape($0.node, path: "\(path).\($0.key)") }
        case .array(let elements):
            return ["\(path):array"] + elements.enumerated().flatMap { shape($1, path: "\(path)[\($0)]") }
        case .string(let v): return ["\(path):string=\(v)"]
        case .number(let t): return ["\(path):number=\(t)"]
        case .bool(let v): return ["\(path):bool=\(v)"]
        case .null: return ["\(path):null"]
        }
    }

    @Test("escapes are re-emitted exactly as written, not re-encoded")
    func escapesSurvive() {
        // Each of these decodes to something a re-encoder would spell differently.
        let source = #"{"a":"café","b":"a\/b","c":"🧊","d":"tab\there"}"#
        let out = formatted(source, .minified)
        #expect(out.contains(#"é"#), "an escaped é must not become a literal é")
        #expect(out.contains(#"a\/b"#), "an escaped solidus must not become a bare /")
        #expect(out.contains(#"🧊"#), "a surrogate pair must not become the character")
        #expect(out.contains(#"tab\there"#))
    }

    @Test("numbers keep their source text — the reason .number stores a String")
    func numbersSurvive() {
        let source = #"{"big":9007199254740993,"float":1.0,"neg":-0,"exp":1.2e+10,"zero":0}"#
        let out = formatted(source, .minified)
        #expect(out.contains("9007199254740993"), "must not round through Double")
        #expect(out.contains("1.0"), "1.0 must not become 1")
        #expect(out.contains("-0"), "-0 must not become 0")
        #expect(out.contains("1.2e+10"))
    }

    @Test("keys keep their order and their duplicates")
    func keyOrderAndDuplicates() {
        let out = formatted(#"{"z":1,"a":2,"z":3}"#, .minified)
        #expect(out == #"{"z":1,"a":2,"z":3}"#, "sorting is FM-06's job, not Format's")
    }

    @Test("formatting is idempotent")
    func idempotent() throws {
        let source = try sampleJSON()
        for options: FormatOptions in [.pretty, .uniform, .minified, FormatOptions(indent: .tab)] {
            let once = Formatter(options: options).format(
                try #require(Parser().parse(source).tree), source: source)
            let twice = Formatter(options: options).format(
                try #require(Parser().parse(once).tree), source: once)
            #expect(twice == once, "second pass changed the output")
        }
    }

    @Test("a recovered tree still formats to VALID JSON")
    func recoveredTreeFormatsValid() {
        // The string's span has no closing quote, so copying it out verbatim would propagate the
        // break. The literal writer checks the slice and falls back to encoding the decoded value.
        let broken = "{\n  \"a\": \"oops,\n  \"b\": 2\n}"
        let result = Parser().parse(broken)
        #expect(!result.errors.isEmpty)
        guard let tree = result.tree else { Issue.record("no tree"); return }

        let out = Formatter(options: .minified).format(tree, source: broken)
        #expect(Parser().parse(out).isValid, "formatter emitted invalid JSON: \(out)")
    }

    @Test("an empty document formats to nil, not to an empty string")
    func emptyDocument() {
        let result = Parser().parse("   ")
        #expect(result.isEmpty)
        // Returning "" here would let a caller save an empty file over their document.
        #expect(Formatter().format(result, source: "   ") == nil)
    }
}

@Suite("Formatter · layout")
struct FormatterLayoutTests {

    @Test("minify emits the compact legal form")
    func minify() {
        #expect(formatted(#"{ "a" : 1 , "b" : [ 1 , 2 ] }"#, .minified) == #"{"a":1,"b":[1,2]}"#)
        #expect(formatted("{}", .minified) == "{}")
        #expect(formatted("[]", .minified) == "[]")
        #expect(formatted(#"[{"a":[]}]"#, .minified) == #"[{"a":[]}]"#)
    }

    @Test("uniform mode breaks every container, one value per line")
    func uniform() {
        #expect(formatted(#"{"a":[1,2]}"#, .uniform) == """
        {
          "a": [
            1,
            2
          ]
        }
        """)
    }

    @Test("indent is configurable, and the status bar label comes from the same enum")
    func indentOptions() {
        #expect(formatted(#"{"a":{"b":1}}"#, FormatOptions(indent: .spaces(4), printWidth: nil)) == """
        {
            "a": {
                "b": 1
            }
        }
        """)
        #expect(formatted(#"{"a":{"b":1}}"#, FormatOptions(indent: .tab, printWidth: nil)) == """
        {
        \t"a": {
        \t\t"b": 1
        \t}
        }
        """)
        #expect(FormatOptions.Indent.spaces(2).label == "2 spaces")
        #expect(FormatOptions.Indent.spaces(1).label == "1 space")
        #expect(FormatOptions.Indent.tab.label == "Tabs")
    }

    @Test("the trailing newline is opt-in and adds exactly one")
    func trailingNewline() {
        #expect(formatted("{}", FormatOptions(compact: true, trailingNewline: true)) == "{}\n")
        #expect(formatted("{}", .minified) == "{}")
    }

    @Test("empty containers never break")
    func emptyContainers() {
        #expect(formatted(#"{"a":{},"b":[]}"#, .uniform) == """
        {
          "a": {},
          "b": []
        }
        """)
    }

    @Test("objects carry inner spaces when inlined, arrays don't")
    func inlineSpacing() {
        // Read off the approved artboard: `{ "value": 34.2, … }` but `["priority", …]`.
        #expect(formatted(#"{"a":{"x":1}}"#) == #"{ "a": { "x": 1 } }"#)
        #expect(formatted(#"{"a":[1,2]}"#) == #"{ "a": [1, 2] }"#)
    }

    @Test("a container breaks exactly when its line would exceed printWidth")
    func widthBoundary() {
        // 39 characters inline: `{ "key": "0123456789012345678901" }`… measure it rather than
        // eyeball it, then assert the decision either side of the boundary.
        let source = #"{"key":"0123456789012345678901234"}"#
        let inline = formatted(source, FormatOptions(printWidth: 200))
        #expect(!inline.contains("\n"))

        let broken = formatted(source, FormatOptions(printWidth: inline.count - 1))
        #expect(broken.contains("\n"), "one column short of fitting must break")

        let exact = formatted(source, FormatOptions(printWidth: inline.count))
        #expect(!exact.contains("\n"), "exactly fitting must stay inline")
    }

    @Test("the approved artboard's inline-or-break decisions, reproduced exactly")
    func matchesTheApprovedDesign() throws {
        // `Design/screens/Window.dc.html` is the visual source of truth. It inlines lines of 77,
        // 78 and 79 columns and breaks `headers`, which would be 119 — so any printWidth in
        // [87, 118] reproduces it, and the recorded default of 100 sits inside that range.
        // These four are every decision the artboard makes that is measurable.
        let source = try sampleJSON()
        let out = Formatter(options: FormatOptions(indent: .spaces(2), printWidth: 100))
            .format(try #require(Parser().parse(source).tree), source: source)
        let all = lines(out)

        func line(containing key: String) throws -> String {
            try #require(all.first { $0.contains("\"\(key)\"") }, "no line for \(key)")
        }

        // Broken in the artboard.
        #expect(try line(containing: "headers").hasSuffix("{"), "headers must break")
        #expect(try line(containing: "coordinates").hasSuffix("{"), "coordinates must break")

        // Inlined in the artboard, at these widths.
        let tags = try line(containing: "tags")
        #expect(tags.hasSuffix("],"), "tags must stay inline")
        #expect(tags.count == 78, "artboard renders this at 78 columns, got \(tags.count)")

        let accuracy = try line(containing: "accuracy")
        #expect(accuracy.contains("{ \"horizontal\""), "accuracy must stay inline")
        #expect(accuracy.count == 79, "artboard renders this at 79 columns, got \(accuracy.count)")

        let temperature = try line(containing: "temperature")
        #expect(temperature.count == 77, "artboard renders this at 77, got \(temperature.count)")
    }

    @Test("uniform mode on the fixture is 224 lines — the figure recorded when Format was specced")
    func uniformLineCount() throws {
        let source = try sampleJSON()
        let out = Formatter(options: .uniform).format(
            try #require(Parser().parse(source).tree), source: source)
        #expect(lines(out).count == 224)
    }

    @Test("deep nesting formats without exhausting the stack")
    func deepNesting() {
        // Same constraint as the parser: this runs on a concurrency thread with a 512 KB stack.
        let source = String(repeating: "{\"a\":", count: 400) + "1" + String(repeating: "}", count: 400)
        let result = Parser().parse(source)
        #expect(result.isValid)
        guard let tree = result.tree else { Issue.record("no tree"); return }
        let out = Formatter(options: .minified).format(tree, source: source)
        #expect(Parser().parse(out).isValid)
    }
}
