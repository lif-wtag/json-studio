/// Shared ground for the tree→tree transforms (`KeySorter`, `Pruner`).
///
/// # Spans survive a transform, and that is load-bearing
///
/// Every walker before these read the tree. A transform **rewrites** it, which raises a question
/// none of them had to answer: what happens to the spans of nodes that move or disappear?
///
/// **They are kept, unchanged, pointing into the original source.** Not because it is tidy, but
/// because the formatter depends on it. `Formatter` re-emits a string or a key by slicing the
/// **source text** at its span — that is what keeps `é` from becoming a literal `é` and `\/`
/// from becoming `/`. Rewriting or clearing spans during a sort would silently downgrade every
/// subsequent format from byte-exact to merely equivalent.
///
/// The consequence a caller must respect:
///
/// > A transformed tree describes values, not a document. Its spans still index the **original**
/// > source, so it must be formatted with **that same source**. Formatting it against the *output*
/// > of a previous format is a bug, and the mismatch is silent — the guard in `Formatter`'s
/// > literal writer will simply fall back to re-encoding, and the escapes will change.
///
/// Container spans go stale in a different way: after sorting, an object's span still covers the
/// region it originally occupied, which no longer holds its members in that order. Harmless, since
/// `Formatter` re-renders containers rather than slicing them, but it means a transformed tree is
/// **not** suitable for editor navigation. Re-parse the formatted output for that.
///
/// # Both transforms are iterative
///
/// ADR-01 Amendment 1a. Rebuilding a tree bottom-up is the natural shape for recursion, which is
/// exactly why it needed saying: the rebuild is a post-order walk over an explicit stack, the same
/// pattern `JSONNode.structuralDigest` uses.
enum TreeTransform {

    /// One step of a bottom-up rebuild.
    enum Work {
        case descend(JSONNode)
        /// Rebuild an object from the top `members.count` results, which arrive in member order.
        case closeObject(members: [JSONMember], span: SourceSpan)
        /// Rebuild an array from the top `count` results, in order.
        case closeArray(count: Int, span: SourceSpan)
    }

    /// Rebuilds `root` bottom-up, letting the caller decide what each container becomes.
    ///
    /// `rebuildObject` and `rebuildArray` receive children **already transformed**, and return
    /// `nil` to delete the container outright — which is how `Pruner` cascades: an object whose
    /// last member was dropped can itself be dropped, in the same pass, without a second walk.
    /// Scalars pass through untouched, spans and all.
    static func rebuild(
        _ root: JSONNode,
        rebuildObject: ([JSONMember], SourceSpan) -> JSONNode?,
        rebuildArray: ([JSONNode], SourceSpan) -> JSONNode?,
        keepScalar: (JSONNode) -> Bool = { _ in true }
    ) -> JSONNode? {
        var work: [Work] = [.descend(root)]
        // `nil` marks a child the transform deleted, so a parent can tell "dropped" from "kept".
        var results: [JSONNode?] = []

        while let item = work.popLast() {
            switch item {
            case .descend(let node):
                switch node.value {
                case .object(let members):
                    work.append(.closeObject(members: members, span: node.span))
                    // Reversed, so results land in member order.
                    for member in members.reversed() { work.append(.descend(member.node)) }
                case .array(let elements):
                    work.append(.closeArray(count: elements.count, span: node.span))
                    for element in elements.reversed() { work.append(.descend(element)) }
                default:
                    results.append(keepScalar(node) ? node : nil)
                }

            case .closeObject(let members, let span):
                let children = Array(results.suffix(members.count))
                results.removeLast(members.count)
                let kept = zip(members, children).compactMap { member, child in
                    child.map { JSONMember(key: member.key, keySpan: member.keySpan, node: $0) }
                }
                results.append(rebuildObject(kept, span))

            case .closeArray(let count, let span):
                let children = Array(results.suffix(count))
                results.removeLast(count)
                results.append(rebuildArray(children.compactMap { $0 }, span))
            }
        }
        return results.first ?? nil
    }
}
