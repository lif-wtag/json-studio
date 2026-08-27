import Testing
@testable import JSONKit

// Phase 2, step 7 / Task 9. ADR-07 says the structural diff is the reason the app can't be
// replaced by a website, so the load-bearing test is the first one: key order must produce no
// differences. Everything else builds on that.

private func tree(_ source: String) throws -> JSONNode {
    try #require(Parser().parse(source).tree, "fixture did not parse: \(source)")
}

private func diff(
    _ lhs: String, _ rhs: String, matching: ArrayMatching = .index
) throws -> [DiffChange] {
    try StructuralDiff(arrayMatching: matching).diff(try tree(lhs), try tree(rhs))
}

/// `kind@path` for each change — compact enough to assert a whole diff in one expectation.
private func summarise(_ changes: [DiffChange]) -> [String] {
    changes.map { "\($0.kind)@\($0.path)" }
}

@Suite("StructuralDiff · key-order independence")
struct DiffKeyOrderTests {

    @Test("the case ADR-07 exists for: reordering keys is not a difference")
    func reorderingKeysIsIdentical() throws {
        #expect(try diff(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#).isEmpty)
        #expect(try StructuralDiff().isIdentical(
            try tree(#"{"a":1,"b":2}"#), try tree(#"{"b":2,"a":1}"#)))
    }

    @Test("reordering survives nesting and mixed containers")
    func reorderingNested() throws {
        let a = #"{"x":{"p":1,"q":[1,2]},"y":null}"#
        let b = #"{"y":null,"x":{"q":[1,2],"p":1}}"#
        #expect(try diff(a, b).isEmpty)
    }

    @Test("array order, by contrast, IS meaningful")
    func arrayOrderMatters() throws {
        // Arrays are sequences; reordering them is a real change, not formatting.
        #expect(try diff("[1,2]", "[2,1]").isEmpty == false)
    }

    @Test("formatting is not a difference — whitespace and indentation are invisible")
    func formattingIsNotADifference() throws {
        let source = try sampleJSON()
        let original = try tree(source)
        for options: FormatOptions in [.pretty, .uniform, .minified] {
            let reformatted = Formatter(options: options).format(original, source: source)
            #expect(try StructuralDiff().diff(original, try tree(reformatted)).isEmpty,
                    "reformatting produced differences")
        }
    }

    @Test("a document does not differ from itself")
    func identity() throws {
        let source = try sampleJSON()
        #expect(try StructuralDiff().diff(try tree(source), try tree(source)).isEmpty)
    }
}

@Suite("StructuralDiff · classification")
struct DiffClassificationTests {

