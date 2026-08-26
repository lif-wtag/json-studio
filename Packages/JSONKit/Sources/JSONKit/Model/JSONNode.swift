/// A JSON value together with the source span it occupies. Spans are load-bearing for error
/// location, editor↔tree bidirectional selection, and path-from-cursor (ADR-01).
public struct JSONNode: Sendable, Equatable {
    public var value: JSONValue
    public var span: SourceSpan

    public init(value: JSONValue, span: SourceSpan) {
        self.value = value
        self.span = span
    }
}
