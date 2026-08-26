/// Maps a UTF-16 offset to a 1-based `(line, column)` and back, via a cached table of line-start
/// offsets. Built once per parse in a single pass; every lookup is a binary search (ADR-01).
///
/// **Recognises `\n`, `\r\n` and a lone `\r`.** RFC 8259 permits all three as whitespace, and
/// treating `\r\n` as two breaks would put every reported line number off by one on a
/// Windows-authored payload — a humiliating bug in a tool whose pitch is that it tells you the
/// right line.
public struct LineIndex: Sendable {
    /// UTF-16 offset at which each line begins. Always non-empty; `lineStarts[0] == 0`.
    public let lineStarts: [Int]
    /// Total length of the indexed source, in UTF-16 code units.
    public let length: Int

    /// Builds the index by scanning `source` once.
    public init(source: String) {
        var starts = [0]
        var offset = 0
        var previousWasCR = false

        for unit in source.utf16 {
            offset += 1
            if previousWasCR && unit != 0x000A {
                // A lone CR ended the previous line; this unit begins the next one.
                starts.append(offset - 1)
            }
            switch unit {
            case 0x000A:                       // LF — ends the line whether or not a CR preceded
                starts.append(offset)
                previousWasCR = false
            case 0x000D:                       // CR — decided once we see what follows
                previousWasCR = true
            default:
                previousWasCR = false
            }
        }
        if previousWasCR {
            starts.append(offset)              // source ended on a lone CR
        }

        self.lineStarts = starts
        self.length = offset
    }

    /// Direct construction, for tests and for callers that already have the table.
    public init(lineStarts: [Int] = [0], length: Int = 0) {
        precondition(!lineStarts.isEmpty, "lineStarts must contain at least the zero offset")
        precondition(lineStarts[0] == 0, "lineStarts must begin at 0")
        self.lineStarts = lineStarts
        self.length = length
    }

    /// Number of lines. A trailing newline does **not** create a further line: "a\n" is one line,
    /// matching how editors number them.
    public var lineCount: Int {
        if lineStarts.count > 1 && lineStarts[lineStarts.count - 1] == length {
            return lineStarts.count - 1
        }
        return lineStarts.count
    }

    /// 1-based line and column for a UTF-16 offset. Offsets past the end clamp to the last
    /// position rather than trapping — a stale offset from the UI should degrade, not crash.
    public func position(at offset: Int) -> (line: Int, column: Int) {
        let clamped = min(max(offset, 0), length)
        let line = lineIndex(containing: clamped)
        return (line: line + 1, column: clamped - lineStarts[line] + 1)
    }

    /// UTF-16 offset for a 1-based line and column. Out-of-range input clamps.
    public func offset(line: Int, column: Int) -> Int {
        let lineIdx = min(max(line - 1, 0), lineStarts.count - 1)
        let lineStart = lineStarts[lineIdx]
        let lineEnd = lineIdx + 1 < lineStarts.count ? lineStarts[lineIdx + 1] : length
        return min(max(lineStart + max(column - 1, 0), lineStart), lineEnd)
    }

    /// The span of a 1-based line, **including** its terminator. Returns nil for a line that
    /// does not exist.
    public func span(ofLine line: Int) -> SourceSpan? {
        let idx = line - 1
        guard idx >= 0 && idx < lineStarts.count else { return nil }
        let end = idx + 1 < lineStarts.count ? lineStarts[idx + 1] : length
        return SourceSpan(start: lineStarts[idx], end: end)
    }

    /// Zero-based index into `lineStarts` for the line containing `offset`.
    private func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
