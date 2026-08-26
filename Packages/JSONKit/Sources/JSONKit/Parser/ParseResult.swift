/// The result of a parse: a (possibly partial) tree plus every error encountered.
///
/// Both fields are populated together (ADR-02) — the parser recovers rather than throwing,
/// so a live editor always has a tree to show even while the document is invalid mid-edit.
public struct ParseResult: Sendable {
    public var tree: JSONNode?
    public var errors: [ParseError]

    public init(tree: JSONNode?, errors: [ParseError]) {
        self.tree = tree
        self.errors = errors
    }

    public var isValid: Bool { errors.isEmpty && tree != nil }
}
