/// Options for `Formatter`. Round-trip fidelity is guaranteed: formatting then reparsing
/// yields an equal tree.
public struct FormatOptions: Sendable, Equatable {
    public enum Indent: Sendable, Equatable {
        case spaces(Int)
        case tab
    }

    /// Ignore `indent` and emit the most compact legal form (minify).
    public var compact: Bool
    public var indent: Indent
    public var trailingNewline: Bool

    public init(compact: Bool = false, indent: Indent = .spaces(2), trailingNewline: Bool = false) {
        self.compact = compact
        self.indent = indent
        self.trailingNewline = trailingNewline
    }

    public static let pretty = FormatOptions()
    public static let minified = FormatOptions(compact: true)
}
