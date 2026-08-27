/// The result of a parse: a (possibly partial) tree plus every error encountered.
///
/// Both fields are populated together (ADR-02) — the parser recovers rather than throwing,
/// so a live editor always has a tree to show even while the document is invalid mid-edit.
public struct ParseResult: Sendable {
    public var tree: JSONNode?
    /// Lexical and structural errors together, in **cause** order (see `Parser`).
    public var errors: [ParseError]
    /// Built during tokenization, carried here so the UI can derive every line and column
    /// without a second scan of the document. `ParseError` deliberately stores neither (ADR-01).
    public var lineIndex: LineIndex
    /// Set when cooperative cancellation cut the parse short (ADR-09). The tree is then a
    /// truncated fragment, so it must not be mistaken for a successful parse.
    public var wasCancelled: Bool

    public init(
        tree: JSONNode?,
        errors: [ParseError],
        lineIndex: LineIndex = LineIndex(),
        wasCancelled: Bool = false
    ) {
        self.tree = tree
        self.errors = errors
        self.lineIndex = lineIndex
        self.wasCancelled = wasCancelled
    }

    public var isValid: Bool { errors.isEmpty && tree != nil && !wasCancelled }

    /// `true` for a document with nothing in it — the state of every new window, and not an
    /// error. The status bar says "Empty document"; `isValid` is false but there is nothing to fix.
    public var isEmpty: Bool { tree == nil && errors.isEmpty && !wasCancelled }
}
