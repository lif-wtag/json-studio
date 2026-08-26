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
        }
    }

    /// Status-bar summary. `Design/error-copy.md` specifies the exact shapes.
    public static func statusSummary(errorCount: Int, firstLine: Int?, firstColumn: Int?) -> String {
        switch errorCount {
        case 0:
            return "Valid JSON"
        case 1:
            guard let line = firstLine, let column = firstColumn else { return "1 error" }
            return "1 error · line \(line), column \(column)"
        default:
            guard let line = firstLine else { return "\(errorCount) errors" }
            return "\(errorCount) errors · first on line \(line)"
        }
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
