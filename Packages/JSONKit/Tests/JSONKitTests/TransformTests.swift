import Testing
@testable import JSONKit

// Phase 2, step 9 / Task 11. The transforms are the first code that *rewrites* the tree rather
// than reading it, so the tests that matter are the ones about what survives the rewrite: spans,
// number source text, string escapes, and the byte-exact round trip through the formatter.

private func node(_ source: String) throws -> JSONNode {
    try #require(Parser().parse(source).tree)
}

/// Formats a transformed tree against the source it came from — the contract `TreeTransform`
/// documents, and the only correct way to render one.
private func render(_ transformed: JSONNode, from source: String) -> String {
    Formatter(options: .minified).format(transformed, source: source)
}

@Suite("KeySorter")
struct KeySorterTests {

    @Test("shallow sorts only this object's own keys")
    func shallow() throws {
        let source = #"{"c":1,"a":{"z":1,"b":2},"b":3}"#
        let sorted = KeySorter(recursive: false).sorted(try node(source))
        #expect(render(sorted, from: source) == #"{"a":{"z":1,"b":2},"b":3,"c":1}"#)
    }

    @Test("recursive sorts nested objects, including ones inside arrays")
    func recursive() throws {
        let source = #"{"c":1,"a":{"z":1,"b":2},"d":[{"y":1,"x":2}]}"#
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        #expect(render(sorted, from: source) == #"{"a":{"b":2,"z":1},"c":1,"d":[{"x":2,"y":1}]}"#)
    }

    @Test("arrays are never reordered — an array is a sequence, not a bag")
    func arraysAreNotSorted() throws {
        let source = #"{"a":[3,1,2]}"#
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        #expect(render(sorted, from: source) == #"{"a":[3,1,2]}"#)
    }

    @Test("duplicate keys keep their relative order — the sort is stable")
    func stability() throws {
        // Reordering duplicates would destroy VA-10's evidence and could change which value a
        // consumer reads.
        let source = #"{"b":1,"a":"first","a":"second"}"#
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        #expect(render(sorted, from: source) == #"{"a":"first","a":"second","b":1}"#)
    }

    @Test("sorting is idempotent")
    func idempotent() throws {
        let source = try sampleJSON()
        let once = KeySorter(recursive: true).sorted(try node(source))
        let twice = KeySorter(recursive: true).sorted(once)
        #expect(once.isStructurallyEqual(to: twice))
        #expect(render(once, from: source) == render(twice, from: source))
    }

    @Test("sorting changes nothing structurally — key order is not part of the value")
    func structurallyUnchanged() throws {
        let source = try sampleJSON()
        let original = try node(source)
        let sorted = KeySorter(recursive: true).sorted(original)
        // The diff's own promise, applied to the transform's own output.
        #expect(original.isStructurallyEqual(to: sorted))
        #expect(try StructuralDiff().diff(original, sorted).isEmpty)
    }

    @Test("a non-object root passes through untouched")
    func nonObjectRoot() throws {
        for source in ["42", #""text""#, "[3,1,2]", "null"] {
            let sorted = KeySorter(recursive: true).sorted(try node(source))
            #expect(render(sorted, from: source) == source)
        }
    }

    @Test("deep nesting sorts without exhausting the stack")
    func deepNesting() throws {
        let source = String(repeating: #"{"b":1,"a":"#, count: 400) + "1"
            + String(repeating: "}", count: 400)
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        #expect(render(sorted, from: source).hasPrefix(#"{"a":"#))
    }
}

@Suite("Pruner")
struct PrunerTests {

    @Test("each rule strips only what it names")
    func rulesAreIndependent() throws {
        let source = #"{"n":null,"e":"","o":{},"a":[],"keep":1}"#
        let tree = try node(source)

        let nulls = try #require(Pruner(stripNulls: true).pruned(tree))
        #expect(render(nulls, from: source) == #"{"e":"","o":{},"a":[],"keep":1}"#)

        let strings = try #require(
            Pruner(stripNulls: false, stripEmptyStrings: true).pruned(tree))
        #expect(render(strings, from: source) == #"{"n":null,"o":{},"a":[],"keep":1}"#)

