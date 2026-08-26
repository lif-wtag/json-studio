/// Error-recovering recursive-descent parser (ADR-02).
///
/// Never throws on the first error: on a syntax error it records a `ParseError`, skips to the
/// next plausible sync point (`,` `}` `]` at the current depth) and continues, so the returned
/// tree is as complete as the input allows. Runs off the main actor with cooperative
/// cancellation (ADR-09).
public struct Parser: Sendable {
    public init() {}

    /// Parse `source` into a partial tree plus the list of recovered errors.
    public func parse(_ source: String) -> ParseResult {
        // TODO Phase 2: tokenize via Tokenizer, then recursive descent with recovery.
        _ = source
        return ParseResult(tree: nil, errors: [])
    }
}
