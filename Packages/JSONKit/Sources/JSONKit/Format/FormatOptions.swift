/// Options for `Formatter`.
///
/// One command, not two. A width-aware "Beautify" verb was proposed on 2026-08-26 and rejected —
/// in practice it means the same thing to a developer as Format, and a toolbar pill that
/// duplicates its neighbour is the weakest kind of addition. So width-awareness lives here, as a
/// **preference on the one Format command** (FM-03), and `printWidth` is the whole of it.
public struct FormatOptions: Sendable, Equatable {
    public enum Indent: Sendable, Equatable {
        case spaces(Int)
        case tab

        var text: String {
            switch self {
            case .spaces(let count): String(repeating: " ", count: max(0, count))
            case .tab: "\t"
            }
        }

        /// Columns this indent occupies, for the width test. A tab is counted as the editor
        /// displays it, so the same document doesn't wrap differently than it looks.
        var columns: Int {
            switch self {
            case .spaces(let count): max(0, count)
            case .tab: 4
            }
        }

        /// What the status bar shows (SH-04): "2 spaces", "Tabs".
        public var label: String {
            switch self {
            case .spaces(let count): "\(count) space\(count == 1 ? "" : "s")"
            case .tab: "Tabs"
            }
        }
    }

    /// Ignore `indent` and `printWidth` and emit the most compact legal form (minify).
    public var compact: Bool
    public var indent: Indent

    /// Column budget for keeping a container on one line. A container is inlined when its whole
    /// rendering fits the remaining width — which is why the sample payload reads the way a
    /// developer would have written it by hand rather than one scalar per line.
    ///
    /// `nil` turns width-awareness off entirely: every container breaks, one value per line.
    /// That is the strictly-uniform output, useful for diffing by line and for narrow panes.
    public var printWidth: Int?

    public var trailingNewline: Bool

    public init(
        compact: Bool = false,
        indent: Indent = .spaces(2),
        printWidth: Int? = 100,
        trailingNewline: Bool = false
    ) {
        self.compact = compact
        self.indent = indent
        self.printWidth = printWidth
        self.trailingNewline = trailingNewline
    }

    /// The default Format command: 2 spaces, width-aware at 100 columns.
    public static let pretty = FormatOptions()

    /// Every container broken, one value per line. No width heuristic.
    public static let uniform = FormatOptions(printWidth: nil)

    public static let minified = FormatOptions(compact: true)
}