        let collections = try #require(
            Pruner(stripNulls: false, stripEmptyCollections: true).pruned(tree))
        #expect(render(collections, from: source) == #"{"n":null,"e":"","keep":1}"#)
    }

    @Test("pruning cascades in one pass, so it reaches a fixed point immediately")
    func cascades() throws {
        // {"a":{"b":null}} → {"a":{}} → {} → nothing, all bottom-up in a single walk. The root
        // is an empty collection like any other, so the cascade reaches it too — consistent with
        // `pruned("{}") == nil` below. Anything less would need the command run twice and would
        // break idempotence.
        let pruner = Pruner(stripNulls: true, stripEmptyCollections: true)
        #expect(pruner.pruned(try node(#"{"a":{"b":null}}"#)) == nil)

        // And it stops as soon as something survives, rather than eating the document.

        let deeper = #"{"x":{"y":{"z":null}},"keep":1}"#
        let prunedDeeper = try #require(pruner.pruned(try node(deeper)))
        #expect(render(prunedDeeper, from: deeper) == #"{"keep":1}"#)
    }

    @Test("array elements are pruned too, which shifts indices")
    func arraysArePruned() throws {
        let source = #"{"a":[1,null,2,null,3]}"#
        let pruned = try #require(Pruner(stripNulls: true).pruned(try node(source)))
        #expect(render(pruned, from: source) == #"{"a":[1,2,3]}"#)
    }

    @Test("the root can prune away entirely, and that is nil rather than an empty object")
    func rootPrunesAway() throws {
        #expect(Pruner(stripNulls: true).pruned(try node("null")) == nil)
        #expect(Pruner(stripNulls: false, stripEmptyStrings: true).pruned(try node(#""""#)) == nil)

        let emptyRoot = Pruner(stripNulls: false, stripEmptyCollections: true)
        #expect(emptyRoot.pruned(try node("{}")) == nil)
        #expect(emptyRoot.pruned(try node("[]")) == nil)
    }

    @Test("values that merely look empty are kept — 0, false and \"0\" are values")
    func doesNotOverreach() throws {
        let source = #"{"zero":0,"false":false,"zeroString":"0","negZero":-0}"#
        let pruner = Pruner(stripNulls: true, stripEmptyStrings: true, stripEmptyCollections: true)
        let pruned = try #require(pruner.pruned(try node(source)))
        #expect(render(pruned, from: source) == #"{"zero":0,"false":false,"zeroString":"0","negZero":-0}"#)
    }

    @Test("pruning is idempotent")
    func idempotent() throws {
        let source = try sampleJSON()
        let pruner = Pruner(stripNulls: true, stripEmptyStrings: true, stripEmptyCollections: true)
        let once = try #require(pruner.pruned(try node(source)))
        let twice = try #require(pruner.pruned(once))
        #expect(once.isStructurallyEqual(to: twice))
        #expect(render(once, from: source) == render(twice, from: source))
    }

    @Test("no rule enabled is a no-op, and says so before the walk")
    func noOp() throws {
        let pruner = Pruner(stripNulls: false)
        #expect(pruner.isNoOp)
        let source = #"{"n":null,"e":""}"#
        let pruned = try #require(pruner.pruned(try node(source)))
        #expect(render(pruned, from: source) == source)
    }

    @Test("deep nesting prunes without exhausting the stack")
    func deepNesting() throws {
        let source = String(repeating: #"{"a":"#, count: 400) + "null"
            + String(repeating: "}", count: 400)
        // Strips the null, then cascades all 400 levels away.
        #expect(Pruner(stripNulls: true, stripEmptyCollections: true).pruned(try node(source)) == nil)
        // Without the cascade rule, the 400 empty objects survive.
        let kept = try #require(Pruner(stripNulls: true).pruned(try node(source)))
        #expect(render(kept, from: source).hasPrefix(#"{"a":{"#))
    }
}

@Suite("Transforms · what must survive a rewrite")
struct TransformFidelityTests {

    @Test("spans survive, so the formatter still re-emits escapes byte-exactly")
    func spansSurviveForByteExactness() throws {
        // The reason TreeTransform keeps spans: re-encoding would turn é into a literal é
        // and \/ into /. Both are the same value and neither is what was typed.
        let source = #"{"z":1,"a":"café","b":"p\/q"}"#
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        let rendered = render(sorted, from: source)
        #expect(rendered == #"{"a":"café","b":"p\/q","z":1}"#)
        #expect(rendered.contains(#"é"#), "escape was re-encoded instead of re-emitted")
    }

    @Test("number source text survives, including the value Double cannot hold")
    func numbersSurvive() throws {
        let source = #"{"z":1.0,"a":9007199254740993,"b":-0,"c":1.2e+10}"#
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        let rendered = render(sorted, from: source)
        #expect(rendered == #"{"a":9007199254740993,"b":-0,"c":1.2e+10,"z":1.0}"#)
    }

    @Test("keys keep their own escapes too, not just values")
    func keyEscapesSurvive() throws {
        let source = #"{"z":1,"key":2}"#
        let sorted = KeySorter(recursive: true).sorted(try node(source))
        #expect(render(sorted, from: source).contains(#"key"#))
    }

    @Test("a transformed tree round-trips: format it, reparse it, same structure")
    func roundTripsThroughTheFormatter() throws {
        let source = try sampleJSON()
        let tree = try node(source)

        for transformed in [
            KeySorter(recursive: true).sorted(tree),
            KeySorter(recursive: false).sorted(tree),
            try #require(Pruner(stripNulls: true).pruned(tree)),
        ] {
            for options: FormatOptions in [.pretty, .uniform, .minified] {
                let text = Formatter(options: options).format(transformed, source: source)
                let reparsed = Parser().parse(text)
                #expect(reparsed.isValid, "transformed output did not reparse")
                #expect(try #require(reparsed.tree).isStructurallyEqual(to: transformed))
            }
        }
    }

    @Test("sort then prune, and prune then sort, agree")
    func transformsCompose() throws {
        let source = try sampleJSON()
        let tree = try node(source)
        let sorter = KeySorter(recursive: true)
        let pruner = Pruner(stripNulls: true, stripEmptyCollections: true)

        let sortedThenPruned = try #require(pruner.pruned(sorter.sorted(tree)))
        let prunedThenSorted = sorter.sorted(try #require(pruner.pruned(tree)))
        #expect(render(sortedThenPruned, from: source) == render(prunedThenSorted, from: source))
    }

    @Test("a transform preserves everything the diff considers a value")
    func noStructuralChangeBeyondTheIntendedOne() throws {
        let source = try sampleJSON()
        let tree = try node(source)
        // Sorting is value-preserving; pruning is not, and every difference it makes must be a
        // removal — never a modification or an addition.
        let pruned = try #require(Pruner(stripNulls: true).pruned(tree))
        let changes = try StructuralDiff().diff(tree, pruned)
        #expect(!changes.isEmpty, "the fixture has nulls, so something should have gone")
        #expect(changes.allSatisfy { $0.kind == .removed }, "pruning did more than remove")
    }
}
