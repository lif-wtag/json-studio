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
        /// A bare word the tokenizer could not classify — `region`, `True`, `NaN`. The tokenizer
        /// deliberately does not decide what it *means*: as an object key it is an unquoted key,
        /// elsewhere it is something else entirely, and only the parser knows which.
        case identifier
        /// Recovery: a run of characters that cannot begin any token.
        case invalid
        case endOfInput
    }

    /// Values the tokenizer has already computed, so the parser never re-scans the source.
    public enum Payload: Sendable, Equatable {
        /// A string's **decoded** value — escapes resolved, surrogate pairs combined.
        case string(String)
        /// A number's **source text**, preserved exactly (see `JSONValue`).
        case number(String)
        /// A bare word's text, for `identifier` and `invalid`.
        case text(String)
    }

    public var kind: Kind
    public var span: SourceSpan
    public var payload: Payload?

    public init(kind: Kind, span: SourceSpan, payload: Payload? = nil) {
        self.kind = kind
        self.span = span
        self.payload = payload
    }

    /// The decoded text of a string token, or a bare word's text. Nil for everything else.
    public var stringValue: String? {
        switch payload {
        case .string(let s), .text(let s): s
        default: nil
        }
    }

    /// The source text of a number token.
    public var numberText: String? {
        if case .number(let s) = payload { return s }
        return nil
    }

    /// `true` for tokens that can begin a JSON value — what the parser's recovery uses to decide
    /// whether it has found somewhere to resume.
    public var canBeginValue: Bool {
        switch kind {
        case .beginObject, .beginArray, .string, .number,
             .literalTrue, .literalFalse, .literalNull:
            true
        default:
            false
        }
    }
}
