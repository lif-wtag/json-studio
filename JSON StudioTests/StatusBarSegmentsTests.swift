import Foundation
import Testing
@testable import JSON_Studio
import JSONKit

// Task 16. The status bar's copy is specified in `Design/error-copy.md` §Status bar as one string,
// but the artboard draws it as separate runs — the validity label in SF Pro and its semantic
// colour, every figure in SF Mono. Splitting it in the view is therefore a place where wording can
// be improvised without anyone noticing, which the project contract forbids.
//
// So the join is asserted. If a segment's wording drifts from `ParseErrorCopy`, these fail.

@Suite("Status bar segments")
struct StatusBarSegmentsTests {

    /// Deterministic, so a machine in a de_DE locale doesn't fail on a decimal comma.
    private let locale = Locale(identifier: "en_US_POSIX")

    private func segments(
        _ validity: DocumentStatus.Validity,
        statistics: Statistics? = nil,
        byteCount: Int = 0,
        encoding: DocumentEncoding = .utf8,
        cursor: CursorPosition = CursorPosition(),
        indent: FormatOptions.Indent = .spaces(2)
    ) -> StatusBarSegments {
        StatusBarSegments.make(
            status: DocumentStatus(
                validity: validity, statistics: statistics, byteCount: byteCount, encoding: encoding
            ),
            cursor: cursor,
            indent: indent,
            locale: locale
        )
    }

    private func statistics(properties: Int) -> Statistics {
        var s = Statistics()
        s.properties = properties
        return s
    }

    // MARK: - The pin

    @Test("the valid line joins to exactly the string error-copy.md specifies")
    func validJoinsToTheSpecifiedString() {
        // The fixture's own figures, which are also the ones the artboard renders.
        let s = segments(.valid, statistics: statistics(properties: 119), byteCount: 3771)
        #expect(s.accessibilityText == ParseErrorCopy.statusSummary(
            errorCount: 0, properties: 119, size: "3.7 KB", encoding: "UTF-8"
        ))
        #expect(s.accessibilityText == "Valid JSON · 119 properties · 3.7 KB · UTF-8")
    }

    @Test("one error joins to the specified string, and is not split into figures")
    func oneErrorJoinsToTheSpecifiedString() {
        let s = segments(.invalid(errorCount: 1, firstLine: 42, firstColumn: 18))
        #expect(s.accessibilityText == ParseErrorCopy.statusSummary(
            errorCount: 1, firstLine: 42, firstColumn: 18
        ))
        // The copy is a sentence — splitting "line 42, column 18" into runs would invent
        // punctuation the copy document does not specify.
        #expect(s.leading.count == 1)
    }

    @Test("several errors name the first line, not every line")
    func severalErrors() {
        let s = segments(.invalid(errorCount: 4, firstLine: 7, firstColumn: 3))
        #expect(s.accessibilityText == ParseErrorCopy.statusSummary(errorCount: 4, firstLine: 7))
        #expect(s.accessibilityText == "4 errors · first on line 7")
    }

    @Test("an empty document is not an error, and says so in the specified words")
    func emptyDocument() {
        let s = segments(.empty)
        #expect(s.accessibilityText == ParseErrorCopy.emptyDocument)
    }

    // MARK: - Typography

    @Test("figures are flagged for tabular mono; the validity label is not")
    func figureFlags() {
        let s = segments(.valid, statistics: statistics(properties: 119), byteCount: 3771)
        // `#expect` decomposes its argument, and its `rethrows` analysis rejects a key-path
        // `allSatisfy` call — hoist the result first.
        let figuresAfterTheLabel = s.leading.dropFirst().allSatisfy(\.isFigure)
        let trailingAreAllFigures = s.trailing.allSatisfy(\.isFigure)
        #expect(s.leading.first?.isFigure == false)
        #expect(figuresAfterTheLabel)
        #expect(trailingAreAllFigures)
    }

    // MARK: - The trailing group

    @Test("cursor and indent render as the artboard draws them")
    func trailingGroup() {
        let s = segments(.valid, cursor: CursorPosition(line: 30, column: 20), indent: .spaces(2))
        #expect(s.trailing.map(\.text) == ["Ln 30, Col 20", "2 spaces"])
    }

    @Test("a four-figure line number is not grouped — Ln 1,024 would read as two numbers")
    func lineNumbersAreUngrouped() {
        let s = segments(.valid, cursor: CursorPosition(line: 1024, column: 3))
        #expect(s.trailing.first?.text == "Ln 1024, Col 3")
    }

    @Test("indent mode follows the preference, using the domain's own label")
    func indentModes() {
        #expect(segments(.valid, indent: .spaces(4)).trailing.last?.text == "4 spaces")
        #expect(segments(.valid, indent: .tab).trailing.last?.text == "Tabs")
    }

    // MARK: - Encoding

    @Test("the encoding segment names what will be written back, BOM included")
    func encodingSegment() {
        let s = segments(.valid, byteCount: 3771, encoding: .utf8WithBOM)
        #expect(s.leading.last?.text == "UTF-8 with BOM")
    }
}
