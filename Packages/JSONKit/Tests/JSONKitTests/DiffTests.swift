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

// MARK: - Task 10: array matching

@Suite("StructuralDiff · identity-key matching")
struct DiffIdentityKeyTests {

    private let records = #"[{"id":1,"v":"a"},{"id":2,"v":"b"},{"id":3,"v":"c"}]"#

    @Test("the design's own claim: a reordered record array is Identical, 0 changes")
    func reorderedRecordsAreIdentical() throws {
        // The Compare artboard renders "Identical · 0 changes" and explains: "Identity-key
        // matching pairs records by id, so a reordered array is not 32 changes."
        let shuffled = #"[{"id":3,"v":"c"},{"id":1,"v":"a"},{"id":2,"v":"b"}]"#
        #expect(try diff(records, shuffled, matching: .identityKey("id")).isEmpty)
    }

    @Test("…and the same input index-wise is every element changed — the contrast that justifies it")
    func sameInputIndexWiseIsNoise() throws {
        let shuffled = #"[{"id":3,"v":"c"},{"id":1,"v":"a"},{"id":2,"v":"b"}]"#
        // Each of the three positions has both its id and its v changed, so a pure reorder of
        // three records costs six changes index-wise — against zero under identity-key.
        let changes = try diff(records, shuffled, matching: .index)
        #expect(changes.count == 6, "index-wise reports \(changes.count) changes for a reorder")
        #expect(changes.allSatisfy { $0.kind == .modified })
    }

    @Test("an inserted record is one addition, not a cascade")
    func insertion() throws {
        let withNew = #"[{"id":0,"v":"z"},{"id":1,"v":"a"},{"id":2,"v":"b"},{"id":3,"v":"c"}]"#
        #expect(summarise(try diff(records, withNew, matching: .identityKey("id"))) == ["added@$[0]"])
        // Index-wise shifts every record by one, so both fields of all three differ, plus the
        // surplus element: seven changes for a single insertion.
        let byIndex = try diff(records, withNew, matching: .index)
        #expect(byIndex.count == 7, "got \(byIndex.count)")
    }

    @Test("a removed record is one removal, and an edited one is a modification at its own path")
    func removalAndEdit() throws {
        let without2 = #"[{"id":1,"v":"a"},{"id":3,"v":"c"}]"#
        #expect(summarise(try diff(records, without2, matching: .identityKey("id"))) == ["removed@$[1]"])

        let edited = #"[{"id":1,"v":"a"},{"id":2,"v":"CHANGED"},{"id":3,"v":"c"}]"#
        #expect(summarise(try diff(records, edited, matching: .identityKey("id")))
                == ["modified@$[1].v"])
    }

    @Test("reordered AND edited: the edit is found at the record's left-document index")
    func reorderedAndEdited() throws {
        let both = #"[{"id":3,"v":"c"},{"id":2,"v":"CHANGED"},{"id":1,"v":"a"}]"#
        #expect(summarise(try diff(records, both, matching: .identityKey("id")))
                == ["modified@$[1].v"])
    }

    @Test("elements without the key are paired positionally among themselves")
    func unkeyedElementsFallBack() throws {
        // A partly-keyed array stays useful instead of reporting every unkeyed element twice.
        let a = #"[{"id":1,"v":"a"},"loose",{"id":2,"v":"b"}]"#
        let b = #"[{"id":2,"v":"b"},"loose",{"id":1,"v":"a"}]"#
        #expect(try diff(a, b, matching: .identityKey("id")).isEmpty)

        // `#expect`'s message is a NON-throwing autoclosure, so the result is hoisted first —
        // the same constraint the tokenizer task hit with `allSatisfy(\.keyPath)`.
        let c = #"[{"id":1,"v":"a"},"changed"]"#
        let mixed = summarise(try diff(a, c, matching: .identityKey("id")))
        #expect(mixed == ["removed@$[2]", "modified@$[1]"], "got \(mixed)")
    }

    @Test("a container-valued identity is not an identity — those elements pair positionally")
    func containerIdentityIsIgnored() throws {
        let a = #"[{"id":[1],"v":"a"},{"id":[2],"v":"b"}]"#
        let b = #"[{"id":[2],"v":"b"},{"id":[1],"v":"a"}]"#
        // Positional, so this reads as changed rather than as a reorder.
        #expect(!(try diff(a, b, matching: .identityKey("id")).isEmpty))
    }

    @Test("duplicate identity values pair positionally within their group")
    func duplicateIdentities() throws {
        let a = #"[{"id":1,"v":"x"},{"id":1,"v":"y"}]"#
        #expect(try diff(a, a, matching: .identityKey("id")).isEmpty)
        let b = #"[{"id":1,"v":"x"},{"id":1,"v":"z"}]"#
        #expect(summarise(try diff(a, b, matching: .identityKey("id"))) == ["modified@$[1].v"])
    }

    @Test("a missing key name matches nothing and degrades to positional")
    func wrongKeyName() throws {
        let shuffled = #"[{"id":3,"v":"c"},{"id":1,"v":"a"},{"id":2,"v":"b"}]"#
        // Nothing has "uuid", so every element is unkeyed and pairs positionally.
        let byWrongKey = summarise(try diff(records, shuffled, matching: .identityKey("uuid")))
        let byIndex = summarise(try diff(records, shuffled, matching: .index))
        #expect(byWrongKey == byIndex)
    }
}

