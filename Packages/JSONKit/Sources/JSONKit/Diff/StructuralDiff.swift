/// Key-order-independent structural diff (ADR-07) — the feature that makes the app more than a
/// website. `{"a":1,"b":2}` and `{"b":2,"a":1}` compare as identical.
///
/// **Numbers compare by source text; strings compare by decoded value.** That asymmetry is
/// forced, not arbitrary. Decoding a string is lossless and total, so `"café"` and `"café"`
/// genuinely denote the same value and must not read as a change. Normalising a *number* would
/// mean parsing it, and no Swift numeric type holds every JSON number — `Double` rounds
/// `9007199254740993` down, so a numeric comparison would report two genuinely different integers
/// as equal. **A diff may be noisy; it may never claim two different values are the same.** So
/// `1` and `1.0` are reported as changed. Refining that needs arbitrary-precision comparison, not
/// `Double`, and is deliberately not attempted here.
///
/// **The walk is iterative** (ADR-01 Amendment 1a), over pairs of nodes.
///
/// **Array pairing is pluggable** — see `ArrayMatching` for what each strategy is right for. It
/// is a parameter rather than a guess because the compare workspace exposes it: for arrays of
/// records the difference between identity-key and index-wise matching is the difference between
/// a useful diff and noise.
public struct StructuralDiff: Sendable {
    public var arrayMatching: ArrayMatching

    /// Defaults to `.heuristic`: knowing nothing about the array, aligning on equal elements is
    /// the least-noisy assumption. `.index` and `.identityKey` are better when the caller knows
    /// which one applies, which is why the UI asks.
    public init(arrayMatching: ArrayMatching = .heuristic) {
        self.arrayMatching = arrayMatching
    }

    /// Every difference between the two documents.
    ///
    /// Order is deterministic: for each matched pair, that node's own added and removed members
    /// first (in left-document order, then keys only present on the right), followed by the
    /// differences inside its matched members, depth-first with children in order. The compare
    /// workspace re-orders for display; the domain only promises stability.
    ///
    /// Throws `CancellationError` if cancelled — a 1 MB × 1 MB diff is budgeted at 500 ms, long
    /// enough that a partial answer would otherwise be shown (ADR-09).
    public func diff(_ lhs: JSONNode, _ rhs: JSONNode) throws -> [DiffChange] {
        var changes: [DiffChange] = []
        var stack: [(before: JSONNode, after: JSONNode, path: JSONPath)] = [(lhs, rhs, .root)]
        var sinceCancellationCheck = 0

        while let (before, after, path) = stack.popLast() {
            sinceCancellationCheck += 1
            if sinceCancellationCheck >= 4096 {
                sinceCancellationCheck = 0
                try Task.checkCancellation()
            }

            // A type change is reported instead of recursing: a string that became an object has
            // no meaningful child-level diff, and descending would bury the real change in noise.
            guard before.kind == after.kind else {
                changes.append(DiffChange(
                    kind: .typeChanged, path: path, before: before, after: after
                ))
                continue
            }

            switch (before.value, after.value) {
            case (.object(let left), .object(let right)):
                compareObjects(left, right, at: path, into: &changes, pushing: &stack)

            case (.array(let left), .array(let right)):
                compareArrays(left, right, at: path, into: &changes, pushing: &stack)

            case (.string(let a), .string(let b)):
                if a != b { changes.append(modified(path, before, after)) }

            case (.number(let a), .number(let b)):
                if a != b { changes.append(modified(path, before, after)) }

            case (.bool(let a), .bool(let b)):
                if a != b { changes.append(modified(path, before, after)) }

            case (.null, .null):
                break

            default:
                break   // unreachable: equal kinds mean the pairs align
            }
        }
        return changes
    }

    /// `true` when the two documents are structurally identical.
    public func isIdentical(_ lhs: JSONNode, _ rhs: JSONNode) throws -> Bool {
        try diff(lhs, rhs).isEmpty
    }

    private func modified(_ path: JSONPath, _ before: JSONNode, _ after: JSONNode) -> DiffChange {
        DiffChange(kind: .modified, path: path, before: before, after: after)
    }

    // MARK: Objects

