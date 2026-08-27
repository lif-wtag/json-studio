/// Pretty-prints or minifies a JSON tree.
///
/// **Scalars are re-emitted from their source spans, not re-encoded.** `JSONValue.string` holds
/// the *decoded* value (`café`), so re-encoding it would turn `é` into a literal `é` and
/// `\/` into `/`. Both are semantically identical and neither is what the developer typed. The
/// formatter has the source and every node has a span, so an unmodified value is copied out
/// byte-for-byte and the round-trip is exact rather than merely equivalent. Numbers need no
/// lookup at all — `.number` already stores its source text, which is why `9007199254740993`
/// and `1.0` survive.
///
/// **The walk is iterative, for the reason in ADR-01 Amendment 1.** A recursive version was
/// written first and measured on a concurrency thread in a debug build: it overflowed the 512 KB
/// stack between **192 and 256** levels of nested objects — below `Parser.maxDepth`, so a
/// document the parser accepts would have crashed the formatter. Only the width test recurses,
/// and it is bounded by `printWidth`: each nesting level costs at least four characters of
/// budget, so it cannot exceed ~`printWidth / 4` levels before it bails.
///
/// **Formatting assumes a valid parse.** On a recovered tree a string's span can be missing its
/// closing quote, and copying that out verbatim would emit invalid JSON. The literal writer
/// checks the slice is a well-formed string literal and falls back to encoding the decoded value
/// if it isn't, so the formatter is total — but the Format command itself should stay disabled
/// while the document is invalid, which is what every other tool does and what the toolbar
/// design assumes.
public struct Formatter: Sendable {
    public var options: FormatOptions

    public init(options: FormatOptions = .pretty) {
        self.options = options
    }

    /// Formats `node` using `source` to re-emit unmodified scalars.
    public func format(_ node: JSONNode, source: String) -> String {
        var writer = Writer(units: Array(source.utf16), options: options)
        writer.write(node)
        if options.trailingNewline { writer.out.append("\n") }
        return writer.out
    }

    /// Formats a parse result. Returns nil when there is no tree, so a caller can't accidentally
    /// format an empty document into `""` and save it over their file.
    public func format(_ result: ParseResult, source: String) -> String? {
        result.tree.map { format($0, source: source) }
    }
}

// MARK: - Writer

private struct Writer {
    let units: [UInt16]
    let options: FormatOptions
    var out = ""

    /// One open container. What recursion would have kept in a stack frame, kept on the heap.
    private struct Frame {
        let node: JSONNode
        /// Indent level of the container's own closing delimiter.
        let level: Int
        let count: Int
        var index = 0
    }

    private var stack: [Frame] = []

    init(units: [UInt16], options: FormatOptions) {
        self.units = units
        self.options = options
        self.out.reserveCapacity(units.count + units.count / 4)
    }

    // MARK: The walk

    mutating func write(_ root: JSONNode) {
        guard root.value.isContainer else { out += scalar(root); return }
        guard root.value.childCount > 0 else { out += empty(root); return }
        if let inline = inlineIfItFits(root.value, column: 0, reserving: 0) {
            out += inline
            return
        }

        out += opener(root) + afterOpener
        stack.append(Frame(node: root, level: 0, count: root.value.childCount))

        while let top = stack.indices.last {
            if stack[top].index == stack[top].count {
                out += indent(stack[top].level) + closer(stack[top].node)
                stack.removeLast()
                closeChild()
                continue
            }
            emitOneChild(at: top)
        }
    }

    /// Emits the child at the top frame's cursor — or opens it and pushes, when it breaks.
    private mutating func emitOneChild(at top: Int) {
        let frame = stack[top]
        let level = frame.level + 1
        let isLast = frame.index == frame.count - 1

        out += indent(level)
        var column = options.compact ? 0 : options.indent.columns * level

        let child: JSONNode
        switch frame.node.value {
        case .object(let members):
            let member = members[frame.index]
            let keyText = key(member)
            out += keyText + keySeparator
            column += keyText.count + keySeparator.count
            child = member.node
        case .array(let elements):
            child = elements[frame.index]
        default:
            stack.removeLast()          // unreachable: only containers are pushed
            return
        }
        stack[top].index += 1

        // A comma still has to fit after this child, and one column is the difference between a
        // line that fits and one that is a character over.
        let reserving = isLast ? 0 : 1

        if child.value.isContainer && child.value.childCount > 0 {
            if let inline = inlineIfItFits(child.value, column: column, reserving: reserving) {
                out += inline
                out += isLast ? afterLastChild : betweenChildren
            } else {
                out += opener(child) + afterOpener
                stack.append(Frame(node: child, level: level, count: child.value.childCount))
            }
            return
        }

        out += child.value.isContainer ? empty(child) : scalar(child)
        out += isLast ? afterLastChild : betweenChildren
    }

