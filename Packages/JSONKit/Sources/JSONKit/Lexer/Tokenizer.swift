/// Hand-written tokenizer over UTF-16 code units. Produces `Token`s with exact spans, resolving
/// string escapes and `\u` surrogate pairs, and validating the RFC 8259 number grammar.
///
/// **It never throws and never stops early.** Like the parser above it, the tokenizer recovers:
/// a malformed string or number produces a token *and* an error, and scanning continues. A live
/// editor spends most of its time on invalid input, and a lexer that gave up at the first bad
/// escape would blank the tree on every keystroke inside a broken string.
///
/// Scanning works on `Array(source.utf16)` — a single up-front copy that buys O(1) indexed access
/// and makes span arithmetic exact rather than a `String.Index` dance. For a 10 MB document that
/// is ~20 MB of `UInt16`, which is the right trade for offsets that are correct by construction.
///
/// Phase 4 adds a streaming variant for inspect-mode payloads.
public struct Tokenizer: Sendable {

    public struct Result: Sendable {
        public var tokens: [Token]
        /// Lexical errors only — an unterminated string, a bad escape, a malformed number. The
        /// parser adds structural errors on top.
        public var errors: [ParseError]
        /// Built during the same pass, so callers need not scan the source again.
        public var lineIndex: LineIndex

        public init(tokens: [Token], errors: [ParseError], lineIndex: LineIndex) {
            self.tokens = tokens
            self.errors = errors
            self.lineIndex = lineIndex
        }
    }

    public init() {}

    public func tokenize(_ source: String) -> Result {
        var scanner = Scanner(source: source)
        scanner.run()
        return Result(tokens: scanner.tokens, errors: scanner.errors, lineIndex: scanner.lineIndex)
    }
}

// MARK: - Scanner

private struct Scanner {
    let units: [UInt16]
    let lineIndex: LineIndex

    var index = 0
    var tokens: [Token] = []
    var errors: [ParseError] = []

    init(source: String) {
        self.units = Array(source.utf16)
        self.lineIndex = LineIndex(source: source)
        self.tokens.reserveCapacity(units.count / 8 + 8)
    }

    // Named constants beat magic numbers in a scanner, where every branch is a code unit.
    private enum U {
        static let tab: UInt16 = 0x09, lf: UInt16 = 0x0A, cr: UInt16 = 0x0D, space: UInt16 = 0x20
        static let quote: UInt16 = 0x22, apostrophe: UInt16 = 0x27
        static let plus: UInt16 = 0x2B, comma: UInt16 = 0x2C, minus: UInt16 = 0x2D
        static let dot: UInt16 = 0x2E, slash: UInt16 = 0x2F
        static let zero: UInt16 = 0x30, nine: UInt16 = 0x39
        static let colon: UInt16 = 0x3A
        static let upperA: UInt16 = 0x41, upperE: UInt16 = 0x45, upperF: UInt16 = 0x46
        static let upperZ: UInt16 = 0x5A
        static let openBracket: UInt16 = 0x5B, backslash: UInt16 = 0x5C, closeBracket: UInt16 = 0x5D
        static let underscore: UInt16 = 0x5F
        static let lowerA: UInt16 = 0x61, lowerB: UInt16 = 0x62, lowerE: UInt16 = 0x65
        static let lowerF: UInt16 = 0x66, lowerN: UInt16 = 0x6E, lowerR: UInt16 = 0x72
        static let lowerT: UInt16 = 0x74, lowerU: UInt16 = 0x75, lowerZ: UInt16 = 0x7A
        static let openBrace: UInt16 = 0x7B, closeBrace: UInt16 = 0x7D
        static let replacement: UInt16 = 0xFFFD
    }

    private func peek(_ ahead: Int = 0) -> UInt16? {
        let i = index + ahead
        return i < units.count ? units[i] : nil
    }

    private func isDigit(_ u: UInt16) -> Bool { u >= U.zero && u <= U.nine }

