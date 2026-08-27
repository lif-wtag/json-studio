/// Resolves between source offsets and paths, in both directions:
///  - `path(at:)`  — the JSON path of the innermost node containing a UTF-16 offset
///                   (drives editor cursor → tree selection, IN-06, and the path bar, IN-15).
///  - `resolve(_:)` / `span(of:)` — what a path points at
///                   (drives tree selection → editor highlight, IN-05).
///
/// **A caret inside a key resolves to that key's member, not to the enclosing object.** The
/// member's own span stops at its value, so an offset-in-key test against value spans alone
/// would answer "the object" — and clicking a property name in the editor would select its
/// parent, which is useless. So the descent tests `JSONMember.span` (key through value) and
/// then stops if the offset never reaches the value.
///
/// Both directions are iterative. The parser gave up recursion for a measured reason — a debug
/// build's 512 KB concurrency-thread stack — and while a walker's frames are far smaller than
/// the parser's were, there is no reason for a resolver called on every cursor move to carry any
/// stack risk at all.
public struct PathResolver: Sendable {
    public let root: JSONNode

    public init(root: JSONNode) {
        self.root = root
    }

    /// Everything the inspector needs about one resolved path, from a single walk.
    public struct Resolution: Sendable, Equatable {
        public var node: JSONNode
        /// The key's own span, quotes included. Nil for the root and for array elements.
        public var keySpan: SourceSpan?

        public init(node: JSONNode, keySpan: SourceSpan?) {
            self.node = node
            self.keySpan = keySpan
        }

        /// The value alone — what "highlight this node" and "copy value" want.
        public var span: SourceSpan { node.span }

        /// Key through value — what "copy this property" wants, and what a diff highlights when
        /// a whole member is added or removed.
        public var memberSpan: SourceSpan {
            keySpan.map { $0.union(node.span) } ?? node.span
        }
    }

    // MARK: Offset → path

    /// The path of the innermost node containing `offset`, or nil when the offset falls outside
    /// the document. An offset anywhere in the root that is in no child returns `$`.
    public func path(at offset: Int) -> JSONPath? {
        guard root.span.touches(offset) else { return nil }

        var components: [JSONPath.Component] = []
        var node = root

        while true {
            switch node.value {
            case .object(let members):
                // Members are disjoint and in document order, so the first that touches wins.
                guard let member = members.first(where: { $0.span.touches(offset) }) else {
                    return JSONPath(components)
                }
                components.append(.key(member.key))
                // In the key, the colon, or the whitespace between: the member is the answer and
                // there is nothing deeper to descend into.
                guard member.node.span.touches(offset) else { return JSONPath(components) }
                node = member.node

            case .array(let elements):
                guard let match = elements.enumerated().first(where: { $0.element.span.touches(offset) })
                else {
                    return JSONPath(components)
                }
                components.append(.index(match.offset))
                node = match.element

            default:
                return JSONPath(components)
            }
        }
    }

    // MARK: Path → span

    /// Walks `path` from the root. Returns nil when any component doesn't exist — a key that was
    /// renamed, an index past the end of a shortened array — rather than trapping, because the
    /// inspector's selection routinely outlives the edit that invalidated it.
    public func resolve(_ path: JSONPath) -> Resolution? {
        var node = root
        var keySpan: SourceSpan?

        for component in path.components {
            switch component {
            case .key(let key):
                guard case .object(let members) = node.value,
                      let member = members.first(where: { $0.key == key })
                else { return nil }
                node = member.node
                keySpan = member.keySpan

            case .index(let index):
                guard case .array(let elements) = node.value,
                      elements.indices.contains(index)
                else { return nil }
                node = elements[index]
                keySpan = nil
            }
        }
        return Resolution(node: node, keySpan: keySpan)
    }

    /// The span a path points at — the value, not the key. `resolve(_:)` exposes both.
    public func span(of path: JSONPath) -> SourceSpan? {
        resolve(path)?.span
    }
}