    /// **Key-order independence lives here** (CP-02): members are paired by key, never by
    /// position, so `{"a":1,"b":2}` and `{"b":2,"a":1}` produce nothing.
    ///
    /// Duplicate keys are legal JSON and almost always a bug (VA-10), so they are handled rather
    /// than assumed away: members sharing a key are paired **positionally within that key group**,
    /// and any surplus on either side is reported added or removed. Those changes share one path —
    /// the ambiguity `JSONPath` documents — which is another reason the compare workspace
    /// navigates by span.
    private func compareObjects(
        _ left: [JSONMember],
        _ right: [JSONMember],
        at path: JSONPath,
        into changes: inout [DiffChange],
        pushing stack: inout [(before: JSONNode, after: JSONNode, path: JSONPath)]
    ) {
        var leftByKey: [String: [JSONNode]] = [:]
        var rightByKey: [String: [JSONNode]] = [:]
        for member in left { leftByKey[member.key, default: []].append(member.node) }
        for member in right { rightByKey[member.key, default: []].append(member.node) }

        // Left-document order first, then keys only on the right — so the output is stable and
        // reads in the order someone scanning the left document would meet the changes.
        var seen = Set<String>()
        var keys: [String] = []
        for member in left where seen.insert(member.key).inserted { keys.append(member.key) }
        for member in right where seen.insert(member.key).inserted { keys.append(member.key) }

        var pending: [(JSONNode, JSONNode, JSONPath)] = []
        for key in keys {
            let mine = leftByKey[key] ?? []
            let theirs = rightByKey[key] ?? []
            let childPath = JSONPath(path.components + [.key(key)])
            let paired = min(mine.count, theirs.count)

            for i in 0..<paired { pending.append((mine[i], theirs[i], childPath)) }
            for i in paired..<mine.count {
                changes.append(DiffChange(kind: .removed, path: childPath, before: mine[i]))
            }
            for i in paired..<theirs.count {
                changes.append(DiffChange(kind: .added, path: childPath, after: theirs[i]))
            }
        }
        // Reversed, because the stack pops last-in-first: this makes children come out in order.
        stack.append(contentsOf: pending.reversed().map { (before: $0.0, after: $0.1, path: $0.2) })
    }

    // MARK: Arrays

    /// How one element on each side lines up. Producing pairings first, then turning them into
    /// changes, is what lets the three strategies share everything except the pairing itself.
    private enum Pairing {
        case matched(left: Int, right: Int)
        case removed(left: Int)
        case added(right: Int)
    }

    private func compareArrays(
        _ left: [JSONNode],
        _ right: [JSONNode],
        at path: JSONPath,
        into changes: inout [DiffChange],
        pushing stack: inout [(before: JSONNode, after: JSONNode, path: JSONPath)]
    ) {
        let pairings: [Pairing]
        switch arrayMatching {
        case .index:
            pairings = positionalPairings(leftCount: left.count, rightCount: right.count)
        case .identityKey(let key):
            pairings = identityPairings(left, right, key: key)
        case .heuristic:
            pairings = heuristicPairings(left, right)
        }
        apply(pairings, left, right, at: path, into: &changes, pushing: &stack)
    }

    /// Turns pairings into changes and further work.
    ///
    /// Paths use the **left** index for a matched or removed element and the **right** index for an
    /// added one, because that is the index at which a reader will find it in the document they are
    /// looking at. A matched pair whose indices differ — an element that moved — is compared for
    /// content and reported only if its content changed; there is no "moved" semantic to render.
    private func apply(
        _ pairings: [Pairing],
        _ left: [JSONNode],
        _ right: [JSONNode],
        at path: JSONPath,
        into changes: inout [DiffChange],
        pushing stack: inout [(before: JSONNode, after: JSONNode, path: JSONPath)]
    ) {
        var pending: [(JSONNode, JSONNode, JSONPath)] = []
        for pairing in pairings {
            switch pairing {
            case .matched(let l, let r):
                pending.append((left[l], right[r], JSONPath(path.components + [.index(l)])))
            case .removed(let l):
                changes.append(DiffChange(
                    kind: .removed, path: JSONPath(path.components + [.index(l)]), before: left[l]
                ))
            case .added(let r):
                changes.append(DiffChange(
                    kind: .added, path: JSONPath(path.components + [.index(r)]), after: right[r]
                ))
            }
        }
        // Reversed, because the stack pops last-in-first: this makes children come out in order.
        stack.append(contentsOf: pending.reversed().map { (before: $0.0, after: $0.1, path: $0.2) })
    }

