import Foundation
import JSONKit

/// Rendering helpers. Everything user-facing that JSONKit already owns — error prose, the status
/// line — comes from `ParseErrorCopy`; this file only arranges it.
public enum Output {

    /// `3.7 KB`, matching the `{size}` placeholder in `Design/error-copy.md` §Status bar.
    public static func byteSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB"]
        var value = Double(bytes) / 1024, index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return String(format: "%.1f %@", value, units[index])
    }

    public static func name(of encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16, .utf16LittleEndian, .utf16BigEndian: "UTF-16"
        case .ascii: "ASCII"
        default: "\(encoding)"
        }
    }

    /// One error, in `file:line:column:` form so editors and CI can jump to it, followed by the
    /// exact copy from `Design/error-copy.md` and an excerpt of the cause line.
    ///
    /// **The excerpt points at the cause, not the detection point.** That is the whole
    /// differentiator (Phase 0), and until now nothing has rendered it anywhere — the parser has
    /// been carrying `span` and `detectedAt` for five tasks with no way to see the difference.
    public static func render(
        _ error: ParseError, in source: String, lineIndex: LineIndex, path: String
    ) -> String {
        let position = lineIndex.position(at: error.span.start)
        let copy = error.copy
        var out = "\(path):\(position.line):\(position.column): \(copy.title)\n"
        out += "    \(copy.body)\n"

        if let excerpt = excerpt(at: error.span, in: source, lineIndex: lineIndex) {
            out += "\n" + excerpt
        }
        if error.wasDetectedElsewhere, let detected = error.detectedAt {
            let where_ = lineIndex.position(at: detected.start)
            out += "\n    (noticed at line \(where_.line), column \(where_.column))\n"
        }
        return out
    }

    /// The cause line with the span marked beneath it.
    private static func excerpt(
        at span: SourceSpan, in source: String, lineIndex: LineIndex
    ) -> String? {
        let position = lineIndex.position(at: span.start)
        guard let lineSpan = lineIndex.span(ofLine: position.line) else { return nil }

        let units = Array(source.utf16)
        let end = min(lineSpan.end, units.count)
        guard lineSpan.start <= end else { return nil }
        var text = String(decoding: units[lineSpan.start..<end], as: UTF16.self)
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }

        let gutter = String(position.line).count
        let pad = String(repeating: " ", count: gutter)
        // A zero-width span — a missing comma, colon or value — marks one column: there is no
        // offending text to underline, only a place where something belongs.
        let width = max(1, min(span.length, max(1, text.utf16.count - (position.column - 1))))
        let marker = String(repeating: " ", count: max(0, position.column - 1))
            + String(repeating: "^", count: width)

        return """
            \(position.line) │ \(text)
            \(pad) │ \(marker)
        """
    }
}
