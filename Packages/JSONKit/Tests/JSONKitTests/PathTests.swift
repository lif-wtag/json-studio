import Testing
@testable import JSONKit

// Phase 2, step 4. Both directions, and the property that matters more than either: for every
// node in a real document, the path derived from its offset must resolve back to that same node.
// A resolver that is merely self-consistent on hand-written cases would pass a dozen unit tests
// and still mis-select on the fixture.

private func resolver(_ source: String) -> PathResolver? {
    Parser().parse(source).tree.map(PathResolver.init(root:))
}

@Suite("JSONPath · rendering")
struct JSONPathRenderingTests {

    @Test("the $.a.b[0] form")
    func basicForm() {
        #expect(JSONPath([.key("a"), .key("b"), .index(0)]).description == "$.a.b[0]")
        #expect(JSONPath().description == "$")
        #expect(JSONPath.root.isRoot)
        #expect(JSONPath([.index(3), .index(1)]).description == "$[3][1]")
    }

    @Test("a key that isn't a bare identifier is bracketed and quoted")
    func bracketedKeys() {
        let cases: [(String, String)] = [
            ("with space", "$[\"with space\"]"),
            ("x-trace-id", "$[\"x-trace-id\"]"),        // hyphens are not identifier characters
            ("", "$[\"\"]"),
            ("1", "$[\"1\"]"),                          // $.1 would read as an index
            ("verträge-2026", "$[\"verträge-2026\"]"),
            ("a.b", "$[\"a.b\"]"),                      // a dot in the key must not read as a step
        ]
        for (key, expected) in cases {
            #expect(JSONPath([.key(key)]).description == expected, "key: \(key)")
        }
    }

    @Test("underscores and digits after the first character stay bare")
    func bareKeys() {
        for key in ["a", "_id", "schemaVersion", "x1", "A_B_2"] {
            #expect(JSONPath([.key(key)]).description == "$.\(key)")
        }
    }

    @Test("quotes, backslashes and control characters in a key are escaped")
    func escapedKeys() {
        #expect(JSONPath([.key("say \"hi\"")]).description == #"$["say \"hi\""]"#)
        #expect(JSONPath([.key("back\\slash")]).description == #"$["back\\slash"]"#)
        #expect(JSONPath([.key("two\nlines")]).description == #"$["two\nlines"]"#)
    }

    @Test("paths are hashable, so the inspector can key expansion state by them")
    func hashable() {
        let a = JSONPath([.key("a"), .index(0)])
        let b = JSONPath([.key("a"), .index(0)])
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
        #expect(Set([a, JSONPath([.key("a"), .index(1)])]).count == 2)
    }
}

@Suite("PathResolver · offset to path")
struct PathResolverOffsetTests {

    @Test("an offset inside a nested value gives its full path")
    func nestedValue() throws {
        //                  0         1         2         3
        //                  0123456789012345678901234567890123456
        let source = "{\"a\": {\"b\": [10, 20]}, \"c\": true}"
        let r = try #require(resolver(source))
        // Offset 17 is inside `20`.
        #expect(r.path(at: 17)?.description == "$.a.b[1]")
        // Offset 13 is inside `10`.
        #expect(r.path(at: 13)?.description == "$.a.b[0]")
        #expect(r.path(at: 27)?.description == "$.c")
    }

    @Test("an offset inside a KEY resolves to that member, not to its parent object")
    func offsetInsideKey() throws {
        //                  0123456789...
        let source = "{\"region\": 1}"
        let r = try #require(resolver(source))
        // Offsets 1–9 are the quoted key. Selecting a property name must select the property.
        for offset in 1...9 {
            #expect(r.path(at: offset)?.description == "$.region", "offset \(offset)")
        }
        // And the value still resolves to the same path.
        #expect(r.path(at: 11)?.description == "$.region")
    }

