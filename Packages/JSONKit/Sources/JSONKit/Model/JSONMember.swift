/// One key/value member of a JSON object. The key carries its **own** span (`keySpan`)
/// distinct from the value's span, so the inspector can select and copy a key independently
/// of its value.
public struct JSONMember: Sendable, Equatable {
    public var key: String
    public var keySpan: SourceSpan
    public var node: JSONNode

    public init(key: String, keySpan: SourceSpan, node: JSONNode) {
        self.key = key
        self.keySpan = keySpan
        self.node = node
    }
}