    private func hexValue(_ u: UInt16) -> UInt16? {
        switch u {
        case U.zero...U.nine: u - U.zero
        case U.lowerA...U.lowerF: u - U.lowerA + 10
        case U.upperA...U.upperF: u - U.upperA + 10
        default: nil
        }
    }

    /// Letters, digits and `_` — the shape of a bare word we should report as one unit rather
    /// than as a stream of single-character garbage.
    private func isWordCharacter(_ u: UInt16) -> Bool {
        (u >= U.lowerA && u <= U.lowerZ) || (u >= U.upperA && u <= U.upperZ)
            || isDigit(u) || u == U.underscore
    }

    private func line(at offset: Int) -> Int { lineIndex.position(at: offset).line }

    private func text(_ span: SourceSpan) -> String {
        String(decoding: units[span.start..<min(span.end, units.count)], as: UTF16.self)
    }

    // MARK: Driver

    mutating func run() {
        while true {
            skipWhitespace()
            guard let u = peek() else { break }
            let start = index

            switch u {
            case U.openBrace:    advanceAndEmit(.beginObject)
            case U.closeBrace:   advanceAndEmit(.endObject)
            case U.openBracket:  advanceAndEmit(.beginArray)
            case U.closeBracket: advanceAndEmit(.endArray)
            case U.colon:        advanceAndEmit(.colon)
            case U.comma:        advanceAndEmit(.comma)
            case U.quote:        scanString(quoted: U.quote)
            case U.apostrophe:   scanSingleQuotedString()
            case U.minus:        scanNumber()
            // A leading `.` must enter the number scanner, not fall through to `invalid`, or
            // `.5` reports nothing at all instead of "add a digit before the decimal point".
            case U.dot:          scanNumber()
            case _ where isDigit(u): scanNumber()
            case _ where isWordCharacter(u): scanWord()
            default:
                // A character that cannot begin any token. Consume exactly one so the loop
                // always progresses — a lexer that can stall is worse than one that mislabels.
                index += 1
                let span = SourceSpan(start: start, end: index)
                emit(.invalid, span, .text(text(span)))
            }
        }
        tokens.append(Token(kind: .endOfInput, span: .empty(at: units.count)))
    }

    private mutating func skipWhitespace() {
        // RFC 8259 §2: space, tab, LF, CR. Nothing else is whitespace, U+00A0 included.
        while let u = peek(), u == U.space || u == U.tab || u == U.lf || u == U.cr {
            index += 1
        }
    }

    private mutating func advanceAndEmit(_ kind: Token.Kind) {
        let start = index
        index += 1
        emit(kind, SourceSpan(start: start, end: index), nil)
    }

    private mutating func emit(_ kind: Token.Kind, _ span: SourceSpan, _ payload: Token.Payload?) {
        tokens.append(Token(kind: kind, span: span, payload: payload))
    }

    // MARK: Strings

    /// Scans a string literal. `quoted` is the delimiter, so the single-quote recovery path can
    /// reuse every escape rule rather than duplicating them.
    private mutating func scanString(quoted delimiter: UInt16) {
        let openQuote = index
        index += 1                                   // past the opening delimiter
        var decoded: [UInt16] = []

        while let u = peek() {
            if u == delimiter {
                index += 1
                let span = SourceSpan(start: openQuote, end: index)
                emit(.string, span, .string(String(decoding: decoded, as: UTF16.self)))
                return
            }

            if u == U.lf || u == U.cr {
                // A newline ends the line, so the string is unterminated. Do NOT consume it:
                // the next line is almost certainly valid JSON and should tokenize normally.
                unterminated(openQuote: openQuote, reachedEndOfDocument: false, decoded: decoded)
                return
            }

            if u < 0x20 {
                let (name, escape) = ParseErrorCopy.characterName(forUTF16: u)
                errors.append(ParseError(
                    kind: .controlCharacterInString,
                    span: SourceSpan(start: index, end: index + 1),
                    context: .init(characterName: name, escape: escape)
                ))
                // Keep the character in the decoded value: the tree should show what is there.
                decoded.append(u)
                index += 1
                continue
            }

            if u == U.backslash {
                scanEscape(into: &decoded, openQuote: openQuote)
                continue
            }

            decoded.append(u)
            index += 1
        }

        unterminated(openQuote: openQuote, reachedEndOfDocument: true, decoded: decoded)
    }

