/// The user-facing error strings, **transcribed verbatim from `Design/error-copy.md`**.
///
/// This file and that document must change together. Nothing here is improvised, and no other
/// code in the project may author error prose — the project contract makes that a rule because
/// the error experience is the product, not a cosmetic layer.
///
/// The three rules the copy obeys, restated so a future editor of this file keeps them:
///   1. **Point at the cause.** Never the detection point alone.
///   2. **Say what to do.** Every string contains an imperative — add, remove, close, escape.
///   3. **No apology, no vagueness, no exclamation.** Sentence case, active voice.
public enum ParseErrorCopy {

    /// Heading and body for an error, with `context` interpolated.
    public static func text(for error: ParseError) -> (title: String, body: String) {
        let c = error.context

        switch error.kind {
        case .missingComma:
            // The array wording is not cosmetic: "property" is wrong for an element, and this is
            // the message developers read most often.
            if c.container == .array {
                return (
                    "Add a comma after this element.",
                    "The next element starts on line \(c.nextLine.map(String.init) ?? "?") without one."
                )
            }
            return (
                "Add a comma after this value.",
                "The next property starts on line \(c.nextLine.map(String.init) ?? "?") without one."
            )

        case .trailingComma:
            return (
                "Remove this comma.",
                "JSON doesn't allow a comma before \(c.closer ?? "the closing delimiter")."
            )

        case .unterminatedString:
            // `endLine` present means the string swallowed the rest of the document, which is a
            // different fix from a string that merely ran past its own line.
            if c.endLine != nil, let openLine = c.openLine {
                return (
                    "This string never closes.",
                    "It runs to the end of the document. The opening quote is on line \(openLine)."
                )
            }
            return (
                "This string never closes.",
                "Add a closing quote before the end of line \(c.openLine.map(String.init) ?? "?")."
            )

        case .controlCharacterInString:
            let name = c.characterName ?? "character"
            return (
                "Escape this \(name).",
                "A literal \(name) isn't allowed inside a string — write \(c.escape ?? "an escape") instead."
            )

        case .invalidUnicodeEscape:
            return (
                "Complete this \\u escape.",
                "It needs exactly four hex digits, like \\u00e9."
            )

        case .loneSurrogate:
            return (
                "This \\u escape is an unpaired surrogate.",
                "Follow it with a \\uDC00–\\uDFFF escape, or write the character directly."
            )

        case .invalidEscape:
            return (
                "Remove this backslash, or finish the escape.",
                "\\\(c.found ?? "?") isn't a JSON escape. The valid ones are \\\" \\\\ \\/ \\b \\f \\n \\r \\t and \\uXXXX."
            )

        case .missingClosingBrace:
            return (
                "This object never closes.",
                "Add } to match the { on line \(c.openLine.map(String.init) ?? "?")."
            )

        case .missingClosingBracket:
            return (
                "This array never closes.",
                "Add ] to match the [ on line \(c.openLine.map(String.init) ?? "?")."
            )

        case .missingColon:
            return (
                "Add a colon after this key.",
                "Object entries are written \"key\": value."
            )

        case .unquotedKey:
            return (
                "Put double quotes around \(c.found ?? "this key").",
                "JSON keys are always quoted strings."
            )

        case .singleQuotedString:
            return (
                "Use double quotes here.",
                "JSON strings can't be single-quoted."
            )

        case .invalidNumber:
            switch c.numberProblem {
            case .leadingZero:
                return (
                    "Remove the leading zero.",
                    "JSON numbers can't start with 0 unless the value is 0 itself."
                )
            case .trailingDecimalPoint:
                return (
                    "Add a digit after the decimal point,",
                    "or remove the point."
                )
            case .leadingDecimalPoint:
                return (
                    "Add a digit before the decimal point.",
                    "Write 0.5, not .5"
                )
            case .missingDigits, .none:
                return (
                    "Finish this number.",
                    "\(c.found ?? "It") is missing its digits."
                )
            }

        case .trailingContent:
            return (
                "The document already ended on line \(c.endLine.map(String.init) ?? "?").",
                "Remove this, or wrap both values in an array."
            )

        case .missingValue:
            if c.container == .array {
                return (
                    "Add a value, or remove the comma.",
                    "An array element can't be empty."
                )
            }
            return (
                "Add a value after the colon.",
                "An object entry needs one — write \"key\": value."
            )

        case .invalidLiteral:
            let found = c.found ?? "this"
            if c.expectation == .key {
                return (
                    "Replace \(found) with a quoted key.",
                    "Object entries are written \"key\": value."
                )
            }
            return (
                "Replace \(found) with a JSON value.",
                "JSON has strings, numbers, true, false, null, objects and arrays — nothing else."
            )

        case .nestingTooDeep:
            // The one message with no imperative — see `error-copy.md` #17. There is no action
            // the developer can take, and inventing one would be advice rather than an error.
            return (
                "This structure nests deeper than \(c.limit.map(String.init) ?? "512") levels.",
                "Everything above that depth is parsed; below it, this branch is shown empty."
            )
        }
    }