@Suite("StructuralDiff · heuristic matching")
struct DiffHeuristicTests {

    @Test("an insertion is one addition, not a shift of everything after it")
    func insertionInAnOrderedList() throws {
        let before = #"["a","b","c","d"]"#
        let after = #"["a","b","NEW","c","d"]"#
        #expect(summarise(try diff(before, after, matching: .heuristic)) == ["added@$[2]"])
        // Index-wise shifts: c→NEW, d→c, then d is added.
        #expect(try diff(before, after, matching: .index).count == 3)
    }

    @Test("a deletion is one removal")
    func deletion() throws {
        #expect(summarise(try diff(#"["a","b","c"]"#, #"["a","c"]"#, matching: .heuristic))
                == ["removed@$[1]"])
    }

    @Test("an element edited in place is ONE modification, not a removal plus an addition")
    func editInPlace() throws {
        // The reason the gaps are paired positionally after the LCS: a plain LCS matches only
        // identical elements, so this would otherwise be worse than index-wise.
        #expect(summarise(try diff(#"["a","b","c"]"#, #"["a","CHANGED","c"]"#, matching: .heuristic))
                == ["modified@$[1]"])
    }

    @Test("insertion and edit together are reported separately")
    func insertionAndEdit() throws {
        let before = #"["a","b","c"]"#
        let after = #"["a","b","EDITED","NEW"]"#
        let changes = try diff(before, after, matching: .heuristic)
        #expect(changes.count == 2, "got \(summarise(changes))")
        #expect(Set(changes.map(\.kind)) == Set([.modified, .added]))
    }

    @Test("records without an id still align on the ones that didn't change")
    func recordsWithoutAnIdentity() throws {
        let before = #"[{"a":1},{"b":2},{"c":3}]"#
        let after = #"[{"a":1},{"NEW":0},{"b":2},{"c":3}]"#
        #expect(summarise(try diff(before, after, matching: .heuristic)) == ["added@$[1]"])
    }

    @Test("reordering is still a change under the heuristic — arrays are sequences")
    func reorderingIsStillAChange() throws {
        // Only identity-key treats a reorder as identical; the heuristic preserves order meaning.
        #expect(!(try diff(#"["a","b"]"#, #"["b","a"]"#, matching: .heuristic).isEmpty))
    }

    @Test("key order inside elements is still ignored — CP-02 holds through matching")
    func keyOrderInsideElements() throws {
        let a = #"[{"x":1,"y":2},{"p":3}]"#
        let b = #"[{"y":2,"x":1},{"p":3}]"#
        #expect(try diff(a, b, matching: .heuristic).isEmpty)
        #expect(try diff(a, b, matching: .identityKey("x")).isEmpty)
    }

    @Test("the LCS cap is documented and answerable in advance, not silent")
    func cellCap() {
        #expect(StructuralDiff.heuristicWasExact(leftCount: 100, rightCount: 100))
        #expect(StructuralDiff.heuristicWasExact(leftCount: 2000, rightCount: 2000))
        #expect(!StructuralDiff.heuristicWasExact(leftCount: 3000, rightCount: 3000))
    }

    @Test("two long arrays differing only in the middle stay cheap and exact")
    func prefixSuffixStripping() throws {
        // Prefix/suffix stripping is what keeps the cap out of reach for realistic documents.
        let common = (0..<5000).map { "\($0)" }.joined(separator: ",")
        let before = "[" + common + ",111,999]"
        let after = "[" + common + ",222,999]"
        #expect(summarise(try diff(before, after, matching: .heuristic)) == ["modified@$[5000]"])
    }

    @Test("heuristic is the default, since it is the least-noisy assumption when nothing is known")
    func defaultStrategy() throws {
        #expect(StructuralDiff().arrayMatching == .heuristic)
    }
}

@Suite("Structural equality")
struct StructuralEqualityTests {

