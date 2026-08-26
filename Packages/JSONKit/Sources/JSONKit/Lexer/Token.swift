/// A lexical token with its source span (ADR-01: every token records where it came from).
public struct Token: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case beginObject   // {
        case endObject     // }
        case beginArray    // [
        case endArray      // ]
        case colon         // :
        case comma         // ,
        case string
        case number
        case literalTrue   // true
        case literalFalse  // false
        case literalNull   // null
        case invalid       // recovery: an unrecognised or malformed run
        case endOfInput
    }

    public var kind: Kind
    public var span: SourceSpan

    public init(kind: Kind, span: SourceSpan) {
        self.kind = kind
        self.span = span
    }
}