    @Test("an offset on a container's own delimiter resolves to the container")
    func offsetOnDelimiter() throws {
        //                  0123456789
        let source = "{\"a\": [1]}"
        let r = try #require(resolver(source))
        #expect(r.path(at: 0)?.description == "$", "the opening brace is the root itself")
        #expect(r.path(at: 6)?.description == "$.a", "the opening bracket belongs to $.a")
        #expect(r.path(at: 9)?.description == "$.a", "the closing brace of the root's member")
    }

    @Test("a caret immediately after a value is still inside that value")
    func caretAtTheTrailingEdge() throws {
        //                  0123456789
        let source = "{\"a\": [1]}"
        let r = try #require(resolver(source))
        // Offset 8 is the `]`, which is also the caret position you are left in after typing
        // `1`. Spans are half-open and `touches` accepts both boundaries precisely so this
        // resolves to the element rather than jumping out to its parent mid-keystroke.
        #expect(r.path(at: 8)?.description == "$.a[0]")

        // With whitespace between, nothing owns the gap and the array is the answer.
        let spaced = try #require(resolver("{\"a\": [1 ]}"))
        #expect(spaced.path(at: 9)?.description == "$.a")
    }

    @Test("an offset in the whitespace between members resolves to the enclosing object")
    func offsetBetweenMembers() throws {
        //                  0         1
        //                  012345678901234567
        let source = "{\"a\": 1,   \"b\": 2}"
        let r = try #require(resolver(source))
        #expect(r.path(at: 9)?.description == "$", "no member owns the gap after the comma")
    }

    @Test("an offset outside the document is nil, not a guess")
    func offsetOutside() throws {
        let r = try #require(resolver("  {\"a\": 1}  "))
        #expect(r.path(at: 0) == nil, "leading whitespace is outside the root span")
        #expect(r.path(at: 11) == nil, "trailing whitespace too")
        #expect(r.path(at: 2)?.description == "$")
    }

    @Test("a scalar document has only the root path")
    func scalarRoot() throws {
        let r = try #require(resolver("42"))
        #expect(r.path(at: 0)?.description == "$")
        #expect(r.path(at: 1)?.description == "$")
    }
}

@Suite("PathResolver · path to span")
struct PathResolverSpanTests {

    @Test("a path resolves to its value's span, and exposes the key's span separately")
    func spans() throws {
        //                  0         1
        //                  01234567890123
        let source = "{\"ab\": [7, 8]}"
        let r = try #require(resolver(source))

        let resolution = try #require(r.resolve(JSONPath([.key("ab")])))
        #expect(resolution.span == SourceSpan(start: 7, end: 13), "the array value")
        #expect(resolution.keySpan == SourceSpan(start: 1, end: 5), "the key, quotes included")
        #expect(resolution.memberSpan == SourceSpan(start: 1, end: 13), "key through value")
        #expect(resolution.node.kind == .array)

        // An array element has no key of its own.
        let element = try #require(r.resolve(JSONPath([.key("ab"), .index(1)])))
        #expect(element.keySpan == nil)
        #expect(element.span == SourceSpan(start: 11, end: 12))
        #expect(element.memberSpan == element.span)
        #expect(r.span(of: JSONPath([.key("ab"), .index(1)])) == element.span)
    }

    @Test("the root path resolves to the whole document")
    func rootPath() throws {
        let r = try #require(resolver("{\"a\": 1}"))
        #expect(r.span(of: .root) == SourceSpan(start: 0, end: 8))
        #expect(r.resolve(.root)?.keySpan == nil)
    }

    @Test("a path that no longer exists is nil — a stale selection must degrade, not trap")
    func stalePaths() throws {
        let r = try #require(resolver("{\"a\": [1, 2]}"))
        #expect(r.span(of: JSONPath([.key("nope")])) == nil)
        #expect(r.span(of: JSONPath([.key("a"), .index(5)])) == nil, "index past the end")
        #expect(r.span(of: JSONPath([.key("a"), .key("b")])) == nil, "a key into an array")
        #expect(r.span(of: JSONPath([.index(0)])) == nil, "an index into an object")
        #expect(r.span(of: JSONPath([.key("a"), .index(0), .key("x")])) == nil, "into a scalar")
    }

