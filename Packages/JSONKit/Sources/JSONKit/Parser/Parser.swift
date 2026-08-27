/// Error-recovering JSON parser (ADR-02).
///
/// Never throws on the first error: on a syntax error it records a `ParseError`, skips to the
/// next plausible sync point (`,` `}` `]` at the current depth) and continues, so the returned
/// tree is as complete as the input allows. Runs off the main actor with cooperative
/// cancellation (ADR-09).
///
/// **Attribution is the hard part, not parsing.** A JSON grammar is a day's work; the reason
/// this parser is hand-written is that every error has to point at its *cause* rather than at
/// the token where the parser noticed — Phase 0's one surviving differentiator. So
/// `missingComma` reports a zero-width span at the end of the completed value, carrying the
/// next property's line for the copy to name; `missingClosingBrace` reports the unmatched `{`,
/// not EOF. Every `ParseError` this file builds sets `span` to where the fix goes, and sets
/// `detectedAt` only when the two genuinely differ.
///
/// **Containers are walked with an explicit stack, not by recursion.** This is a departure from
/// the "recursive descent" wording in ADR-01/02 and it is forced by measurement, not taste. A
/// recursive version of this file was written first and then measured on a Swift concurrency
/// thread — which is where the app parses, and which gets a 512 KB stack rather than the main
/// thread's 8 MB. In a **debug** build it died at **96 levels of nesting for objects** (~5 KB of
/// frame per level, since each level costs a container frame plus a member frame). 96 is close
/// enough to real machine-generated payloads that the crash was reachable, and a crash on user
/// input is exactly what ADR-02 forbids. With the stack on the heap the depth limit below is a
/// policy choice that can actually be enforced, instead of a number the process never reaches.
public struct Parser: Sendable {

    /// Maximum container nesting. RFC 8259 §9 explicitly permits an implementation limit.
    /// Exceeding it is reported once as `nestingTooDeep` and never silently truncated.
    ///
    /// The parser itself no longer needs a limit (its stack is on the heap), but the *tree* is
    /// still walked recursively — `JSONNode.depth`, `innermostNode(at:)`, `JSONValue`'s
    /// synthesized `==`, and the formatter and diff to come. Those frames are small; 512 is
    /// verified safe for them in a debug build on a concurrency thread, and it accepts
    /// JSONTestSuite's `i_structure_500_nested_arrays.json`.
    public static let maxDepth = 512

    public init() {}

    /// Parse `source` into a partial tree plus the list of recovered errors.
    public func parse(_ source: String) -> ParseResult {
        parse(Tokenizer().tokenize(source))
    }

    /// Parse an already-tokenized document. The editor tokenizes once per edit to drive syntax
    /// highlighting, so it should not pay for a second scan to get the tree.
    public func parse(_ lexed: Tokenizer.Result) -> ParseResult {
        var state = ParserState(
            tokens: lexed.tokens, lineIndex: lexed.lineIndex, errors: lexed.errors
        )
        let tree = state.parseDocument()
        return ParseResult(
            tree: tree,
            errors: state.errorsInDocumentOrder(),
            lineIndex: lexed.lineIndex,
            wasCancelled: state.wasCancelled
        )
    }
}

// MARK: - ParserState

private struct ParserState {

    /// One open container. What recursion would have kept in a stack frame, kept on the heap.
    struct Frame {
        /// Where the frame is in the `entry → value → separator → entry` cycle. Splitting the
        /// member into two states is what lets a nested container suspend and resume: the
        /// parent sits in `.value` while the child is on top of the stack.
        enum State { case entry, value, separator }

        let isObject: Bool
        let open: SourceSpan
        var state: State = .entry
        var members: [JSONMember] = []
        var elements: [JSONNode] = []
        /// An object that has read `key :` and is waiting for the value.
        var pendingKey: (text: String, span: SourceSpan)?
    }

    let tokens: [Token]
    let lineIndex: LineIndex
    var errors: [ParseError]

