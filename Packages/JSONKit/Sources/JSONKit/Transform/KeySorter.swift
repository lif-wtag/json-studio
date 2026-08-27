/// Sorts object keys, shallow or recursively (FM-06 / FM-07). A pure tree→tree transform.
///
/// **Only object keys move. Arrays are never reordered** — an array is a sequence, and sorting one
/// changes what the document says rather than how it is arranged. That is the whole distinction
/// this transform rests on, and it is the same one the diff makes when it treats key order as
/// meaningless and array order as meaningful.
///
/// **The order is `String`'s own, which is Unicode-canonical and locale-independent.** A localised
/// comparison would sort the same document differently on two machines, which for a tool whose
/// output gets committed and diffed would be a defect rather than a nicety.
///
/// **Sorting is stable**, so duplicate keys keep their relative order. Duplicates are legal JSON
/// and almost always a bug (VA-10); reordering them would destroy the evidence and could change
/// which value a consumer reads.
///
/// Spans are preserved — see `TreeTransform` for why that is load-bearing rather than tidy.
public struct KeySorter: Sendable {
    /// Sort nested objects too, including objects inside arrays.
    public var recursive: Bool

    public init(recursive: Bool = false) {
        self.recursive = recursive
    }

    public func sorted(_ node: JSONNode) -> JSONNode {
        guard recursive else { return sortedShallow(node) }
        // A sort never deletes anything, so the rebuild's optional returns are always non-nil.
        return TreeTransform.rebuild(
            node,
            rebuildObject: { members, span in
                JSONNode(value: .object(KeySorter.byKey(members)), span: span)
            },
            rebuildArray: { elements, span in
                JSONNode(value: .array(elements), span: span)
            }
        ) ?? node
    }

    /// Sorts only this node's own members (FM-06). Nested objects are left exactly as they are.
    private func sortedShallow(_ node: JSONNode) -> JSONNode {
        guard case .object(let members) = node.value else { return node }
        return JSONNode(value: .object(KeySorter.byKey(members)), span: node.span)
    }

    /// Stable sort by key. Swift's `sort` is not stable, so the original index breaks ties.
    private static func byKey(_ members: [JSONMember]) -> [JSONMember] {
        members.enumerated()
            .sorted { ($0.element.key, $0.offset) < ($1.element.key, $1.offset) }
            .map(\.element)
    }
}
