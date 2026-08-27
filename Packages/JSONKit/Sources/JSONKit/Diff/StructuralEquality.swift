extension JSONNode {
    /// Structural equality: same shape and same values, **ignoring source positions and key
    /// order**.
    ///
    /// This exists because `==` is the wrong tool and looks like the right one. `JSONValue`'s
    /// synthesized `Equatable` compares a container's children, which are `JSONNode`s and
    /// `JSONMember`s — and those carry **spans**. So two structurally identical documents at
    /// different offsets are `!=`, and reformatting a file makes every container in it unequal to
    /// its former self. Anything comparing *values* rather than *provenance* wants this instead.
    ///
    /// Key order is ignored, for the same reason the diff ignores it (CP-02): `{"a":1,"b":2}` and
    /// `{"b":2,"a":1}` are the same object. Array order is **not** ignored — arrays are sequences.
    ///
    /// Iterative, per ADR-01 Amendment 1a. Short-circuits on the first difference.
    public func isStructurallyEqual(to other: JSONNode) -> Bool {
        var stack: [(JSONNode, JSONNode)] = [(self, other)]

        while let (lhs, rhs) = stack.popLast() {
            guard lhs.kind == rhs.kind else { return false }

            switch (lhs.value, rhs.value) {
            case (.object(let left), .object(let right)):
                guard left.count == right.count else { return false }
                // Group by key so duplicates are compared positionally within their group,
                // matching how the diff pairs them.
                var rightByKey: [String: [JSONNode]] = [:]
                for member in right { rightByKey[member.key, default: []].append(member.node) }
                var leftByKey: [String: [JSONNode]] = [:]
                for member in left { leftByKey[member.key, default: []].append(member.node) }
                guard leftByKey.count == rightByKey.count else { return false }
                for (key, mine) in leftByKey {
                    guard let theirs = rightByKey[key], theirs.count == mine.count else {
                        return false
                    }
                    for index in mine.indices { stack.append((mine[index], theirs[index])) }
                }

            case (.array(let left), .array(let right)):
                guard left.count == right.count else { return false }
                for index in left.indices { stack.append((left[index], right[index])) }

            case (.string(let a), .string(let b)):
                if a != b { return false }
            case (.number(let a), .number(let b)):
                // Source text, for the reason StructuralDiff documents: no Swift numeric type
                // holds every JSON number, so normalising could call two different values equal.
                if a != b { return false }
            case (.bool(let a), .bool(let b)):
                if a != b { return false }
            case (.null, .null):
                break
            default:
                return false   // unreachable: equal kinds mean the pairs align
            }
        }
        return true
    }

    /// A cheap, one-level discriminator. Two nodes with different fingerprints are certainly
    /// different; equal fingerprints mean "worth a full comparison".
    ///
    /// Deliberately **shallow**: it costs one pass over the direct children rather than the whole
    /// subtree, which is what makes the array-matching comparisons affordable. A deep digest would
    /// be a second tree walk per element — and hashing a subtree to decide equality outright would
    /// let a collision claim two different values are the same, which the diff must never do.
    var shallowFingerprint: ShallowFingerprint {
        switch value {
        case .object(let members):
            var keyHash = 0
            // XOR so the hash is order-insensitive, matching key-order independence.
            for member in members { keyHash ^= member.key.hashValue }
            return ShallowFingerprint(kind: .object, childCount: members.count, keyHash: keyHash)
        case .array(let elements):
            return ShallowFingerprint(kind: .array, childCount: elements.count)
        case .string(let text):
            return ShallowFingerprint(kind: .string, scalar: text)
        case .number(let text):
            return ShallowFingerprint(kind: .number, scalar: text)
        case .bool(let flag):
            return ShallowFingerprint(kind: .boolean, scalar: flag ? "true" : "false")
        case .null:
            return ShallowFingerprint(kind: .null)
        }
    }
}

/// See `JSONNode.shallowFingerprint`. For scalars this *is* complete equality; for containers it
/// is a filter.
struct ShallowFingerprint: Hashable {
    var kind: JSONValue.Kind
    var childCount = 0
    var keyHash = 0
    var scalar: String?

    init(kind: JSONValue.Kind, childCount: Int = 0, keyHash: Int = 0, scalar: String? = nil) {
        self.kind = kind
        self.childCount = childCount
        self.keyHash = keyHash
        self.scalar = scalar
    }
}

extension JSONNode {
    /// A structural digest of the whole subtree: equal structure gives equal digests, and key
    /// order is ignored. Computed **iteratively**, in one pass (ADR-01 Amendment 1a).
    ///
    /// This exists for the LCS matcher's benefit. Comparing two arrays element-by-element with
    /// `isStructurallyEqual(to:)` costs a subtree walk **per cell** of an n×m table, which measured
    /// at 493 ms on a 1 MB pair against a 500 ms budget and 2.1 s on a wide array that differs
    /// throughout. Digesting each element once turns every cell into an integer compare.
    ///
    /// **A digest match is never taken as proof.** Two different subtrees can collide, and a diff
    /// that reported different values as identical would be worse than a slow one — so a match is
    /// always confirmed with `isStructurallyEqual(to:)`. The digest is an accelerator, not an
    /// oracle, which is the same reason numbers are compared as text rather than as `Double`.
    public var structuralDigest: Int {
        /// Post-order over an explicit stack: children are digested, then combined by their parent.
        enum Work {
            case descend(JSONNode)
            /// Combine the top `keys.count` results as an object's members.
            case closeObject(keys: [Int])
            /// Combine the top `count` results as an array's elements, in order.
            case closeArray(count: Int)
        }

        var work: [Work] = [.descend(self)]
        var results: [Int] = []

        while let item = work.popLast() {
            switch item {
            case .descend(let node):
                switch node.value {
                case .object(let members):
                    work.append(.closeObject(keys: members.map { $0.key.hashValue }))
                    // Reversed, so results land in `results` in member order.
                    for member in members.reversed() { work.append(.descend(member.node)) }
                case .array(let elements):
                    work.append(.closeArray(count: elements.count))
                    for element in elements.reversed() { work.append(.descend(element)) }
                case .string(let text):
                    results.append(mix(0x51, text.hashValue))
                case .number(let text):
                    results.append(mix(0x52, text.hashValue))
                case .bool(let flag):
                    results.append(mix(0x53, flag ? 1 : 0))
                case .null:
                    results.append(mix(0x54, 0))
                }

            case .closeObject(let keys):
                let children = results.suffix(keys.count)
                results.removeLast(keys.count)
                // **Addition, so member order cannot matter** — and unlike XOR, a duplicated
                // member accumulates instead of cancelling itself out.
                var combined = mix(0x01, keys.count)
                for (key, child) in zip(keys, children) {
                    combined = combined &+ mix(key, child)
                }
                results.append(combined)

            case .closeArray(let count):
                let children = results.suffix(count)
                results.removeLast(count)
                // Sequential, because array order IS meaningful.
                var combined = mix(0x02, count)
                for child in children { combined = combined &* 31 &+ child }
                results.append(combined)
            }
        }
        return results.first ?? 0
    }
}

/// A cheap 2-to-1 mix. Not cryptographic and does not need to be — collisions cost a confirming
/// comparison, never a wrong answer.
private func mix(_ a: Int, _ b: Int) -> Int {
    var h = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
    h ^= UInt64(bitPattern: Int64(b)) &* 0xC2B2_AE3D_27D4_EB4F
    h ^= h >> 29
    h = h &* 0xBF58_476D_1CE4_E5B9
    h ^= h >> 32
    return Int(bitPattern: UInt(truncatingIfNeeded: h))
}
