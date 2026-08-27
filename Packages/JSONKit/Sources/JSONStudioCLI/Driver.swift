import Foundation
import JSONKit

// jsonstudio-cli — exercises JSONKit with no UI, so the domain is runnable in CI and by hand
// before any app exists (ADR-05).
//
// Hand-rolled argument parsing: adding swift-argument-parser would be a third-party dependency,
// which needs an ADR. Four subcommands and a handful of flags do not justify one.

func usageText() -> String {
    """
    jsonstudio-cli \(JSONKit.version)

    usage:
      jsonstudio-cli parse  <file>
      jsonstudio-cli format <file> [options]
      jsonstudio-cli stats  <file>
      jsonstudio-cli diff   <file-a> <file-b> [--match <strategy>]

    format options:
      --minify              most compact legal form
      --indent <n|tab>      spaces per level, or literal tabs (default 2)
      --width <n|none>      keep a container inline while it fits (default 100)
      --newline             end with a trailing newline
      --sort                sort object keys recursively
      --strip-nulls         drop null members and elements
      --strip-empty         drop empty strings and empty containers

    diff strategies:
      index                 position against position
      identity:<key>        pair records by the value of <key>
      heuristic             align on unchanged elements (default)

    exit codes:
      0  valid, or identical
      1  errors found, or documents differ
      2  bad usage, or the file could not be read
    """
}

/// Reads `--flag value` pairs and bare flags out of the argument list.
struct Arguments {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    private(set) var positional: [String] = []
    private(set) var unknown: [String] = []

    init(_ arguments: [String], valueFlags: Set<String>) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if valueFlags.contains(name) {
                    guard index + 1 < arguments.count else { unknown.append(argument); break }
                    values[name] = arguments[index + 1]
                    index += 2
                    continue
                }
                flags.insert(name)
            } else {
                positional.append(argument)
            }
            index += 1
        }
    }

    func has(_ name: String) -> Bool { flags.contains(name) }
    func value(_ name: String) -> String? { values[name] }

    /// Flags that were passed but are not recognised by this subcommand — reported rather than
    /// ignored, because a silently dropped `--minify` produces plausible wrong output.
    func unrecognised(known: Set<String>) -> [String] {
        flags.subtracting(known).map { "--\($0)" } + unknown
    }
}


public enum Driver {

    /// Runs one invocation. A pure function of its arguments and the filesystem, so the tests can
    /// assert on exactly what a user would see.
    public static func run(_ arguments: [String], into output: inout CommandOutput) -> ExitCode {
        guard let command = arguments.first else {
            output.line(usageText())
            return .usage
        }
        let rest = Array(arguments.dropFirst())

        func requireFiles(_ parsed: Arguments, count: Int = 1) -> [String]? {
            guard parsed.positional.count == count else {
                output.error("jsonstudio-cli: \(command) needs \(count) file argument(s)")
                return nil
            }
            return parsed.positional
        }
        /// Unknown flags are reported rather than ignored: a silently dropped `--minify` produces
        /// plausible, wrong output.
        func rejectUnknown(_ parsed: Arguments, known: Set<String>) -> Bool {
            let unknown = parsed.unrecognised(known: known)
            guard unknown.isEmpty else {
                output.error("jsonstudio-cli: unknown option(s) \(unknown.joined(separator: " "))")
                return false
            }
            return true
        }

        switch command {
        case "parse":
            let parsed = Arguments(rest, valueFlags: [])
            guard rejectUnknown(parsed, known: []), let files = requireFiles(parsed) else { return .usage }
            return Commands.parse(files[0], into: &output)

        case "format":
            let parsed = Arguments(rest, valueFlags: ["indent", "width"])
            let known: Set<String> = ["minify", "newline", "sort", "strip-nulls", "strip-empty"]
            guard rejectUnknown(parsed, known: known), let files = requireFiles(parsed) else { return .usage }

            var indent = FormatOptions.Indent.spaces(2)
            if let raw = parsed.value("indent") {
                if raw == "tab" { indent = .tab }
                else if let count = Int(raw), count >= 0 { indent = .spaces(count) }
                else {
                    output.error("jsonstudio-cli: --indent takes a number or 'tab'")
                    return .usage
                }
            }
            var width: Int? = 100
            if let raw = parsed.value("width") {
                if raw == "none" { width = nil }
                else if let columns = Int(raw), columns > 0 { width = columns }
                else {
                    output.error("jsonstudio-cli: --width takes a number or 'none'")
                    return .usage
                }
            }

            let options = FormatOptions(
                compact: parsed.has("minify"),
                indent: indent,
                printWidth: width,
                trailingNewline: parsed.has("newline")
            )
            let pruner = parsed.has("strip-nulls") || parsed.has("strip-empty")
                ? Pruner(
                    stripNulls: parsed.has("strip-nulls"),
                    stripEmptyStrings: parsed.has("strip-empty"),
                    stripEmptyCollections: parsed.has("strip-empty")
                )
                : nil
            return Commands.format(
                files[0], options: options, sort: parsed.has("sort"), prune: pruner, into: &output
            )

        case "stats":
            let parsed = Arguments(rest, valueFlags: [])
            guard rejectUnknown(parsed, known: []), let files = requireFiles(parsed) else { return .usage }
            return Commands.stats(files[0], into: &output)

        case "diff":
            let parsed = Arguments(rest, valueFlags: ["match"])
            guard rejectUnknown(parsed, known: []), let files = requireFiles(parsed, count: 2) else { return .usage }
            var matching = ArrayMatching.heuristic
            if let raw = parsed.value("match") {
                if raw == "index" { matching = .index }
                else if raw == "heuristic" { matching = .heuristic }
                else if raw.hasPrefix("identity:"), case let key = String(raw.dropFirst(9)), !key.isEmpty {
                    matching = .identityKey(key)
                } else {
                    output.error("jsonstudio-cli: --match takes index, identity:<key> or heuristic")
                    return .usage
                }
            }
            return Commands.diff(files[0], files[1], matching: matching, into: &output)

        case "-h", "--help", "help":
            output.line(usageText())
            return .ok

        case "--version":
            output.line(JSONKit.version)
            return .ok

        default:
            output.error("jsonstudio-cli: unknown command '\(command)'")
            output.line(usageText())
            return .usage
        }
    }
}