    @Test("equal structure at different offsets — where == gets it wrong")
    func ignoresSpans() throws {
        let a = try tree(#"{"a":[1,2]}"#)
        let b = try tree("   " + #"{"a":[1,2]}"#)
        #expect(a.isStructurallyEqual(to: b))
        #expect(a != b, "== compares spans, which is exactly why this method exists")
    }

    @Test("key order ignored, array order respected")
    func orderRules() throws {
        #expect(try tree(#"{"a":1,"b":2}"#).isStructurallyEqual(to: try tree(#"{"b":2,"a":1}"#)))
        #expect(!(try tree("[1,2]").isStructurallyEqual(to: try tree("[2,1]"))))
    }

    @Test("differences in kind, count, value and duplicates are all caught")
    func differences() throws {
        #expect(!(try tree(#"{"a":1}"#).isStructurallyEqual(to: try tree(#"{"a":"1"}"#))))
        #expect(!(try tree(#"{"a":1}"#).isStructurallyEqual(to: try tree(#"{"a":1,"b":2}"#))))
        #expect(!(try tree(#"{"a":1,"a":2}"#).isStructurallyEqual(to: try tree(#"{"a":1,"a":3}"#))))
        #expect(!(try tree("[1]").isStructurallyEqual(to: try tree("[1,1]"))))
    }

    @Test("survives reformatting, and deep nesting")
    func robust() throws {
        let source = try sampleJSON()
        let original = try tree(source)
        let minified = Formatter(options: .minified).format(original, source: source)
        #expect(original.isStructurallyEqual(to: try tree(minified)))

        let deep = { (leaf: String) in
            String(repeating: "[", count: 500) + leaf + String(repeating: "]", count: 500)
        }
        #expect(try tree(deep("1")).isStructurallyEqual(to: try tree(deep("1"))))
        #expect(!(try tree(deep("1")).isStructurallyEqual(to: try tree(deep("2")))))
    }
}

@Suite("Structural digest")
struct StructuralDigestTests {

    /// Swift rejects `try` to the right of a non-assignment operator, so digests are taken first.
    private func digest(_ source: String) throws -> Int {
        try tree(source).structuralDigest
    }

    @Test("equal structure digests equally, whatever the offsets or key order")
    func equalStructure() throws {
        #expect(try digest(#"{"a":1}"#) == (try digest("  " + #"{"a":1}"#)))
        #expect(try digest(#"{"a":1,"b":2}"#) == (try digest(#"{"b":2,"a":1}"#)))

        let source = try sampleJSON()
        let original = try tree(source)
        let minified = Formatter(options: .minified).format(original, source: source)
        #expect(original.structuralDigest == (try tree(minified).structuralDigest))
    }

    @Test("array order changes the digest, because arrays are sequences")
    func arrayOrderMatters() throws {
        let ordered = try digest("[1,2]"), reversed = try digest("[2,1]")
        #expect(ordered != reversed)
    }

    @Test("things that must not collide, don't")
    func discriminates() throws {
        let cases = [
            #"{"a":1}"#, #"{"a":2}"#, #"{"b":1}"#, #"{"a":"1"}"#, #"{"a":1.0}"#,
            "[1]", "[1,1]", "{}", "[]", "null", "0", "false",
            #"{"a":{"b":1}}"#, #"{"a":[1]}"#,
        ]
        var seen: [Int: String] = [:]
        for source in cases {
            let d = try digest(source)
            #expect(seen[d] == nil, "\(source) collided with \(seen[d] ?? "")")
            seen[d] = source
        }
    }

    @Test("duplicated members accumulate rather than cancelling out")
    func duplicatesDoNotCancel() throws {
        // Combining members with XOR would make these identical, since x ^ x == 0.
        let doubled = try digest(#"{"a":1,"a":1}"#)
        let empty = try digest("{}")
        let single = try digest(#"{"a":1}"#)
        #expect(doubled != empty)
        #expect(doubled != single)
    }

    @Test("a digest match is never taken as proof — equality still confirms")
    func digestIsNotAnOracle() throws {
        // The contract that keeps a collision from becoming a wrong answer: a digest match is
        // always confirmed with isStructurallyEqual. Shown here on a genuine match.
        let a = try tree(#"{"x":[1,2,3]}"#), b = try tree(#"{"x":[1,2,3]}"#)
        #expect(a.structuralDigest == b.structuralDigest)
        #expect(a.isStructurallyEqual(to: b))
    }

    @Test("deep nesting digests without exhausting the stack")
    func deepNesting() throws {
        let deep = String(repeating: "[", count: 500) + "1" + String(repeating: "]", count: 500)
        let other = String(repeating: "[", count: 500) + "2" + String(repeating: "]", count: 500)
        let a = try digest(deep), b = try digest(other), again = try digest(deep)
        #expect(a != b)
        #expect(a == again)
    }
}
