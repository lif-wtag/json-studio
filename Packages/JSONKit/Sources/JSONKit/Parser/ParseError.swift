/// A single syntax error.
///
/// **The cause and the detection point are separate fields, and that separation is the product.**
/// Phase 0 found that every competing tool reports the position where its parser *noticed* a
/// problem rather than where the problem is — a missing comma gets flagged at the next property
/// name, and the workaround developers actually use is "check one line before". `span` is where
/// the fix goes; `detectedAt` is where the parser noticed, present only when the two differ.
///
/// **No stored line or column.** ADR-01 says derive them from `LineIndex` at the point of display.
/// A stored line number is wrong the moment the document is edited above it.
///
/// **No stored message.** The project contract forbids improvising error copy in code, so
/// the parser chooses a `kind` and fills in `context`; the strings live in `ParseErrorCopy`,
/// transcribed verbatim from `Design/error-copy.md`.
public struct ParseError: Sendable, Equatable, Error {

    /// The thirteen errors from `Design/error-copy.md`. Adding a fourteenth is a design change:
    /// add the copy there first, then the case here — which is exactly how `invalidEscape` got
    /// added when the tokenizer revealed the original twelve had no message for `\x`.
    public enum Kind: String, Sendable, CaseIterable {
        case missingComma
        case trailingComma
        case unterminatedString
        case controlCharacterInString
        case invalidUnicodeEscape
        case loneSurrogate
        /// An unknown escape such as `\\x`. Distinct from `invalidUnicodeEscape`, which is
        /// specifically a malformed `\\u` — the fixes differ.
        case invalidEscape
        case missingClosingBrace
        case missingClosingBracket
        case missingColon
        case unquotedKey
        case singleQuotedString
        case invalidNumber
        case trailingContent
    }

    /// Values the copy interpolates. Each is optional because no single message needs them all;
    /// the copy table asserts what it requires.
    public struct Context: Sendable, Equatable {
        /// 1-based line where the *next* token sits — `missingComma`'s `{nextLine}`.
        public var nextLine: Int?
        /// 1-based line of the unmatched opening delimiter or quote — `{openLine}`.
        public var openLine: Int?
        /// 1-based line where the document's top-level value ended — `{endLine}`.
        public var endLine: Int?
        /// The literal closer, `}` or `]` — `{closer}`.
        public var closer: String?
        /// A *name* for an unprintable character — "tab", "newline" — never the character itself.
        public var characterName: String?
        /// The escape to write instead — `\t`, `\n`.
        public var escape: String?
        /// The offending text, truncated for display — `{found}`.
        public var found: String?
        /// Which `invalidNumber` sub-case applies.
        public var numberProblem: NumberProblem?

        public init(
            nextLine: Int? = nil,
            openLine: Int? = nil,
            endLine: Int? = nil,
            closer: String? = nil,
            characterName: String? = nil,
            escape: String? = nil,
            found: String? = nil,
            numberProblem: NumberProblem? = nil
        ) {
            self.nextLine = nextLine
            self.openLine = openLine
            self.endLine = endLine
            self.closer = closer
            self.characterName = characterName
            self.escape = escape
            self.found = found
            self.numberProblem = numberProblem
        }
    }

    /// `invalidNumber` is one kind with four sub-messages, because the fix differs each time and
    /// a generic "invalid number" is exactly the vagueness `error-copy.md` exists to prevent.
    public enum NumberProblem: String, Sendable, CaseIterable {
        case leadingZero
        case trailingDecimalPoint
        case leadingDecimalPoint
        case missingDigits
    }

    /// Which of the twelve this is.
    public var kind: Kind
    /// **The cause** — the span the fix applies to. What gets underlined and scrolled to.
    public var span: SourceSpan
    /// Where the parser noticed, when that differs from the cause. Nil when they coincide.
    public var detectedAt: SourceSpan?
    /// Values the copy interpolates.
    public var context: Context
    /// The token actually found. Diagnostic data for tests, not for display.
    public var found: Token.Kind?
    /// Tokens that would have been legal here. Diagnostic data for tests, not for display —
    /// an expected-set is the parser's state, not the user's problem.
    public var expected: [Token.Kind]

    public init(
        kind: Kind,
        span: SourceSpan,
        detectedAt: SourceSpan? = nil,
        context: Context = Context(),
        found: Token.Kind? = nil,
        expected: [Token.Kind] = []
    ) {
        self.kind = kind
        self.span = span
        self.detectedAt = detectedAt
        self.context = context
        self.found = found
        self.expected = expected
    }

    /// `true` when the parser noticed the problem somewhere other than its cause — the case the
    /// copy has to explain, and the case competitors get wrong.
    public var wasDetectedElsewhere: Bool {
        guard let detectedAt else { return false }
        return detectedAt.start != span.start
    }

    /// Heading and body, resolved from `ParseErrorCopy`. Verbatim from `Design/error-copy.md`.
    public var copy: (title: String, body: String) {
        ParseErrorCopy.text(for: self)
    }
}
