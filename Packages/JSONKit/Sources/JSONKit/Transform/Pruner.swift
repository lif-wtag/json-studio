/// Strips nulls, empty strings, and empty collections from a tree (FM-08). Each rule is
/// independently toggleable so the UI can offer them separately.
public struct Pruner: Sendable {
    public var stripNulls: Bool
    public var stripEmptyStrings: Bool
    public var stripEmptyCollections: Bool

    public init(stripNulls: Bool = true, stripEmptyStrings: Bool = false, stripEmptyCollections: Bool = false) {
        self.stripNulls = stripNulls
        self.stripEmptyStrings = stripEmptyStrings
        self.stripEmptyCollections = stripEmptyCollections
    }

    public func pruned(_ node: JSONNode) -> JSONNode {
        // TODO Phase 4
        node
    }
}