    private func positionalPairings(leftCount: Int, rightCount: Int) -> [Pairing] {
        let paired = min(leftCount, rightCount)
        var pairings: [Pairing] = (0..<paired).map { .matched(left: $0, right: $0) }
        pairings += (paired..<leftCount).map { .removed(left: $0) }
        pairings += (paired..<rightCount).map { .added(right: $0) }
        return pairings
    }

    /// Positional pairing over two index ranges rather than two whole arrays — used inside the
    /// gaps the heuristic leaves between its anchors, and by identity matching for the leftovers.
    private func positionalPairings(_ lefts: [Int], _ rights: [Int]) -> [Pairing] {
        let paired = min(lefts.count, rights.count)
        var pairings: [Pairing] = (0..<paired).map { .matched(left: lefts[$0], right: rights[$0]) }
        pairings += lefts.dropFirst(paired).map { .removed(left: $0) }
        pairings += rights.dropFirst(paired).map { .added(right: $0) }
        return pairings
    }

    // MARK: Identity-key matching

    /// Pairs elements by the value of `key`, so a reordered array of records is not a change.
    ///
    /// The match key is the identity value's **fingerprint**, which for a scalar is complete
    /// equality. An identity value that is itself a container cannot be a sensible identity, so
    /// such elements — along with non-objects and objects missing the key — are set aside and
    /// paired positionally among themselves. That keeps a partly-keyed array useful instead of
    /// reporting every unkeyed element as removed-and-added.
    ///
    /// Duplicate identity values are paired positionally within their group, the same rule the
    /// object comparison uses for duplicate keys.
    private func identityPairings(
        _ left: [JSONNode], _ right: [JSONNode], key: String
    ) -> [Pairing] {
        func identity(_ node: JSONNode) -> ShallowFingerprint? {
            guard case .object = node.value,
                  let member = node.value.member(key),
                  !member.node.value.isContainer
            else { return nil }
            return member.node.shallowFingerprint
        }

        var leftByIdentity: [ShallowFingerprint: [Int]] = [:]
        var unkeyedLeft: [Int] = []
        for (index, element) in left.enumerated() {
            if let id = identity(element) { leftByIdentity[id, default: []].append(index) }
            else { unkeyedLeft.append(index) }
        }

        var rightByIdentity: [ShallowFingerprint: [Int]] = [:]
        var unkeyedRight: [Int] = []
        for (index, element) in right.enumerated() {
            if let id = identity(element) { rightByIdentity[id, default: []].append(index) }
            else { unkeyedRight.append(index) }
        }

        var pairings: [Pairing] = []
        var matchedRight = Set<Int>()

        // Left-document order, so the output reads in the order a reader meets the elements.
        for index in left.indices {
            guard let id = identity(left[index]) else { continue }
            guard let candidates = rightByIdentity[id], !candidates.isEmpty else {
                pairings.append(.removed(left: index))
                continue
            }
            // Positional within the identity group: the nth left element with this id pairs with
            // the nth right one.
            let position = (leftByIdentity[id] ?? []).firstIndex(of: index) ?? 0
            if position < candidates.count {
                let partner = candidates[position]
                matchedRight.insert(partner)
                pairings.append(.matched(left: index, right: partner))
            } else {
                pairings.append(.removed(left: index))
            }
        }
        for index in right.indices {
            guard identity(right[index]) != nil else { continue }
            if !matchedRight.contains(index) { pairings.append(.added(right: index)) }
        }
        pairings += positionalPairings(unkeyedLeft, unkeyedRight)
        return pairings
    }

    // MARK: Heuristic (LCS) matching

    /// Beyond this many DP cells the LCS is abandoned for positional pairing. Common prefixes and
    /// suffixes are stripped first, so reaching it takes two large arrays that differ throughout.
    ///
    /// **The bound is memory, not time.** Once elements are digested the table fills fast — 2000 ×
    /// 2000 all-different measures 17 ms — but the table itself is `Int32` per cell, so this cap
    /// is 16 MB. Raising it trades a quadratic allocation for an alignment nobody asked for on an
    /// array that size. Documented rather than silent: `heuristicWasExact(leftCount:rightCount:)`
    /// lets a caller ask in advance.
    public static let heuristicCellLimit = 4_000_000