    /// The empty-document state from `Design/error-copy.md` §Status bar. Not an error — it is
    /// the state of every new window, which is why `ParseResult` distinguishes it.
    public static let emptyDocument = "Empty document"

    /// Status-bar summary. `Design/error-copy.md` specifies the exact shapes.
    ///
    /// The valid state takes optional detail — `Valid JSON · 119 properties · 3.7 KB · UTF-8` —
    /// because that whole line is specified there too, and composing it at the call site would be
    /// improvising copy in code. Callers with nothing to add get `Valid JSON` alone.
    public static func statusSummary(
        errorCount: Int,
        firstLine: Int? = nil,
        firstColumn: Int? = nil,
        properties: Int? = nil,
        size: String? = nil,
        encoding: String? = nil
    ) -> String {
        switch errorCount {
        case 0:
            var parts = ["Valid JSON"]
            if let properties { parts.append("\(properties) properties") }
            if let size { parts.append(size) }
            if let encoding { parts.append(encoding) }
            return parts.joined(separator: " · ")
        case 1:
            guard let line = firstLine, let column = firstColumn else { return "1 error" }
            return "1 error · line \(line), column \(column)"
        default:
            guard let line = firstLine else { return "\(errorCount) errors" }
            return "\(errorCount) errors · first on line \(line)"
        }
    }

    /// The `{size}` placeholder in `Design/error-copy.md` §Status bar: `512 B`, `3.7 KB`, `3.0 MB`.
    ///
    /// It lives here rather than in each surface because the CLI's status line and the app's
    /// status bar render the *same specified string*, and two implementations of it would drift —
    /// the fixture is 3,771 bytes, which is `3.7 KB` binary and `3.8 KB` decimal, so the two would
    /// disagree on the very document every mockup and test uses.
    ///
    /// Binary units under decimal labels is what Finder shipped for years and what the artboard's
    /// `3.7 KB` was measured as. No Foundation here (ADR-05), so the one decimal is arithmetic.
    public static func byteSize(_ bytes: Int) -> String {
        guard bytes >= 1024 else { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(units[index])"
    }

    /// `{found}` is capped so an error message can't be swamped by a 4 KB run of garbage.
    /// `Design/error-copy.md` fixes the limit at 24 characters.
    static func truncate(_ s: String, limit: Int = 24) -> String {
        s.count <= limit ? s : String(s.prefix(limit)) + "…"
    }

    /// Human names for the control characters `controlCharacterInString` reports. Never render the
    /// character itself — an invisible glyph in an error message explains nothing.
    public static func characterName(forUTF16 unit: UInt16) -> (name: String, escape: String) {
        switch unit {
        case 0x0009: return ("tab", "\\t")
        case 0x000A: return ("newline", "\\n")
        case 0x000D: return ("carriage return", "\\r")
        case 0x0008: return ("backspace", "\\b")
        case 0x000C: return ("form feed", "\\f")
        default:
            // No Foundation, so no String(format:) — JSONKit stays portable (ADR-05).
            let hex = String(unit, radix: 16)
            let padded = String(repeating: "0", count: max(0, 4 - hex.count)) + hex
            return ("control character", "\\u" + padded)
        }
    }
}
