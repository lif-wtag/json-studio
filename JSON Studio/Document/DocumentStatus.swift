import Foundation
import JSONKit

/// What the status bar reports about the document (SH-04).
///
/// A value type rather than a set of properties on the document, so it can be computed off the
/// main actor and published as one atomic update — a status bar showing a new property count
/// beside a stale validity glyph would be worse than one that lagged.
///
/// **`nonisolated`, and that is the point.** The app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated type is main-actor isolated and
/// a `Task.detached` calling into it would hop straight back to the main actor — parsing on the
/// main thread while looking as though it did not. The 0 ms main-thread budget is enforced here,
/// by the annotation, not by the shape of the call site.
///
/// The **words** are not chosen here. `ParseErrorCopy` owns them (`Design/error-copy.md`) and
/// `StatusBarSegments` is pinned to it by test. This type carries only the numbers.
nonisolated struct DocumentStatus: Sendable, Equatable {

    /// The three states the design draws. `Checking…` — the fourth — belongs to Task 23, which
    /// introduces the debounce that makes a parse long enough to be worth announcing.
    enum Validity: Sendable, Equatable {
        case empty
        case valid
        case invalid(errorCount: Int, firstLine: Int?, firstColumn: Int?)
    }

    var validity: Validity
    /// Present only for a document that parsed cleanly. Task 25's Structure header reads
    /// `maxDepth` from here — it is computed to get `properties` anyway, so carrying the rest is
    /// free and saves a second walk.
    var statistics: Statistics?
    /// Bytes as the document would be written back, so the figure matches what lands on disk —
    /// a BOM included, and UTF-16's two bytes per code unit.
    var byteCount: Int
    var encoding: DocumentEncoding

    static let empty = DocumentStatus(validity: .empty, byteCount: 0, encoding: .utf8)

    /// The semantic for the validity glyph. `nil` for an empty document, which the design gives no
    /// glyph — there is nothing yet to be right or wrong about.
    var semantic: Semantic? {
        switch validity {
        case .empty: nil
        case .valid: .valid
        case .invalid: .invalid
        }
    }

    /// Whether Format and Minify may run. The CLI already refuses an invalid document, for the
    /// reason that matters here too: formatting a *recovered* tree emits valid JSON that silently
    /// differs from what the developer wrote, which is the worst thing a formatter can do.
    var isFormattable: Bool {
        if case .valid = validity { true } else { false }
    }

    /// Parses `text` and measures it. Pure, and deliberately synchronous — the caller decides
    /// which actor it runs on, and every caller here runs it off the main one.
    static func make(text: String, encoding: DocumentEncoding) -> DocumentStatus {
        let byteCount = encoding.encode(text).count
        let result = Parser().parse(text)

        guard !result.isEmpty else {
            return DocumentStatus(validity: .empty, byteCount: byteCount, encoding: encoding)
        }

        if result.errors.isEmpty, let tree = result.tree {
            return DocumentStatus(
                validity: .valid,
                statistics: try? StatisticsWalker().walk(tree),
                byteCount: byteCount,
                encoding: encoding
            )
        }

        // Errors come back in cause order, so `first` is the one the status bar should name and
        // the one the gutter's topmost marker will point at — they agree by construction.
        let position = result.errors.first.map { result.lineIndex.position(at: $0.span.start) }
        return DocumentStatus(
            validity: .invalid(
                errorCount: max(result.errors.count, 1),
                firstLine: position?.line,
                firstColumn: position?.column
            ),
            byteCount: byteCount,
            encoding: encoding
        )
    }
}