    private mutating func unterminated(
        openQuote: Int, reachedEndOfDocument: Bool, decoded: [UInt16]
    ) {
        // Cause is the OPENING quote, never the newline or EOF where it was noticed — the
        // developer needs to see where the string began to know where it should end.
        errors.append(ParseError(
            kind: .unterminatedString,
            span: SourceSpan(start: openQuote, end: openQuote + 1),
            detectedAt: SourceSpan(start: index, end: index),
            context: .init(
                openLine: line(at: openQuote),
                endLine: reachedEndOfDocument ? line(at: units.count) : nil
            )
        ))
        // Still emit the token: the parser can use a partial string, and the tree stays populated.
        emit(.string, SourceSpan(start: openQuote, end: index),
             .string(String(decoding: decoded, as: UTF16.self)))
    }

    /// `'…'` — not legal JSON, but common enough in hand-edited and Python-sourced payloads to
    /// deserve its own diagnosis rather than a cascade of `invalid` tokens.
    private mutating func scanSingleQuotedString() {
        let openQuote = index
        errors.append(ParseError(
            kind: .singleQuotedString,
            span: SourceSpan(start: openQuote, end: openQuote + 1),
            context: .init(openLine: line(at: openQuote))
        ))
        scanString(quoted: U.apostrophe)
    }

    /// Consumes one escape sequence, appending its value. `index` sits on the backslash.
    private mutating func scanEscape(into decoded: inout [UInt16], openQuote: Int) {
        let backslash = index
        index += 1

        guard let e = peek() else {
            // Trailing backslash at EOF; the unterminated-string error follows from the caller.
            decoded.append(U.backslash)
            return
        }

        switch e {
        case U.quote, U.backslash, U.slash:
            decoded.append(e); index += 1
        case U.lowerB: decoded.append(0x08); index += 1
        case U.lowerF: decoded.append(0x0C); index += 1
        case U.lowerN: decoded.append(U.lf);  index += 1
        case U.lowerR: decoded.append(U.cr);  index += 1
        case U.lowerT: decoded.append(U.tab); index += 1
        case U.apostrophe where openQuote < units.count && units[openQuote] == U.apostrophe:
            // Inside a single-quoted string, \' is what the author meant. Already reported.
            decoded.append(e); index += 1
        case U.lowerU:
            index += 1                                    // past 'u'
            scanUnicodeEscape(into: &decoded, backslash: backslash)
        default:
            errors.append(ParseError(
                kind: .invalidEscape,
                span: SourceSpan(start: backslash, end: index + 1),
                context: .init(found: String(decoding: [e], as: UTF16.self))
            ))
            // Drop the backslash, keep the character: `\x` almost always meant a literal x.
            decoded.append(e)
            index += 1
        }
    }

    private mutating func scanUnicodeEscape(into decoded: inout [UInt16], backslash: Int) {
        guard let first = readFourHexDigits() else {
            errors.append(ParseError(
                kind: .invalidUnicodeEscape,
                span: SourceSpan(start: backslash, end: min(index, units.count)),
                context: .init()
            ))
            decoded.append(U.replacement)
            return
        }

        // A high surrogate is only meaningful when a low surrogate follows it as its own escape.
        if (0xD800...0xDBFF).contains(first) {
            let afterHigh = index
            if peek() == U.backslash, peek(1) == U.lowerU {
                index += 2
                if let second = readFourHexDigits(), (0xDC00...0xDFFF).contains(second) {
                    decoded.append(first)
                    decoded.append(second)
                    return
                }
                index = afterHigh                          // not a valid pair; leave it alone
            }
            errors.append(ParseError(
                kind: .loneSurrogate,
                span: SourceSpan(start: backslash, end: afterHigh),
                context: .init()
            ))
            decoded.append(U.replacement)
            return
        }

        if (0xDC00...0xDFFF).contains(first) {
            errors.append(ParseError(
                kind: .loneSurrogate,
                span: SourceSpan(start: backslash, end: index),
                context: .init()
            ))
            decoded.append(U.replacement)
            return
        }

        decoded.append(first)
    }

