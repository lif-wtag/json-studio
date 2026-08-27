import Foundation
import JSONKit

/// Exit codes, so the CLI is usable from CI and from a shell conditional.
public enum ExitCode: Int32 {
    /// Valid, or two documents identical.
    case ok = 0
    /// The document has errors, or the two documents differ. Not a failure of the tool.
    case findings = 1
    /// Bad usage, or the file could not be read.
    case usage = 2
}

public struct Document {
    let path: String
    let text: String
    let encoding: String.Encoding
    let byteCount: Int

    /// Reads with Foundation's own encoding detection, so a UTF-16 payload is not reported as
    /// unreadable. Full detection with BOM handling is DC-09, in the app.
    static func read(_ path: String) -> Document? {
        var used = String.Encoding.utf8
        guard let text = try? String(contentsOfFile: path, usedEncoding: &used) else { return nil }
        let bytes = (try? Data(contentsOf: URL(fileURLWithPath: path)).count) ?? text.utf8.count
        return Document(path: path, text: text, encoding: used, byteCount: bytes)
    }
}

public enum Commands {

    // MARK: parse

    public static func parse(_ path: String, into output: inout CommandOutput) -> ExitCode {
        guard let document = Document.read(path) else {
            output.error("jsonstudio-cli: cannot read \(path)")
            return .usage
        }
        let result = Parser().parse(document.text)

        guard !result.isEmpty else {
            output.line(ParseErrorCopy.emptyDocument)
            return .ok
        }

        for error in result.errors {
            output.line(Output.render(
                error, in: document.text, lineIndex: result.lineIndex, path: document.path
            ))
        }

        let first = result.errors.first.map { result.lineIndex.position(at: $0.span.start) }
        let properties = result.tree.flatMap { try? StatisticsWalker().walk($0) }?.properties
        output.line(ParseErrorCopy.statusSummary(
            errorCount: result.errors.count,
            firstLine: first?.line,
            firstColumn: first?.column,
            properties: result.errors.isEmpty ? properties : nil,
            size: result.errors.isEmpty ? Output.byteSize(document.byteCount) : nil,
            encoding: result.errors.isEmpty ? Output.name(of: document.encoding) : nil
        ))
        return result.errors.isEmpty ? .ok : .findings
    }

    // MARK: format

    public static func format(
        _ path: String, options: FormatOptions, sort: Bool, prune: Pruner?,
        into output: inout CommandOutput
    ) -> ExitCode {
        guard let document = Document.read(path) else {
            output.error("jsonstudio-cli: cannot read \(path)")
            return .usage
        }
        let result = Parser().parse(document.text)
        guard result.errors.isEmpty else {
            // Formatting a recovered tree would emit valid JSON that silently differs from what
            // the developer wrote. Refuse, and point at the first problem.
            output.error("jsonstudio-cli: \(path) is not valid JSON — run `parse` to see why")
            return .findings
        }
        guard var tree = result.tree else {
            output.error("jsonstudio-cli: \(path) is empty")
            return .usage
        }

        if sort { tree = KeySorter(recursive: true).sorted(tree) }
        if let prune {
            guard let kept = prune.pruned(tree) else {
                output.error("jsonstudio-cli: pruning removed the whole document")
                return .findings
            }
            tree = kept
        }
        // Formatted against the ORIGINAL source, which is what keeps scalars byte-exact after a
        // transform. See TreeTransform.
        output.line(Formatter(options: options).format(tree, source: document.text))
        return .ok
    }

    // MARK: stats

    public static func stats(_ path: String, into output: inout CommandOutput) -> ExitCode {
        guard let document = Document.read(path) else {
            output.error("jsonstudio-cli: cannot read \(path)")
            return .usage
        }
        let result = Parser().parse(document.text)
        guard let tree = result.tree, let statistics = try? StatisticsWalker().walk(tree) else {
            output.line(ParseErrorCopy.emptyDocument)
            return .ok
        }
        if !result.errors.isEmpty {
            output.error("jsonstudio-cli: \(path) has \(result.errors.count) error(s); "
                + "counting the partial tree")
        }

        // A typographic table, right-aligned — the same shape IN-09 specifies, no charts.
        let rows: [(String, Int)] = [
            ("Objects", statistics.objects),
            ("Arrays", statistics.arrays),
            ("Properties", statistics.properties),
            ("Strings", statistics.strings),
            ("Numbers", statistics.numbers),
            ("Booleans", statistics.booleans),
            ("Nulls", statistics.nulls),
            ("Max depth", statistics.maxDepth),
            ("Characters", statistics.characterCount),
        ]
        let label = rows.map(\.0.count).max() ?? 0
        let value = rows.map { String($0.1).count }.max() ?? 0
        for (name, count) in rows {
            let padded = name.padding(toLength: label, withPad: " ", startingAt: 0)
            output.line("\(padded)  \(String(repeating: " ", count: value - String(count).count))\(count)")
        }
        output.line("")
        output.line("\(Output.byteSize(document.byteCount)) · \(Output.name(of: document.encoding))")
        return result.errors.isEmpty ? .ok : .findings
    }

    // MARK: diff

    public static func diff(
        _ leftPath: String, _ rightPath: String, matching: ArrayMatching,
        into output: inout CommandOutput
    ) -> ExitCode {
        guard let left = Document.read(leftPath) else {
            output.error("jsonstudio-cli: cannot read \(leftPath)")
            return .usage
        }
        guard let right = Document.read(rightPath) else {
            output.error("jsonstudio-cli: cannot read \(rightPath)")
            return .usage
        }
        let leftResult = Parser().parse(left.text), rightResult = Parser().parse(right.text)
        guard let leftTree = leftResult.tree, let rightTree = rightResult.tree else {
            output.error("jsonstudio-cli: both documents must contain a value")
            return .usage
        }
        guard let changes = try? StructuralDiff(arrayMatching: matching).diff(leftTree, rightTree)
        else {
            output.error("jsonstudio-cli: diff was cancelled")
            return .usage
        }

        guard !changes.isEmpty else {
            output.line("Identical · 0 changes")
            return .ok
        }
        for change in changes {
            output.line("\(sign(change.kind)) \(change.path)\(detail(change))")
        }
        output.line("")
        // The change summary CP-07 specifies: a total, broken down by class.
        let counts = DiffChange.Kind.allCases.map { kind in
            (label(kind), changes.filter { $0.kind == kind }.count)
        }.filter { $0.1 > 0 }
        output.line("\(changes.count) change\(changes.count == 1 ? "" : "s") · "
            + counts.map { "\($0.1) \($0.0)" }.joined(separator: " · "))
        return .findings
    }

    /// The gutter signs the design specifies for added and removed, so the output stays readable
    /// without colour — which a pipe has none of anyway.
    private static func sign(_ kind: DiffChange.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .modified: "~"
        case .typeChanged: "≠"
        }
    }

    /// Labels transcribed from `Design/tokens.md`: "Changed", not "Modified".
    private static func label(_ kind: DiffChange.Kind) -> String {
        switch kind {
        case .added: "added"
        case .removed: "removed"
        case .modified: "changed"
        case .typeChanged: "type-changed"
        }
    }

    private static func detail(_ change: DiffChange) -> String {
        if let transition = change.typeTransition {
            return "  \(transition.from.rawValue) → \(transition.to.rawValue)"
        }
        return ""
    }
}
