/// Maps a UTF-16 offset to a 1-based `(line, column)` and back, via a cached table of
/// line-start offsets. Built once per parse and reused; derivation is lazy (ADR-01).
///
/// Phase 2: scan the source once recording each line start, then binary-search on lookup.
public struct LineIndex: Sendable {
    /// UTF-16 offset at which each line begins. `lineStarts[0] == 0`.
    public let lineStarts: [Int]

    public init(lineStarts: [Int] = [0]) {
        self.lineStarts = lineStarts
    }

    /// 1-based line and column for a UTF-16 offset.
    public func position(at offset: Int) -> (line: Int, column: Int) {
        // TODO Phase 2: binary-search lineStarts.
        (line: 1, column: max(1, offset + 1))
    }
}
