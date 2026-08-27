/// A JSON value together with the source span it occupies.
///
/// Spans are load-bearing, not decoration: error location, editor↔tree bidirectional selection,
/// path-from-cursor, bracket matching and click-to-highlight all read them (ADR-01). Half the
/// feature list dies without them, which is why the parser is hand-written.
public struct JSONNode: Sendable, Equatable {
    public var value: JSONValue
    /// Covers the whole value, opening through closing delimiter for containers.
    public var span: SourceSpan

    public init(value: JSONValue, span: SourceSpan) {
        self.value = value
        self.span = span
    }

    public var kind: JSONValue.Kind { value.kind }

    /// Direct children in document order, paired with the key each was reached by. Object
    /// children carry their key; array children carry nil.
    public var children: [(key: String?, node: JSONNode)] {
        switch value {
        case .object(let members): members.map { (key: $0.key, node: $0.node) }
        case .array(let elements): elements.map { (key: nil, node: $0) }
        default: []
        }
    }

    /// The innermost node whose span contains `offset`, searching depth-first.
    ///
    /// This is the editor-caret-to-tree-selection primitive (IN-06). It uses `touches` rather
    /// than `contains` at the top level so a caret resting on a closing brace still resolves to
    /// that container rather than to nothing.
    public func innermostNode(at offset: Int) -> JSONNode? {
        guard span.touches(offset) else { return nil }
        for (_, child) in children {
            if let deeper = child.innermostNode(at: offset) {
                return deeper
            }
        }
        return self
    }

    /// Depth of the deepest descendant, counting this node as 0.
    public var depth: Int {
        children.reduce(0) { max($0, $1.node.depth + 1) }
    }
}