    @Test("added, removed, modified and type-changed")
    func fourKinds() throws {
        let changes = try diff(
            #"{"keep":1,"gone":2,"same":"s","num":1,"type":"5"}"#,
            #"{"keep":1,"same":"s","num":2,"type":5,"new":3}"#
        )
        #expect(Set(summarise(changes)) == Set([
            "removed@$.gone",
            "modified@$.num",
            "typeChanged@$.type",
            "added@$.new",
        ]))
        #expect(changes.count == 4, "unchanged members must produce nothing")
    }

    @Test("a type change is reported instead of recursing into it")
    func typeChangeDoesNotRecurse() throws {
        // A string that became an object has no meaningful child-level diff; descending would
        // bury the real change under one 'added' per key.
        let changes = try diff(#"{"a":"text"}"#, #"{"a":{"x":1,"y":2}}"#)
        #expect(summarise(changes) == ["typeChanged@$.a"])
        #expect(changes[0].typeTransition?.from == .string)
        #expect(changes[0].typeTransition?.to == .object)
    }

    @Test("the type transition feeds the design's dynamic label")
    func typeTransitionLabel() throws {
        let changes = try diff(#"{"a":"5"}"#, #"{"a":5}"#)
        let transition = try #require(changes.first?.typeTransition)
        // The design specifies "string → number"; JSONKit supplies the kinds, the UI the arrow.
        #expect("\(transition.from.rawValue) → \(transition.to.rawValue)" == "string → number")
    }

    @Test("both sides are carried, with spans indexing their own document")
    func bothSidesCarried() throws {
        //                     0123456789
        let changes = try diff(#"{"a":1}"#, #"{"a":22}"#)
        let change = try #require(changes.first)
        #expect(change.kind == .modified)
        #expect(change.before?.value == .number("1"))
        #expect(change.after?.value == .number("22"))
        #expect(change.before?.span == SourceSpan(start: 5, end: 6), "span in the LEFT document")
        #expect(change.after?.span == SourceSpan(start: 5, end: 7), "span in the RIGHT document")

        // Added has no before; removed has no after.
        let added = try #require(try diff("{}", #"{"a":1}"#).first)
        #expect(added.kind == .added && added.before == nil && added.after != nil)
        let removed = try #require(try diff(#"{"a":1}"#, "{}").first)
        #expect(removed.kind == .removed && removed.before != nil && removed.after == nil)
    }

    @Test("a whole added or removed subtree is ONE change, not one per descendant")
    func subtreeIsOneChange() throws {
        let changes = try diff("{}", #"{"a":{"b":{"c":[1,2,3]}}}"#)
        #expect(summarise(changes) == ["added@$.a"], "got \(summarise(changes))")
    }

    @Test("null is a value: null-to-value is a type change, null-to-null is nothing")
    func nulls() throws {
        #expect(try diff(#"{"a":null}"#, #"{"a":null}"#).isEmpty)
        #expect(summarise(try diff(#"{"a":null}"#, #"{"a":1}"#)) == ["typeChanged@$.a"])
        #expect(summarise(try diff(#"{"a":1}"#, #"{"a":null}"#)) == ["typeChanged@$.a"])
    }

    @Test("booleans: true to false is modified, not type-changed")
    func booleans() throws {
        #expect(summarise(try diff(#"{"a":true}"#, #"{"a":false}"#)) == ["modified@$.a"])
    }

    @Test("differing roots are reported at $")
    func rootDiffers() throws {
        #expect(summarise(try diff("1", #""1""#)) == ["typeChanged@$"])
        #expect(summarise(try diff("1", "2")) == ["modified@$"])
        #expect(summarise(try diff("{}", "[]")) == ["typeChanged@$"])
    }
}

@Suite("StructuralDiff · value comparison")
struct DiffValueComparisonTests {

    @Test("strings compare by DECODED value, so escaping is not a change")
    func stringsCompareDecoded() throws {
        // Decoding is lossless and total, so these genuinely denote the same string.
        #expect(try diff(#"{"a":"café"}"#, #"{"a":"café"}"#).isEmpty)
        #expect(try diff(#"{"a":"a\/b"}"#, #"{"a":"a/b"}"#).isEmpty)
    }

    @Test("numbers compare by SOURCE TEXT, so 1 and 1.0 read as changed")
    func numbersCompareText() throws {
        // Documented and deliberate. Normalising would mean parsing, and no Swift numeric type
        // holds every JSON number: Double rounds 9007199254740993 down, so a numeric comparison
        // would report two genuinely different integers as EQUAL. A diff may be noisy; it may
        // never claim two different values are the same.
        #expect(summarise(try diff(#"{"a":1}"#, #"{"a":1.0}"#)) == ["modified@$.a"])
        #expect(summarise(try diff(#"{"a":1e2}"#, #"{"a":100}"#)) == ["modified@$.a"])

        // The failure that rule prevents:
        #expect(summarise(try diff(#"{"a":9007199254740993}"#, #"{"a":9007199254740992}"#))
                == ["modified@$.a"])
        #expect(Double("9007199254740993") == Double("9007199254740992"),
                "…which is exactly why Double must not be the comparison")
    }
}

@Suite("StructuralDiff · duplicates, arrays and order")
struct DiffStructureTests {

    @Test("duplicate keys pair positionally within their key group")
    func duplicateKeys() throws {
        // Legal JSON, almost always a bug (VA-10). Handled rather than assumed away.
        #expect(try diff(#"{"a":1,"a":2}"#, #"{"a":1,"a":2}"#).isEmpty)
        #expect(summarise(try diff(#"{"a":1,"a":2}"#, #"{"a":1,"a":3}"#)) == ["modified@$.a"])
        // A surplus on either side is added or removed, sharing the one ambiguous path.
        #expect(summarise(try diff(#"{"a":1,"a":2}"#, #"{"a":1}"#)) == ["removed@$.a"])
        #expect(summarise(try diff(#"{"a":1}"#, #"{"a":1,"a":2}"#)) == ["added@$.a"])
    }

    @Test("arrays: index-wise pairing, with the surplus added or removed")
    func arraysIndexWise() throws {
        #expect(summarise(try diff("[1,2,3]", "[1,9,3]")) == ["modified@$[1]"])
        #expect(summarise(try diff("[1,2]", "[1,2,3]")) == ["added@$[2]"])
        #expect(summarise(try diff("[1,2,3]", "[1,2]")) == ["removed@$[2]"])
    }

    @Test("index-wise matching on records is noisy — the reason Task 10 exists")
    func indexWiseOnRecordsIsNoisy() throws {
        // One element inserted at the front shifts every subsequent pairing.
        let before = #"[{"id":1},{"id":2},{"id":3}]"#
        let after = #"[{"id":0},{"id":1},{"id":2},{"id":3}]"#
        let changes = try diff(before, after, matching: .index)
        #expect(changes.count == 4, "one insertion became \(changes.count) changes")
        // Identity-key matching (Task 10) should reduce this to a single 'added'.
    }

    @Test("unimplemented strategies fall back to index-wise, visibly")
    func unimplementedStrategiesFallBack() throws {
        #expect(ArrayMatching.index.isImplemented)
        #expect(!ArrayMatching.identityKey("id").isImplemented)
        #expect(!ArrayMatching.heuristic.isImplemented)
        // Same answer as .index until Task 10 — asserted so the fallback is not a surprise.
        let byIndex = summarise(try diff("[1,2]", "[1,9]", matching: .index))
        #expect(summarise(try diff("[1,2]", "[1,9]", matching: .identityKey("id"))) == byIndex)
        #expect(summarise(try diff("[1,2]", "[1,9]", matching: .heuristic)) == byIndex)
    }

    @Test("output order is deterministic")
    func deterministicOrder() throws {
        let a = #"{"z":1,"m":{"q":1,"p":2},"a":[1,2]}"#
        let b = #"{"a":[1,3],"m":{"p":9,"q":1},"z":2,"extra":0}"#
        let first = summarise(try diff(a, b))
        for _ in 0..<5 { #expect(summarise(try diff(a, b)) == first) }
        #expect(first.count == 4, "got \(first)")
    }

    @Test("a realistic API-response diff: nested value, added and removed keys, changed type")
    func realisticDiff() throws {
        let source = try sampleJSON()
        let modified = source
            .replacingOccurrences(of: "\"method\": \"GET\"", with: "\"method\": \"POST\"")
            .replacingOccurrences(of: "\"authenticated\": true", with: "\"authenticated\": \"yes\"")
            .replacingOccurrences(of: "\"locale\": \"de-DE\",", with: "")
        let changes = try StructuralDiff().diff(try tree(source), try tree(modified))
        let kinds = summarise(changes)
        #expect(kinds.contains("modified@$.request.method"))
        #expect(kinds.contains("typeChanged@$.request.authenticated"))
        #expect(kinds.contains("removed@$.account.locale"))
        #expect(changes.count == 3, "got \(kinds)")
    }
}

@Suite("StructuralDiff · robustness")
struct DiffRobustnessTests {

    @Test("deep nesting diffs without exhausting the stack")
    func deepNesting() throws {
        let deep = { (leaf: String) in
            String(repeating: "{\"a\":", count: 500) + leaf + String(repeating: "}", count: 500)
        }
        let changes = try StructuralDiff().diff(try tree(deep("1")), try tree(deep("2")))
        #expect(changes.count == 1)
        #expect(changes[0].kind == .modified)
        #expect(changes[0].path.components.count == 500)
    }

    @Test("partial trees diff — the compare workspace may hold an invalid document")
    func partialTrees() throws {
        let left = Parser().parse(#"{"a":1,"b":2"#)     // missing brace
        let right = Parser().parse(#"{"a":1,"b":3"#)
        #expect(!left.errors.isEmpty && !right.errors.isEmpty)
        let changes = try StructuralDiff().diff(
            try #require(left.tree), try #require(right.tree))
        #expect(summarise(changes) == ["modified@$.b"])
    }

    @Test("cancellation throws rather than returning a partial diff")
    func cancellation() async throws {
        let wide = "[" + Array(repeating: "1", count: 30_000).joined(separator: ",") + "]"
        let other = "[" + Array(repeating: "2", count: 30_000).joined(separator: ",") + "]"
        let l = try tree(wide), r = try tree(other)

        let task = Task { try StructuralDiff().diff(l, r) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
