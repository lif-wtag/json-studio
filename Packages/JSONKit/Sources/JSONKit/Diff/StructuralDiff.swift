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
/// **Arrays are index-wise in this version.** `ArrayMatching.identityKey` and `.heuristic` are
/// Task 10; until then they behave as `.index`, which `ArrayMatching.isImplemented` reports and a
/// test asserts.
public struct StructuralDiff: Sendable {
    public var arrayMatching: ArrayMatching

    /// Defaults to `.index` — the only strategy implemented so far. Task 10 restores `.heuristic`
    /// as the default, since it is the right guess when nothing is known about the array.
    public init(arrayMatching: ArrayMatching = .index) {
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

    /// Index-wise pairing. Task 10 adds identity-key and LCS matching; see `ArrayMatching` for why
    /// index-wise turns a single insertion into a cascade of changes on arrays of records.
    private func compareArrays(
        _ left: [JSONNode],
        _ right: [JSONNode],
        at path: JSONPath,
        into changes: inout [DiffChange],
        pushing stack: inout [(before: JSONNode, after: JSONNode, path: JSONPath)]
    ) {
        let paired = min(left.count, right.count)
        var pending: [(JSONNode, JSONNode, JSONPath)] = []

        for index in 0..<paired {
            pending.append((left[index], right[index], JSONPath(path.components + [.index(index)])))
        }
        for index in paired..<left.count {
            changes.append(DiffChange(
                kind: .removed, path: JSONPath(path.components + [.index(index)]), before: left[index]
            ))
        }
        for index in paired..<right.count {
            changes.append(DiffChange(
                kind: .added, path: JSONPath(path.components + [.index(index)]), after: right[index]
            ))
        }
        stack.append(contentsOf: pending.reversed().map { (before: $0.0, after: $0.1, path: $0.2) })
    }
}
