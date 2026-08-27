/// A half-open range in the source text, measured in **UTF-16 code units** (ADR-01).
///
/// UTF-16 because everything above JSONKit — `NSTextView`, `NSRange`, `NSLayoutManager` — is
/// UTF-16 based. Storing UTF-8 byte offsets would mean converting on every selection change.
/// Line and column are derived lazily from `LineIndex`, never stored here: a stored line number
/// is wrong the moment the document is edited above it.
///
/// Half-open is stated once, here, and relied on everywhere: `start` is included, `end` is not.
public struct SourceSpan: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Inclusive lower bound, UTF-16 code-unit offset.
    public var start: Int
    /// Exclusive upper bound, UTF-16 code-unit offset.
    public var end: Int

    public init(start: Int, end: Int) {
        precondition(start >= 0, "span start must be non-negative")
        precondition(end >= start, "span end must not precede start")
        self.start = start
        self.end = end
    }

    /// A zero-width span. Used for errors that point *between* tokens — a missing comma, an
    /// unexpected end of input — where there is no offending text to underline.
    public static func empty(at offset: Int) -> SourceSpan {
        SourceSpan(start: offset, end: offset)
    }

    public var length: Int { end - start }
    public var isEmpty: Bool { end == start }

    /// `true` when `offset` falls inside the span. A zero-width span contains nothing, but
    /// `touches` accepts its own position — the distinction matters for caret-in-node tests,
    /// where a caret sitting at a node's closing brace is still "in" that node.
    public func contains(_ offset: Int) -> Bool {
        offset >= start && offset < end
    }

    /// `true` when `offset` is inside the span or exactly at either boundary.
    public func touches(_ offset: Int) -> Bool {
        offset >= start && offset <= end
    }

    public func overlaps(_ other: SourceSpan) -> Bool {
        start < other.end && other.start < end
    }

    /// `true` when this span entirely encloses `other`. A span contains itself.
    public func contains(_ other: SourceSpan) -> Bool {
        start <= other.start && other.end <= end
    }

    /// The smallest span covering both, including any gap between them.
    public func union(_ other: SourceSpan) -> SourceSpan {
        SourceSpan(start: min(start, other.start), end: max(end, other.end))
    }

    /// Clamped into `limit`. Returns an empty span at the nearest boundary when they are disjoint,
    /// so callers never have to handle a nil.
    public func clamped(to limit: SourceSpan) -> SourceSpan {
        let lo = min(max(start, limit.start), limit.end)
        let hi = max(min(end, limit.end), limit.start)
        return SourceSpan(start: lo, end: max(lo, hi))
    }

    /// Ordered by start, then by end — so sorting a span list gives document order, and nested
    /// spans sort outermost-first at the same start.
    public static func < (lhs: SourceSpan, rhs: SourceSpan) -> Bool {
        lhs.start == rhs.start ? lhs.end > rhs.end : lhs.start < rhs.start
    }

    public var description: String { "\(start)..<\(end)" }
}
