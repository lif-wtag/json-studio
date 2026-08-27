import Testing
@testable import JSONKit

// Phase 2. The plan names span accuracy as its own surface for a reason: a tree that classifies
// every value correctly but reports spans one unit out corrupts every feature above it —
// silently, and everywhere at once. These assert exact offsets and structural invariants over
// the real fixture rather than shapes over hand-written snippets.

/// Every node in a tree, in document order, with its parent.
private func flatten(_ node: JSONNode, into out: inout [JSONNode]) {
    out.append(node)
    for (_, child) in node.children { flatten(child, into: &out) }
}

@Suite("Span accuracy")
struct SpanAccuracyTests {

    private func fixtureTree() throws -> (source: String, units: [UInt16], root: JSONNode) {
        let source = try sampleJSON()
        let result = Parser().parse(source)
        try #require(result.isValid, "the fixture must parse clean")
        return (source, Array(source.utf16), try #require(result.tree))
    }

    private func text(_ span: SourceSpan, in units: [UInt16]) -> String {
        String(decoding: units[span.start..<span.end], as: UTF16.self)
    }

    @Test("every span lies inside the document")
    func spansAreInBounds() throws {
        let (_, units, root) = try fixtureTree()
        var nodes: [JSONNode] = []
        flatten(root, into: &nodes)

        for node in nodes {
            #expect(node.span.start >= 0)
            #expect(node.span.end <= units.count)
            #expect(node.span.start < node.span.end, "no node is zero-width")
        }
    }

    @Test("every child is strictly inside its parent, and siblings never overlap")
    func nesting() throws {
        let (_, _, root) = try fixtureTree()
        var nodes: [JSONNode] = []
        flatten(root, into: &nodes)

        for node in nodes {
            var previousEnd = node.span.start
            for (_, child) in node.children {
                #expect(node.span.contains(child.span), "child escaped its parent")
                #expect(child.span.start >= previousEnd, "siblings out of order or overlapping")
                previousEnd = child.span.end
            }
        }
    }

    @Test("a member's key sits before its value, and both inside the object")
    func memberSpans() throws {
        let (_, units, root) = try fixtureTree()
        var nodes: [JSONNode] = []
        flatten(root, into: &nodes)

        for node in nodes {
            guard case .object(let members) = node.value else { continue }
            for member in members {
                #expect(member.keySpan.end <= member.node.span.start, "key must precede its value")
                #expect(node.span.contains(member.span), "member escaped its object")
                // The key span includes its quotes, which is what "copy key" and the error
                // underline both depend on.
                let raw = text(member.keySpan, in: units)
                #expect(raw.hasPrefix("\""), "key span should include the opening quote: \(raw)")
                #expect(raw.hasSuffix("\""), "key span should include the closing quote: \(raw)")
            }
        }
    }

    @Test("a container's span begins on its opener and ends just past its closer")
    func containerDelimiters() throws {
        let (_, units, root) = try fixtureTree()
        var nodes: [JSONNode] = []
        flatten(root, into: &nodes)

        for node in nodes where node.value.isContainer {
            let raw = text(node.span, in: units)
            let expected = node.kind == .object ? ("{", "}") : ("[", "]")
            #expect(raw.hasPrefix(expected.0), "container span should start on \(expected.0)")
            #expect(raw.hasSuffix(expected.1), "container span should end on \(expected.1)")
        }
    }

    /// A structural fingerprint: every descendant as `path:kind`, with scalar values inlined.
    /// Deliberately not `JSONValue ==`, because a container's value embeds its children's
    /// **spans** — so the same structure at a different offset is legitimately not equal, and
    /// that is a fact the diff engine (step 7) has to respect too.
    private func shape(_ node: JSONNode, path: String = "$", into out: inout [String]) {
        switch node.value {
        case .object(let members):
            out.append("\(path):object(\(members.count))")
            for member in members { shape(member.node, path: "\(path).\(member.key)", into: &out) }
        case .array(let elements):
            out.append("\(path):array(\(elements.count))")
            for (i, element) in elements.enumerated() { shape(element, path: "\(path)[\(i)]", into: &out) }
        case .string(let value): out.append("\(path):string=\(value)")
        case .number(let text): out.append("\(path):number=\(text)")
        case .bool(let value): out.append("\(path):bool=\(value)")
        case .null: out.append("\(path):null")
        }
    }

    @Test("slicing any node's span and re-parsing it yields the same structure")
    func slicesReparse() throws {
        let (_, units, root) = try fixtureTree()
        var nodes: [JSONNode] = []
        flatten(root, into: &nodes)
        #expect(nodes.count > 100, "the fixture should be substantial: \(nodes.count) nodes")

        // The strongest statement of span accuracy available without a formatter: if a span is
        // even one unit out, the slice either fails to parse or parses to something else.
        for node in nodes {
            let slice = text(node.span, in: units)
            let reparsed = Parser().parse(slice)
            #expect(reparsed.errors.isEmpty, "slice did not parse cleanly: \(slice.prefix(60))")
            guard let tree = reparsed.tree else { Issue.record("no tree for \(slice.prefix(40))"); continue }

            var expected: [String] = [], actual: [String] = []
            shape(node, into: &expected)
            shape(tree, into: &actual)
            #expect(actual == expected, "slice parsed to a different structure")
            // The slice starts at offset 0, so its root span is the original's, rebased.
            #expect(tree.span == SourceSpan(start: 0, end: node.span.length))
        }
    }

    @Test("the unsafe integer and the German string keep exact spans")
    func awkwardValues() throws {
        let (_, units, root) = try fixtureTree()
        let r = PathResolver(root: root)

        let id = try #require(r.resolve(JSONPath([.key("account"), .key("externalId")])))
        #expect(text(id.span, in: units) == "9007199254740993")
        #expect(id.node.value == .number("9007199254740993"))

        let note = try #require(r.resolve(JSONPath([.key("account"), .key("note")])))
        let raw = text(note.span, in: units)
        #expect(raw.hasPrefix("\"") && raw.hasSuffix("\""), "the span includes both quotes")
        // The decoded value drops the quotes, so it is exactly two units shorter — no escapes
        // in this string, which is what makes the arithmetic checkable.
        #expect(note.node.value == .string(String(raw.dropFirst().dropLast())))
    }

    @Test("astral-plane characters occupy two units, and spans count units not characters")
    func astralPlaneArithmetic() {
        let source = "[\"🧊\", 1]"
        let units = Array(source.utf16)
        let result = Parser().parse(source)
        #expect(result.isValid)

        guard let ice = result.tree?.value.element(at: 0),
              let one = result.tree?.value.element(at: 1) else {
            Issue.record("expected two elements"); return
        }
        // "🧊" is 1 Character but 4 UTF-16 units with its quotes: " + 2 + ".
        #expect(ice.span == SourceSpan(start: 1, end: 5))
        #expect(text(ice.span, in: units) == "\"🧊\"")
        #expect(one.span == SourceSpan(start: 7, end: 8))
        #expect(source.utf16.count == 9)
    }
}