    var index = 0
    private var stack: [Frame] = []
    /// `nestingTooDeep` is one fact about the document, not one per level.
    private var reportedNestingLimit = false
    private(set) var wasCancelled = false
    private var tokensSinceCancellationCheck = 0

    init(tokens: [Token], lineIndex: LineIndex, errors: [ParseError]) {
        // The tokenizer always terminates its output with `.endOfInput`, so `current` is total.
        self.tokens = tokens.isEmpty ? [Token(kind: .endOfInput, span: .empty(at: 0))] : tokens
        self.lineIndex = lineIndex
        self.errors = errors
    }

    // MARK: Cursor

    var current: Token { tokens[index] }
    var isAtEnd: Bool { current.kind == .endOfInput }

    mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    /// End of the previous token — the insertion point for a missing comma, colon or value.
    var previousEnd: Int {
        index > 0 ? tokens[index - 1].span.end : 0
    }

    func line(at offset: Int) -> Int { lineIndex.position(at: offset).line }

    /// The token's source text. Keywords and the structural characters carry no payload, so
    /// they are spelled out — an error reading "Replace  with a quoted key." names nothing.
    func sourceText(_ token: Token) -> String {
        switch token.kind {
        case .literalTrue: "true"
        case .literalFalse: "false"
        case .literalNull: "null"
        case .beginObject: "{"
        case .endObject: "}"
        case .beginArray: "["
        case .endArray: "]"
        case .colon: ":"
        case .comma: ","
        case .endOfInput: "the end of the document"
        default: token.stringValue ?? token.numberText ?? ""
        }
    }

    /// Checked every few thousand tokens rather than every token: the check is cheap but not
    /// free, and 4096 tokens is far inside the 200 ms perceived-latency budget (ADR-09).
    mutating func checkCancellation() {
        tokensSinceCancellationCheck += 1
        guard tokensSinceCancellationCheck >= 4096 else { return }
        tokensSinceCancellationCheck = 0
        if Task.isCancelled { wasCancelled = true }
    }