    @Test("duplicate keys resolve to the first, and the ambiguity is the documented behaviour")
    func duplicateKeys() throws {
        //                  0         1
        //                  0123456789012345
        let r = try #require(resolver("{\"a\": 1, \"a\": 2}"))
        // Both members render as $.a; resolving it picks the first in document order.
        #expect(r.path(at: 6)?.description == "$.a")
        #expect(r.path(at: 14)?.description == "$.a")
        #expect(r.resolve(JSONPath([.key("a")]))?.node.value == .number("1"))
        // Which is why the UI navigates by span: the second member is still reachable, just not
        // by its path. VA-10's duplicate-key warning is the real answer to this document.
        #expect(r.root.value.members("a").count == 2)
    }
}

@Suite("PathResolver · round trip")
struct PathResolverRoundTripTests {

    /// Every node in the tree, paired with the path the resolver derives for it.
    private func walk(_ node: JSONNode, _ path: JSONPath, into out: inout [(JSONPath, JSONNode)]) {
        out.append((path, node))
        switch node.value {
        case .object(let members):
            for member in members {
                walk(member.node, JSONPath(path.components + [.key(member.key)]), into: &out)
            }
        case .array(let elements):
            for (index, element) in elements.enumerated() {
                walk(element, JSONPath(path.components + [.index(index)]), into: &out)
            }
        default:
            break
        }
    }

    @Test("every node in the sample payload round-trips: node → path → span → same node")
    func roundTripsOverTheFixture() throws {
        let source = try sampleJSON()
        let result = Parser().parse(source)
        try #require(result.isValid)
        let root = try #require(result.tree)
        let r = PathResolver(root: root)

        var nodes: [(JSONPath, JSONNode)] = []
        walk(root, .root, into: &nodes)
        #expect(nodes.count > 100, "the fixture should be substantial: \(nodes.count) nodes")

        for (path, node) in nodes {
            // path → span
            #expect(r.span(of: path) == node.span, "\(path) resolved to the wrong span")

            // offset → path, for an offset that is unambiguously inside this node and no child.
            // A container's own opening delimiter is exactly such an offset; for a scalar, its
            // start is.
            let probe = node.span.start
            let derived = r.path(at: probe)
            #expect(derived == path, "offset \(probe) gave \(derived?.description ?? "nil"), expected \(path)")
        }
    }

    @Test("the fixture's awkward keys render as valid bracketed paths")
    func awkwardKeysInTheFixture() throws {
        let result = Parser().parse(try sampleJSON())
        let root = try #require(result.tree)
        let r = PathResolver(root: root)

        // `x-trace-id` has hyphens, so it must be bracketed rather than dotted.
        let headers = JSONPath([.key("request"), .key("headers")])
        let trace = JSONPath(headers.components + [.key("x-trace-id")])
        #expect(trace.description == "$.request.headers[\"x-trace-id\"]")
        #expect(r.span(of: trace) != nil, "and it must still resolve")
    }

    @Test("resolution works on a PARTIAL tree, which is what the editor usually has")
    func partialTree() {
        // Missing closing brace: the tree is partial but every span in it is real.
        let result = Parser().parse("{\"a\": {\"b\": 1}")
        #expect(!result.errors.isEmpty)
        guard let root = result.tree else { Issue.record("no tree"); return }
        let r = PathResolver(root: root)
        #expect(r.path(at: 12)?.description == "$.a.b")
        #expect(r.span(of: JSONPath([.key("a"), .key("b")])) == SourceSpan(start: 12, end: 13))
    }

    @Test("astral-plane characters don't shift paths — offsets are UTF-16 code units")
    func astralPlane() throws {
        // 🧊 is one Character but TWO UTF-16 code units, which is what SourceSpan counts.
        let source = "{\"ice\": \"🧊\", \"next\": 1}"
        let r = try #require(resolver(source))
        let next = try #require(r.resolve(JSONPath([.key("next")])))
        let units = Array(source.utf16)
        #expect(String(decoding: units[next.span.start..<next.span.end], as: UTF16.self) == "1")
        #expect(r.path(at: next.span.start)?.description == "$.next")
    }
}
