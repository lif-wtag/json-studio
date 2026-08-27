/// One key/value member of a JSON object.
///
/// The key carries its **own** span, distinct from the value's, so the inspector can select and
/// copy a key independently of its value — and so an error about a key ("put double quotes around
/// this") can underline exactly the key and nothing else.
public struct JSONMember: Sendable, Equatable {
    /// Decoded key text, escapes resolved. See `JSONValue` on why decoding happens here.
    public var key: String
    /// Covers the key *including* its quotes.
    public var keySpan: SourceSpan
    public var node: JSONNode

    public init(key: String, keySpan: SourceSpan, node: JSONNode) {
        self.key = key
        self.keySpan = keySpan
        self.node = node
    }

    /// Key through value — what a "copy this property" command should take, and what a diff
    /// highlights when a whole member is added or removed.
    public var span: SourceSpan {
        keySpan.union(node.span)
    }
}
