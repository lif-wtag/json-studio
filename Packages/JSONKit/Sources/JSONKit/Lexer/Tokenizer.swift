/// Hand-written tokenizer over UTF-16 code units. Produces `Token`s with exact spans,
/// handling string escapes and `\u` surrogate pairs and the RFC 8259 number grammar.
///
/// Phase 2: implement scanning; Phase 4 adds an incremental/streaming variant for
/// inspect-mode payloads.
public struct Tokenizer: Sendable {
    public init() {}

    /// Tokenize `source`, returning every token including a trailing `.endOfInput`.
    public func tokenize(_ source: String) -> [Token] {
        // TODO Phase 2
        _ = source
        return [Token(kind: .endOfInput, span: SourceSpan(start: 0, end: 0))]
    }
}