    /// Reads exactly four hex digits, or nothing at all — leaving `index` where the digits should
    /// have been so the error span covers the whole malformed escape.
    private mutating func readFourHexDigits() -> UInt16? {
        var value: UInt16 = 0
        var consumed = 0
        while consumed < 4, let u = peek(), let digit = hexValue(u) {
            value = value << 4 | digit
            index += 1
            consumed += 1
        }
        return consumed == 4 ? value : nil
    }

    // MARK: Numbers

    /// RFC 8259 §6:  `-? ( 0 | [1-9][0-9]* ) ( '.' [0-9]+ )? ( [eE] [+-]? [0-9]+ )?`
    ///
    /// Every violation still produces a `.number` token carrying its source text, so the tree
    /// keeps a value the inspector can show while the developer fixes it.
    private mutating func scanNumber() {
        let start = index
        var problem: ParseError.NumberProblem?

        if peek() == U.minus { index += 1 }

        // Integer part.
        if let u = peek(), u == U.zero {
            index += 1
            if let next = peek(), isDigit(next) {
                problem = problem ?? .leadingZero
                while let d = peek(), isDigit(d) { index += 1 }
            }
        } else if let u = peek(), isDigit(u) {
            while let d = peek(), isDigit(d) { index += 1 }
        } else if peek() == U.dot {
            problem = problem ?? .leadingDecimalPoint
        } else {
            problem = problem ?? .missingDigits       // a bare `-`
        }

        // Fraction.
        if peek() == U.dot {
            index += 1
            if let d = peek(), isDigit(d) {
                while let d2 = peek(), isDigit(d2) { index += 1 }
            } else {
                problem = problem ?? .trailingDecimalPoint
            }
        }

        // Exponent.
        if let u = peek(), u == U.lowerE || u == U.upperE {
            index += 1
            if let sign = peek(), sign == U.plus || sign == U.minus { index += 1 }
            if let d = peek(), isDigit(d) {
                while let d2 = peek(), isDigit(d2) { index += 1 }
            } else {
                problem = problem ?? .missingDigits
            }
        }

        // Trailing word characters (`1abc`, `0x1F`) belong to the malformed number, not to a
        // separate token — reporting them together is what makes the message actionable.
        if let u = peek(), isWordCharacter(u) || u == U.dot {
            while let u2 = peek(), isWordCharacter(u2) || u2 == U.dot { index += 1 }
            problem = problem ?? .missingDigits
        }

        let span = SourceSpan(start: start, end: index)
        let source = text(span)

        if let problem {
            errors.append(ParseError(
                kind: .invalidNumber,
                span: span,
                context: .init(found: ParseErrorCopy.truncate(source), numberProblem: problem)
            ))
        }
        emit(.number, span, .number(source))
    }

    // MARK: Bare words

    private mutating func scanWord() {
        let start = index
        while let u = peek(), isWordCharacter(u) { index += 1 }
        let span = SourceSpan(start: start, end: index)
        let word = text(span)

        switch word {
        case "true":  emit(.literalTrue, span, nil)
        case "false": emit(.literalFalse, span, nil)
        case "null":  emit(.literalNull, span, nil)
        default:
            // No error here: only the parser knows whether this is an unquoted key, a misspelled
            // literal, or junk. Emitting a classified token and staying quiet is the honest split.
            emit(.identifier, span, .text(word))
        }
    }

}