    /// Whether `.heuristic` will compute an exact alignment for arrays of these sizes, or fall
    /// back to positional pairing. Only the middle — after common prefix and suffix — counts, so
    /// this is a conservative answer.
    public static func heuristicWasExact(leftCount: Int, rightCount: Int) -> Bool {
        leftCount * rightCount <= heuristicCellLimit
    }

    /// Aligns on equal elements, then pairs positionally inside each gap.
    ///
    /// The second half matters as much as the first. A plain LCS matches only *identical*
    /// elements, so an element edited in place would come back as a removal plus an addition —
    /// worse than index-wise, which would have called it `modified`. Pairing what is left inside
    /// each gap recovers that, and the result is strictly better than either: an insertion is one
    /// addition, an edit is one modification.
    private func heuristicPairings(_ left: [JSONNode], _ right: [JSONNode]) -> [Pairing] {
        // Digested once each, so every table cell is an integer compare rather than a subtree
        // walk. Without this the LCS measured 493 ms on a 1 MB pair against a 500 ms budget.
        let leftDigests = left.map(\.structuralDigest)
        let rightDigests = right.map(\.structuralDigest)
        func equal(_ l: Int, _ r: Int) -> Bool {
            leftDigests[l] == rightDigests[r] && left[l].isStructurallyEqual(to: right[r])
        }

        var pairings: [Pairing] = []

        // Common prefix and suffix. Cheap, and it usually shrinks the LCS to nothing.
        var prefix = 0
        while prefix < left.count, prefix < right.count, equal(prefix, prefix) {
            pairings.append(.matched(left: prefix, right: prefix))
            prefix += 1
        }
        var suffix = 0
        while prefix + suffix < left.count, prefix + suffix < right.count,
              equal(left.count - 1 - suffix, right.count - 1 - suffix) {
            suffix += 1
        }

        let leftMiddle = Array(prefix..<(left.count - suffix))
        let rightMiddle = Array(prefix..<(right.count - suffix))

        if leftMiddle.isEmpty || rightMiddle.isEmpty {
            pairings += positionalPairings(leftMiddle, rightMiddle)
        } else if !Self.heuristicWasExact(leftCount: leftMiddle.count, rightCount: rightMiddle.count) {
            pairings += positionalPairings(leftMiddle, rightMiddle)
        } else {
            pairings += alignByLCS(leftMiddle, rightMiddle, equal)
        }

        for offset in 0..<suffix {
            let l = left.count - suffix + offset
            let r = right.count - suffix + offset
            pairings.append(.matched(left: l, right: r))
        }
        return pairings
    }

    private func alignByLCS(
        _ leftIndices: [Int], _ rightIndices: [Int], _ equal: (Int, Int) -> Bool
    ) -> [Pairing] {
        let n = leftIndices.count, m = rightIndices.count

        // table[i][j] = LCS length of leftIndices[i...] and rightIndices[j...], as one flat array.
        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                let here = i * (m + 1) + j
                if equal(leftIndices[i], rightIndices[j]) {
                    table[here] = table[(i + 1) * (m + 1) + (j + 1)] + 1
                } else {
                    table[here] = max(table[(i + 1) * (m + 1) + j], table[here + 1])
                }
            }
        }

        // Walk the table, collecting anchors and the gaps between them.
        var pairings: [Pairing] = []
        var gapLeft: [Int] = [], gapRight: [Int] = []
        var i = 0, j = 0
        while i < n && j < m {
            if equal(leftIndices[i], rightIndices[j]) {
                pairings += positionalPairings(gapLeft, gapRight)
                gapLeft.removeAll(); gapRight.removeAll()
                pairings.append(.matched(left: leftIndices[i], right: rightIndices[j]))
                i += 1; j += 1
            } else if table[(i + 1) * (m + 1) + j] >= table[i * (m + 1) + (j + 1)] {
                gapLeft.append(leftIndices[i]); i += 1
            } else {
                gapRight.append(rightIndices[j]); j += 1
            }
        }
        gapLeft += leftIndices[i...]
        gapRight += rightIndices[j...]
        pairings += positionalPairings(gapLeft, gapRight)
        return pairings
    }

}