    /// Separator after a container that has just closed, read from its parent's cursor.
    private mutating func closeChild() {
        guard let parent = stack.indices.last else { return }
        let done = stack[parent].index == stack[parent].count
        out += done ? afterLastChild : betweenChildren
    }

    // MARK: Punctuation

    private var afterOpener: String { options.compact ? "" : "\n" }
    private var betweenChildren: String { options.compact ? "," : ",\n" }
    private var afterLastChild: String { options.compact ? "" : "\n" }
    private var keySeparator: String { options.compact ? ":" : ": " }

    private func opener(_ node: JSONNode) -> String { node.kind == .object ? "{" : "[" }
    private func closer(_ node: JSONNode) -> String { node.kind == .object ? "}" : "]" }
    private func empty(_ node: JSONNode) -> String { node.kind == .object ? "{}" : "[]" }

    private func indent(_ level: Int) -> String {
        options.compact ? "" : String(repeating: options.indent.text, count: level)
    }

    // MARK: The width test

    /// The inline rendering of a container, or nil if it doesn't fit the remaining width.
    ///
    /// Building it bails as soon as the budget is blown, so a container that will obviously
    /// break costs at most `printWidth` characters of work rather than a full subtree render —
    /// which is also what bounds this function's own recursion.
    private func inlineIfItFits(_ value: JSONValue, column: Int, reserving: Int) -> String? {
        guard !options.compact, let printWidth = options.printWidth else { return nil }
        let budget = printWidth - column - reserving
        guard budget > 0 else { return nil }
        return measured(value, budget: budget)?.text
    }

    /// Objects carry inner spaces — `{ "a": 1 }` — and arrays don't — `["a", "b"]`. Read off the
    /// approved artboard, which is written in exactly this shape; it is the convention a
    /// developer hand-writing JSON already uses.
    ///
    /// Width is carried alongside the text rather than recomputed from it. `String.count` walks
    /// the string to find grapheme breaks, so asking for it once per child made the inline
    /// attempt quadratic in the child count — measured at 84 ms on a 1 MB payload against an
    /// 80 ms budget, versus 57 ms once the count is accumulated.
    private func measured(_ value: JSONValue, budget: Int) -> (text: String, width: Int)? {
        switch value {
        case .object(let members):
            if members.isEmpty { return ("{}", 2) }
            var text = "{ "
            var width = 2
            for (i, member) in members.enumerated() {
                if i > 0 { text += ", "; width += 2 }
                let keyText = key(member)
                text += keyText + ": "
                width += keyText.count + 2
                guard width <= budget,
                      let child = measuredChild(member.node, budget: budget - width)
                else { return nil }
                text += child.text
                width += child.width
                if width > budget { return nil }
            }
            text += " }"
            width += 2
            return width <= budget ? (text, width) : nil

        case .array(let elements):
            if elements.isEmpty { return ("[]", 2) }
            var text = "["
            var width = 1
            for (i, element) in elements.enumerated() {
                if i > 0 { text += ", "; width += 2 }
                guard width <= budget,
                      let child = measuredChild(element, budget: budget - width)
                else { return nil }
                text += child.text
                width += child.width
                if width > budget { return nil }
            }
            text += "]"
            width += 1
            return width <= budget ? (text, width) : nil

        default:
            return nil
        }
    }

    private func measuredChild(_ node: JSONNode, budget: Int) -> (text: String, width: Int)? {
        guard budget > 0 else { return nil }
        switch node.value {
        case .object, .array:
            return measured(node.value, budget: budget)
        default:
            let text = scalar(node)
            let width = text.count
            return width <= budget ? (text, width) : nil
        }
    }

    // MARK: Literals

    /// A key, re-emitted from its own span so its escapes survive too.
    private func key(_ member: JSONMember) -> String {
        stringLiteral(span: member.keySpan, decoded: member.key)
    }

    private func scalar(_ node: JSONNode) -> String {
        switch node.value {
        case .string(let decoded): stringLiteral(span: node.span, decoded: decoded)
        case .number(let text): text          // already the source text; nothing to look up
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        case .object, .array: ""              // containers never reach here
        }
    }

    /// The source slice when it is a well-formed string literal, otherwise a fresh encoding.
    /// The fallback is what makes a recovered tree — an unterminated string, say — format into
    /// valid JSON instead of propagating the break.
    private func stringLiteral(span: SourceSpan, decoded: String) -> String {
        guard span.length >= 2, span.end <= units.count,
              units[span.start] == 0x22, units[span.end - 1] == 0x22
        else {
            return Writer.encoded(decoded)
        }
        return String(decoding: units[span.start..<span.end], as: UTF16.self)
    }

    /// RFC 8259 §7: escape the quote, the backslash, and everything below U+0020. Nothing else —
    /// re-escaping non-ASCII would undo the point of storing decoded strings.
    static func encoded(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
