import Testing
@testable import JSONKit

// Phase 2, step 6 / Task 8. The counts are trivial arithmetic; what is worth testing is the
// three judgment calls — keys aren't strings, numbers count tokens, duplicates count twice —
// and the depth definition, because that one is user-facing and the artboard renders a figure
// for it.

private func stats(_ source: String) throws -> Statistics {
    let tree = try #require(Parser().parse(source).tree)
    return try StatisticsWalker().walk(tree)
}

@Suite("Statistics · counting")
struct StatisticsCountingTests {

    @Test("each value kind is counted once")
    func kinds() throws {
        let s = try stats(#"{"a":"x","b":1,"c":true,"d":false,"e":null,"f":[],"g":{}}"#)
        #expect(s.objects == 2, "the root and the empty object at g")
        #expect(s.arrays == 1)
        #expect(s.strings == 1)
        #expect(s.numbers == 1)
        #expect(s.booleans == 2, "true and false are both booleans")
        #expect(s.nulls == 1)
        #expect(s.properties == 7)
    }

    @Test("an object KEY is not counted as a string — the counts are of values")
    func keysAreNotStrings() throws {
        // Three keys, one string value. Counting keys would report 4 and mean nothing to a reader.
        let s = try stats(#"{"one":1,"two":2,"three":"x"}"#)
        #expect(s.strings == 1)
        #expect(s.properties == 3)
    }

    @Test("numbers counts tokens, so 1 and 1.0 are two numbers")
    func numbersCountTokens() throws {
        let s = try stats(#"[1,1.0,1e0,9007199254740993]"#)
        #expect(s.numbers == 4, "four numbers were written, whatever they evaluate to")
    }

    @Test("duplicate keys count twice — collapsing them would hide what VA-10 warns about")
    func duplicateKeys() throws {
        let s = try stats(#"{"a":1,"a":2}"#)
        #expect(s.properties == 2)
        #expect(s.numbers == 2)
    }

    @Test("totalValues equals the node count of the tree")
    func totalValues() throws {
        let s = try stats(#"{"a":[1,2],"b":{"c":null}}"#)
        // root, array, 1, 2, object b, null = 6
        #expect(s.totalValues == 6)
        #expect(s.objects + s.arrays + s.strings + s.numbers + s.booleans + s.nulls == s.totalValues)
    }

    @Test("an empty document counts nothing rather than counting zeroes")
    func emptyDocument() throws {
        let result = Parser().parse("   ")
        #expect(result.isEmpty)
        // Returning a Statistics of all zeroes would render a table claiming the document has
        // no properties, which is a different statement from "there is no document".
        #expect(try StatisticsWalker().walk(result) == nil)
    }

    @Test("a scalar document is one value at depth zero")
    func scalarRoot() throws {
        let s = try stats("42")
        #expect(s.numbers == 1)
        #expect(s.maxDepth == 0, "no containers means no nesting")
        #expect(s.totalValues == 1)
    }
}

@Suite("Statistics · depth")
struct StatisticsDepthTests {

    @Test("the outermost container is depth 1")
    func outermostIsOne() throws {
        #expect(try stats(#"{"a":1}"#).maxDepth == 1)
        #expect(try stats("[1,2]").maxDepth == 1)
        #expect(try stats("{}").maxDepth == 1)
    }

    @Test("depth counts container nesting, so an empty nested container still counts")
    func emptyNestedContainerCounts() throws {
        // This is the case where the statistic deliberately differs from JSONNode.depth, which
        // measures the longest chain to a leaf and would report 1.
        let source = #"{"a":{}}"#
        #expect(try stats(source).maxDepth == 2)
        #expect(Parser().parse(source).tree?.depth == 1, "JSONNode.depth is a different measure")
    }

    @Test("depth follows the deepest branch, not the last one")
    func deepestBranch() throws {
        #expect(try stats(#"{"shallow":1,"deep":{"a":{"b":{"c":1}}}}"#).maxDepth == 4)
        #expect(try stats(#"{"deep":{"a":{"b":{"c":1}}},"shallow":1}"#).maxDepth == 4)
    }

    @Test("arrays and objects both add a level")
    func mixedNesting() throws {
        #expect(try stats("[[[1]]]").maxDepth == 3)
        #expect(try stats(#"[{"a":[{"b":1}]}]"#).maxDepth == 4)
    }
}

@Suite("Statistics · the sample payload")
struct StatisticsFixtureTests {

    @Test("the fixture's counts, including the two figures the design renders")
    func fixture() throws {
        let source = try sampleJSON()
        let result = Parser().parse(source)
        try #require(result.isValid)
        let s = try StatisticsWalker().walk(try #require(result.tree))

        // Both of these appear in the approved design and so are acceptance figures, not
        // arbitrary snapshots: the status bar shows a property count, and the inspector's
        // Structure header renders `depth 7`.
        #expect(s.properties == 119)
        #expect(s.maxDepth == 7)

        #expect(s.totalValues == 183)
        #expect(s.characterCount == 3719, "UTF-16 units of the root value, excluding the trailing newline")
        #expect(s.objects > 0 && s.arrays > 0 && s.strings > 0)
        #expect(s.nulls > 0, "the fixture has nulls on purpose")
        #expect(s.booleans > 0)
    }

    @Test("characterCount is UTF-16 units, which the emoji make visible")
    func characterCountUnit() throws {
        let source = try sampleJSON()
        let s = try StatisticsWalker().walk(try #require(Parser().parse(source).tree))
        // Graphemes and UTF-16 units differ here, which is why the field documents its unit.
        #expect(s.characterCount == 3719)
        #expect(source.count == 3717, "3716 Characters plus the trailing newline")
        #expect(s.characterCount != source.count - 1)
    }

    @Test("statistics are unaffected by formatting — they describe structure, not layout")
    func stableAcrossFormatting() throws {
        let source = try sampleJSON()
        let tree = try #require(Parser().parse(source).tree)
        let original = try StatisticsWalker().walk(tree)

        for options: FormatOptions in [.pretty, .uniform, .minified] {
            let reformatted = Formatter(options: options).format(tree, source: source)
            let after = try StatisticsWalker().walk(try #require(Parser().parse(reformatted).tree))
            // Every count must match except characterCount, which is a length and so moves.
            var expected = original
            expected.characterCount = after.characterCount
            #expect(after == expected, "formatting changed a count")
        }
    }

    @Test("a partial tree still counts what survived")
    func partialTree() throws {
        let result = Parser().parse(#"{"a":1,"b":[2,3]"#)   // missing closing brace
        #expect(!result.errors.isEmpty)
        let s = try StatisticsWalker().walk(try #require(result.tree))
        #expect(s.properties == 2)
        #expect(s.numbers == 3)
    }

    @Test("deep nesting counts without exhausting the stack")
    func deepNesting() throws {
        // Runs on a concurrency thread with a 512 KB stack — the condition that killed the
        // recursive parser at 96 levels and the recursive formatter at 192.
        let source = String(repeating: "{\"a\":", count: 500) + "1" + String(repeating: "}", count: 500)
        let s = try StatisticsWalker().walk(try #require(Parser().parse(source).tree))
        #expect(s.objects == 500)
        #expect(s.maxDepth == 500)
        #expect(s.numbers == 1)
    }

    @Test("cancellation throws rather than returning a half-count")
    func cancellation() async throws {
        // A wide document, so the walk crosses the cancellation-check interval.
        let source = "[" + Array(repeating: "1", count: 50_000).joined(separator: ",") + "]"
        let tree = try #require(Parser().parse(source).tree)

        let task = Task { try StatisticsWalker().walk(tree) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
