/// Sorts object keys, shallow or recursively (FM-06 / FM-07). A pure tree→tree transform.
public struct KeySorter: Sendable {
    public var recursive: Bool

    public init(recursive: Bool = false) {
        self.recursive = recursive
    }

    public func sorted(_ node: JSONNode) -> JSONNode {
        // TODO Phase 4
        node
    }
}