    /// Cause order, not discovery order. `missingClosingBrace` is found at EOF but caused at the
    /// opening brace, so sorting by cause is what puts the gutter markers and the status bar's
    /// "first error on line N" in the order a reader expects. Ties keep discovery order.
    func errorsInDocumentOrder() -> [ParseError] {
        errors.enumerated().sorted { a, b in
            let l = a.element.span, r = b.element.span
            if l.start != r.start { return l.start < r.start }
            if l.end != r.end { return l.end < r.end }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Document

    mutating func parseDocument() -> JSONNode? {
        var root: JSONNode?
        var reportedJunk = false
        // A document that opens with junk still has a value in it. Skip forward rather than
        // returning nil and blanking the tree — `# {"a":1}` should show the object.
        while root == nil && !isAtEnd && !wasCancelled {
            let before = index
            root = parseValue()
            if root == nil && index == before {
                // `parseScalar` stays silent on a comma or closer because inside a container
                // the container knows what it means. At the top level there is no container,
                // so the junk is ours to name — once, not once per token. Without this a
                // document of nothing but commas returns no tree *and* no error, and the
                // status bar calls a non-empty file "Empty document".
                if !reportedJunk {
                    reportedJunk = true
                    reportInvalidLiteral(current, expectation: .value)
                }
                advance()
            }
        }
        if let root { reportTrailingContent(after: root) }
        return root
    }

    /// An empty or whitespace-only document is **not** an error — it is the state of every new
    /// window. `parseDocument` returns nil with no errors and the status bar says
    /// "Empty document".
    private mutating func reportTrailingContent(after root: JSONNode) {
        guard !isAtEnd, !wasCancelled else { return }
        // Report once. Pasting a second payload below the first is one mistake, and the fix
        // ("wrap both values in an array") applies to all of it.
        let lastRealToken = tokens.count >= 2 ? tokens[tokens.count - 2] : current
        errors.append(ParseError(
            kind: .trailingContent,
            span: SourceSpan(
                start: current.span.start,
                end: max(current.span.end, lastRealToken.span.end)
            ),
            context: .init(endLine: line(at: root.span.end)),
            found: current.kind,
            expected: [.endOfInput]
        ))
    }

    // MARK: Values

    mutating func parseValue() -> JSONNode? {
        switch current.kind {
        case .beginObject, .beginArray:
            return parseContainer()
        default:
            return parseScalar()
        }
    }

    /// Every value that cannot contain another. Containers go through `parseContainer`, so this
    /// never recurses.
    private mutating func parseScalar() -> JSONNode? {
        let token = current
        switch token.kind {
        case .string:
            advance()
            return JSONNode(value: .string(token.stringValue ?? ""), span: token.span)
        case .number:
            advance()
            return JSONNode(value: .number(token.numberText ?? ""), span: token.span)
        case .literalTrue:
            advance()
            return JSONNode(value: .bool(true), span: token.span)
        case .literalFalse:
            advance()
            return JSONNode(value: .bool(false), span: token.span)
        case .literalNull:
            advance()
            return JSONNode(value: .null, span: token.span)
        case .identifier, .invalid:
            // `True`, `NaN`, `None`, a stray `#`. Reported and then **omitted** from the tree:
            // the parser will not guess that `True` meant `true`, because `"True"` is equally
            // likely and inventing a value would put a lie in the inspector. Contrast the key
            // path, where an unquoted name is unambiguous — the fix is quotes, the text stands.
            reportInvalidLiteral(token, expectation: .value)
            advance()
            return nil
        default:
            // A closer, comma, colon or EOF. There is no value here, but only the caller knows
            // whether that means a missing value, a trailing comma, or a container ending.
            return nil
        }
    }

    // MARK: Containers

    /// Walks a container and everything inside it. `current` is the opening delimiter.
    private mutating func parseContainer() -> JSONNode? {
        stack.removeAll(keepingCapacity: true)
        push()

        while !stack.isEmpty {
            checkCancellation()
            if wasCancelled { break }

            let before = (index, stack.count, stack[stack.count - 1].state)

            switch stack[stack.count - 1].state {
            case .entry:
                if let finished = stepAtEntry() { return finished }
            case .value:
                if let finished = stepAtValue() { return finished }
            case .separator:
                consumeSeparator(isObject: stack[stack.count - 1].isObject)
                stack[stack.count - 1].state = .entry
            }

            // The loop can never stall: an iteration that consumed no token, changed no depth
            // and changed no state forces progress. Cheaper to guarantee here than to prove
            // across every recovery path.
            if !stack.isEmpty,
               index == before.0, stack.count == before.1,
               stack[stack.count - 1].state == before.2 {
                advance()
            }
        }
        return nil   // only reachable via cancellation
    }

    /// At a member or element boundary: close the container, or begin one entry.
    private mutating func stepAtEntry() -> JSONNode? {
        let top = stack.count - 1
        let isObject = stack[top].isObject
        let closer: Token.Kind = isObject ? .endObject : .endArray
        let foreignCloser: Token.Kind = isObject ? .endArray : .endObject

        if current.kind == closer {
            let end = current.span.end
            advance()
            return pop(closeEnd: end)
        }

        // EOF, or a closer belonging to something else — either way this container never
        // closes. The foreign closer is deliberately left unconsumed, so `{"a": [1}` reports
        // the `[` as unclosed and then lets the object close cleanly on the same `}`.
        if current.kind == .endOfInput || current.kind == foreignCloser {
            reportUnclosed(open: stack[top].open, isObject: isObject)
            return pop(closeEnd: nil)
        }

        if isObject {
            guard let key = readKeyAndColon() else { return nil }
            stack[stack.count - 1].pendingKey = key
        }
        stack[stack.count - 1].state = .value
        return nil
    }

    /// A value is due. A container here suspends this frame and pushes a new one.
    private mutating func stepAtValue() -> JSONNode? {
        let top = stack.count - 1
        let isObject = stack[top].isObject

        if current.kind == .beginObject || current.kind == .beginArray {
            guard stack.count < Parser.maxDepth else {
                attach(skipTooDeepContainer(), to: top)
                stack[top].state = .separator
                return nil
            }
            push()
            return nil
        }

        let before = index
        if let node = parseScalar() {
            attach(node, to: top)
        } else {
            // A value is *missing* only if nothing was consumed. When `parseScalar` consumed an
            // unusable token it already reported it, and adding "add a value" on top would name
            // a second mistake that isn't there — `[True]` is one error, not two.
            if index == before {
                reportMissingValue(container: isObject ? .object : .array)
            }
            stack[top].pendingKey = nil
        }
        stack[top].state = .separator
        return nil
    }

    /// Reads `"key" :`, reporting the two mistakes that show up in its place. Returns nil when
    /// there was nothing key-shaped at all, in which case the frame stays at `.entry`.
    private mutating func readKeyAndColon() -> (text: String, span: SourceSpan)? {
        let key: String
        let keySpan: SourceSpan

        switch current.kind {
        case .string:
            key = current.stringValue ?? ""
            keySpan = current.span
            advance()

        case .identifier, .number, .literalTrue, .literalFalse, .literalNull:
            // Name-shaped but unquoted. `{region: 1}` and `{1: 2}` both land here, and the fix
            // is unambiguous — add quotes, keep the text — so the key is accepted into the tree.
            let token = current
            errors.append(ParseError(
                kind: .unquotedKey,
                span: token.span,
                context: .init(found: ParseErrorCopy.truncate(sourceText(token))),
                found: token.kind,
                expected: [.string]
            ))
            key = sourceText(token)
            keySpan = token.span
            advance()

        case .colon:
            // `{: 1}` — no key at all. The fix goes before the colon and there is no text to
            // name, so the copy falls back to "this key".
            errors.append(ParseError(
                kind: .unquotedKey,
                span: .empty(at: current.span.start),
                detectedAt: current.span,
                found: current.kind,
                expected: [.string]
            ))
            key = ""
            keySpan = .empty(at: current.span.start)

        default:
            // A brace or bracket where a key belongs: nothing to quote, so #16 not #9.
            reportInvalidLiteral(current, expectation: .key)
            skipValueOrToken()
            return nil
        }

        if current.kind == .colon {
            advance()
        } else {
            errors.append(ParseError(
                kind: .missingColon,
                span: .empty(at: keySpan.end),
                detectedAt: current.span,
                found: current.kind,
                expected: [.colon]
            ))
        }
        return (text: key, span: keySpan)
    }

    /// The comma between entries, and the two mistakes that show up in its place.
    private mutating func consumeSeparator(isObject: Bool) {
        switch current.kind {
        case .comma:
            let comma = current.span
            advance()
            let closer: Token.Kind = isObject ? .endObject : .endArray
            if current.kind == closer {
                errors.append(ParseError(
                    kind: .trailingComma,
                    span: comma,                       // the cause: this is what gets deleted
                    detectedAt: current.span,
                    context: .init(closer: isObject ? "}" : "]"),
                    found: current.kind
                ))
            }

        case .endObject, .endArray, .endOfInput:
            break                                      // `stepAtEntry` handles these

        default:
            if isObject ? startsMember(current) : startsElement(current) {
                // **The canonical cause-vs-detection case.** The comma belongs at the end of
                // the value just parsed; the parser only found out at the next one. Competing
                // tools report the detection point alone, which is why "check one line before"
                // is the documented workaround for them and not for us.
                errors.append(ParseError(
                    kind: .missingComma,
                    span: .empty(at: previousEnd),
                    detectedAt: current.span,
                    context: .init(
                        nextLine: line(at: current.span.start),
                        container: isObject ? .object : .array
                    ),
                    found: current.kind,
                    expected: [.comma, isObject ? .endObject : .endArray]
                ))
            } else {
                // A colon or stray character at an entry boundary. Name it and move on.
                reportInvalidLiteral(current, expectation: isObject ? .key : .value)
                skipValueOrToken()
            }
        }
    }

    // MARK: Stack

    private mutating func push() {
        stack.append(Frame(isObject: current.kind == .beginObject, open: current.span))
        advance()
    }

    /// Completes the top frame. Returns the node when the stack empties — that is the container
    /// `parseContainer` was asked for; otherwise the node is attached to its parent.
    private mutating func pop(closeEnd: Int?) -> JSONNode? {
        let frame = stack.removeLast()
        let end = closeEnd ?? max(previousEnd, frame.open.end)
        let node = JSONNode(
            value: frame.isObject ? .object(frame.members) : .array(frame.elements),
            span: SourceSpan(start: frame.open.start, end: end)
        )
        guard !stack.isEmpty else { return node }
        attach(node, to: stack.count - 1)
        stack[stack.count - 1].state = .separator
        return nil
    }

    private mutating func attach(_ node: JSONNode, to frameIndex: Int) {
        if stack[frameIndex].isObject {
            if let key = stack[frameIndex].pendingKey {
                stack[frameIndex].members.append(
                    JSONMember(key: key.text, keySpan: key.span, node: node)
                )
                stack[frameIndex].pendingKey = nil
            }
        } else {
            stack[frameIndex].elements.append(node)
        }
    }

    /// Past the depth limit: report once, consume the whole container, and stand an empty one in
    /// its place so the span stays honest about what was there.
    private mutating func skipTooDeepContainer() -> JSONNode {
        let isObject = current.kind == .beginObject
        let open = current.span
        if !reportedNestingLimit {
            reportedNestingLimit = true
            errors.append(ParseError(
                kind: .nestingTooDeep,
                span: open,
                context: .init(openLine: line(at: open.start), limit: Parser.maxDepth)
            ))
        }
        advance()
        let end = skipBalanced()
        return JSONNode(
            value: isObject ? .object([]) : .array([]),
            span: SourceSpan(start: open.start, end: end)
        )
    }

    // MARK: Errors

    private mutating func reportInvalidLiteral(
        _ token: Token, expectation: ParseError.Expectation
    ) {
        errors.append(ParseError(
            kind: .invalidLiteral,
            span: token.span,
            context: .init(
                found: ParseErrorCopy.truncate(sourceText(token)),
                expectation: expectation
            ),
            found: token.kind
        ))
    }

    private mutating func reportMissingValue(container: ParseError.ContainerKind) {
        errors.append(ParseError(
            kind: .missingValue,
            span: .empty(at: previousEnd),
            detectedAt: current.span,
            context: .init(container: container),
            found: current.kind
        ))
    }

    private mutating func reportUnclosed(open: SourceSpan, isObject: Bool) {
        errors.append(ParseError(
            kind: isObject ? .missingClosingBrace : .missingClosingBracket,
            span: open,                                // the cause: the unmatched opener
            detectedAt: current.span,                  // EOF, which alone tells the reader nothing
            context: .init(openLine: line(at: open.start), closer: isObject ? "}" : "]"),
            found: current.kind,
            expected: [isObject ? .endObject : .endArray]
        ))
    }

    // MARK: Recovery helpers

    private func startsMember(_ token: Token) -> Bool {
        switch token.kind {
        case .string, .identifier, .number, .literalTrue, .literalFalse, .literalNull: true
        default: false
        }
    }

    private func startsElement(_ token: Token) -> Bool {
        token.canBeginValue || token.kind == .identifier
    }

    /// Skips one token, or a whole balanced container when the token opens one — so junk in the
    /// middle of an object cannot make the parser mistake the nested closers for its own.
    private mutating func skipValueOrToken() {
        switch current.kind {
        case .beginObject, .beginArray:
            advance()
            _ = skipBalanced()
        case .endOfInput:
            break
        default:
            advance()
        }
    }

    /// Consumes through the closer matching the container whose opener was just consumed, and
    /// returns that closer's end offset.
    private mutating func skipBalanced() -> Int {
        var open = 1
        var end = previousEnd

        while true {
            checkCancellation()
            switch current.kind {
            case .endOfInput:
                return end
            case .beginObject, .beginArray:
                open += 1
            case .endObject, .endArray:
                open -= 1
                end = current.span.end
                advance()
                if open == 0 { return end }
                continue
            default:
                break
            }
            end = current.span.end
            advance()
        }
    }
}
