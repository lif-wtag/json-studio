/// Key-order-independent structural diff (ADR-07) — the feature that makes the app more than a
/// website. `{"a":1,"b":2}` and `{"b":2,"a":1}` compare as identical.
public struct StructuralDiff: Sendable {
    public var arrayMatching: ArrayMatching

    public init(arrayMatching: ArrayMatching = .heuristic) {
        self.arrayMatching = arrayMatching
    }

    public func diff(_ lhs: JSONNode, _ rhs: JSONNode) -> [DiffChange] {
        // TODO Phase 2
        _ = (lhs, rhs)
        return []
    }
}
