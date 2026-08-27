import Foundation

/// Collected output, so the driver is a pure function of its arguments and the filesystem.
///
/// Writing straight to `stdout` would make the CLI untestable from a test target, and CI depends
/// on the CLI — it is the only way the domain runs with no UI (ADR-05). Collecting instead costs
/// one array; documents here are megabytes at most, and `format` is the only command whose output
/// is large.
public struct CommandOutput: Sendable {
    public private(set) var out: [String] = []
    public private(set) var err: [String] = []

    public init() {}

    public mutating func line(_ text: String) { out.append(text) }
    public mutating func error(_ text: String) { err.append(text) }

    /// Everything written to stdout, as it would appear.
    public var stdout: String { out.joined(separator: "\n") }
    public var stderr: String { err.joined(separator: "\n") }

    /// Writes what was collected to the real handles.
    public func flush() {
        if !out.isEmpty { print(out.joined(separator: "\n")) }
        if !err.isEmpty { FileHandle.standardError.write(Data((err.joined(separator: "\n") + "\n").utf8)) }
    }
}
