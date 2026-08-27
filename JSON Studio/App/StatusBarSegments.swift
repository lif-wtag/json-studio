import Foundation
import JSONKit

/// The status bar's text, assembled once so the visible segments and the VoiceOver string cannot
/// drift apart (SH-04, `Design/error-copy.md` §Status bar).
///
/// The bar is drawn as separate runs — the validity label in SF Pro and its semantic colour, every
/// figure in SF Mono with tabular digits — but `Design/error-copy.md` specifies it as one string,
/// and VoiceOver reads that string. So the segments are the source and the announcement is their
/// join: `StatusBarSegmentsTests` asserts the leading group joined with " · " is exactly
/// `ParseErrorCopy.statusSummary(…)`. Improvising the wording here would go unnoticed otherwise.
struct StatusBarSegments: Equatable {

    struct Segment: Equatable {
        var text: String
        /// Figures are set in SF Mono with tabular digits so they don't shift as they change.
        var isFigure: Bool
    }

    /// Validity, properties, size, encoding. The first is the semantic label and is coloured.
    var leading: [Segment]
    /// Cursor position and indent mode. Chrome copy from the artboard, not error copy.
    var trailing: [Segment]

    /// The full string `Design/error-copy.md` specifies, and what VoiceOver reads.
    var accessibilityText: String {
        leading.map(\.text).joined(separator: " · ")
    }

    static func make(
        status: DocumentStatus,
        cursor: CursorPosition,
        indent: FormatOptions.Indent,
        locale: Locale = .autoupdatingCurrent
    ) -> StatusBarSegments {
        var leading: [Segment] = []

        switch status.validity {
        case .empty:
            leading.append(Segment(text: ParseErrorCopy.emptyDocument, isFigure: false))

        case .valid:
            leading.append(Segment(text: Semantic.valid.label, isFigure: false))
            if let properties = status.statistics?.properties {
                leading.append(Segment(
                    text: "\(properties.formatted(.number.locale(locale))) properties",
                    isFigure: true
                ))
            }
            leading.append(Segment(text: ParseErrorCopy.byteSize(status.byteCount), isFigure: true))
            leading.append(Segment(text: status.encoding.label, isFigure: true))

        case .invalid(let count, let line, let column):
            // One string, not a label plus figures: the copy for these two states is a sentence
            // ("1 error · line 42, column 18"), and splitting it would invent punctuation.
            leading.append(Segment(
                text: ParseErrorCopy.statusSummary(
                    errorCount: count, firstLine: line, firstColumn: column
                ),
                isFigure: false
            ))
        }

        return StatusBarSegments(
            leading: leading,
            trailing: [
                Segment(text: cursor.label(locale: locale), isFigure: true),
                Segment(text: indent.label, isFigure: true),
            ]
        )
    }
}

/// The caret's one-based line and column (SH-04).
///
/// Task 22 publishes the real one from the text view; until the editor exists every document sits
/// at its start, which is where a caret genuinely is in a document nobody has clicked into.
struct CursorPosition: Sendable, Equatable {
    var line: Int = 1
    var column: Int = 1

    func label(locale: Locale = .autoupdatingCurrent) -> String {
        let l = line.formatted(.number.grouping(.never).locale(locale))
        let c = column.formatted(.number.grouping(.never).locale(locale))
        return "Ln \(l), Col \(c)"
    }
}
