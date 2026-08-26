/// A half-open range in the source text, measured in **UTF-16 code units** (ADR-01).
///
/// UTF-16 because everything above JSONKit — `NSTextView`, `NSRange`, `NSLayoutManager` —
/// is UTF-16 based. Storing UTF-8 byte offsets would mean converting on every selection
/// change. Line/column are derived lazily from `LineIndex`, never stored here.
public struct SourceSpan: Sendable, Hashable {
    /// Inclusive lower bound, UTF-16 code-unit offset.
    public var start: Int
    /// Exclusive upper bound, UTF-16 code-unit offset.
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var length: Int { end - start }
    public var isEmpty: Bool { end <= start }
}
