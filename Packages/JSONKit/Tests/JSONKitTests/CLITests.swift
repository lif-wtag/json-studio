import Foundation
import Testing
@testable import JSONKit
@testable import JSONStudioCLI

// Phase 2, step 10 / Task 12. The CLI is the only way the domain runs with no UI (ADR-05) and CI
// depends on it, which is why its logic lives in a library target rather than in the executable:
// a test target cannot import an executable.
//
// The assertions that matter are the exit codes (CI reads them) and the error rendering, which is
// the first time the cause-not-symptom copy is rendered anywhere at all.

/// Runs one invocation against a temporary file, returning what a user would see.
private func run(_ arguments: [String]) -> (code: ExitCode, out: String, err: String) {
    var output = CommandOutput()
    let code = Driver.run(arguments, into: &output)
    return (code, output.stdout, output.stderr)
}

/// Writes `contents` to a temp file and runs `arguments + [path]`.
private func runOn(_ contents: String, _ arguments: [String] = ["parse"]) throws
    -> (code: ExitCode, out: String, err: String) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("jsonstudio-cli-test-\(abs(contents.hashValue)).json")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return run(arguments + [url.path])
}

private var fixturePath: String { TestFixture.samplePayloadURL.path }

@Suite("CLI · parse")
struct CLIParseTests {

    @Test("the documented invocation works and reports the design's status line")
    func documentedInvocation() {
        // `CLAUDE.md` and `Packages/JSONKit/README.md` both promise this exact command.
        let result = run(["parse", fixturePath])
        #expect(result.code == .ok)
        // The shape from `Design/error-copy.md` §Status bar, with the design's own figures.
        #expect(result.out == "Valid JSON · 119 properties · 3.7 KB · UTF-8")
    }

    @Test("an error is reported at its CAUSE, not where the parser noticed")
    func reportsTheCause() throws {
        // The whole differentiator, rendered. The comma belongs at the end of line 2; a parser
        // that reported the detection point would say line 3, which is what every other tool does.
        let result = try runOn("{\n  \"a\": 1\n  \"b\": 2\n}\n")
        #expect(result.code == .findings)
        #expect(result.out.contains(":2:"), "should point at line 2, got:\n\(result.out)")
        #expect(result.out.contains("Add a comma after this value."))
        #expect(result.out.contains("The next property starts on line 3 without one."))
        #expect(result.out.contains("(noticed at line 3"), "and should name the detection point too")
    }

    @Test("several errors are reported at once, which a throwing parser could not do")
    func reportsSeveralErrors() throws {
        let result = try runOn("{\n  \"a\": 1\n  \"b\": True\n}\n")
        #expect(result.code == .findings)
        #expect(result.out.contains("Add a comma after this value."))
        #expect(result.out.contains("Replace True with a JSON value."))
        #expect(result.out.contains("2 errors · first on line 2"))
    }

    @Test("the excerpt marks the span, and a zero-width cause marks one column")
    func excerptMarksTheSpan() throws {
        let insertion = try runOn("{\n  \"a\": 1\n  \"b\": 2\n}\n")
        // A missing comma has nothing to underline — only a place where something belongs.
        #expect(insertion.out.contains("│ ") && insertion.out.contains("^"))
        #expect(!insertion.out.contains("^^"), "an insertion point is one column, not a range")

        let span = try runOn("{\"a\": True}")
        #expect(span.out.contains("^^^^"), "a real token is underlined across its width")
    }

    @Test("an empty document is reported as empty, not as an error")
    func emptyDocument() throws {
        let result = try runOn("   \n")
        #expect(result.code == .ok)
        #expect(result.out == "Empty document")
    }

    @Test("a missing file is a usage error, distinct from a parse failure")
    func missingFile() {
        let result = run(["parse", "/no/such/file.json"])
        #expect(result.code == .usage)
        #expect(result.err.contains("cannot read"))
    }
}

@Suite("CLI · format")
struct CLIFormatTests {

    @Test("format reproduces the formatter's own output")
    func formatMatchesTheLibrary() throws {
        let source = try sampleJSON()
        let tree = try #require(Parser().parse(source).tree)

        let pretty = run(["format", fixturePath])
        #expect(pretty.code == .ok)
        #expect(pretty.out == Formatter(options: .pretty).format(tree, source: source))

        let minified = run(["format", fixturePath, "--minify"])
        #expect(minified.out == Formatter(options: .minified).format(tree, source: source))
    }

    @Test("indent and width options reach the formatter")
    func options() throws {
        let uniform = run(["format", fixturePath, "--width", "none"])
        let tabs = run(["format", fixturePath, "--indent", "tab"])
        #expect(uniform.out.split(separator: "\n").count == 224, "uniform mode is 224 lines")
        #expect(tabs.out.contains("\n\t"))
    }

    @Test("--sort and --strip-nulls apply the transforms, formatted against the ORIGINAL source")
    func transforms() throws {
        let sorted = run(["format", fixturePath, "--sort", "--minify"])
        #expect(sorted.code == .ok)
        #expect(sorted.out.hasPrefix(#"{"account":"#), "keys sorted; got \(sorted.out.prefix(40))")
        // The transform kept spans, so the big integer is still re-emitted from source.
        #expect(sorted.out.contains("9007199254740993"))

        let stripped = run(["format", fixturePath, "--strip-nulls", "--minify"])
        #expect(!stripped.out.contains("null"))
    }

    @Test("formatting an invalid document is refused rather than silently repaired")
    func refusesInvalid() throws {
        // Formatting a recovered tree would emit valid JSON that differs from what was written.
        let result = try runOn("{\"a\": 1,}", ["format"])
        #expect(result.code == .findings)
        #expect(result.err.contains("not valid JSON"))
        #expect(result.out.isEmpty)
    }

    @Test("an unknown option is rejected, not ignored")
    func rejectsUnknownOptions() {
        // A silently dropped --minify would produce plausible, wrong output.
        let result = run(["format", fixturePath, "--minfy"])
        #expect(result.code == .usage)
        #expect(result.err.contains("unknown option"))
    }

    @Test("a malformed option value is rejected with a specific message")
    func rejectsBadValues() {
        #expect(run(["format", fixturePath, "--indent", "wide"]).code == .usage)
        #expect(run(["format", fixturePath, "--width", "-3"]).code == .usage)
    }
}

@Suite("CLI · stats and diff")
struct CLIStatsDiffTests {

    @Test("stats reports the walker's counts, including the design's two figures")
    func stats() {
        let result = run(["stats", fixturePath])
        #expect(result.code == .ok)

        // Asserting the row's content rather than its padding: the alignment is cosmetic and
        // changes with the widest label, so pinning spaces would test nothing and break often.
        func row(_ label: String) -> String? {
            result.out.split(separator: "\n")
                .first { $0.hasPrefix(label) }
                .map { $0.dropFirst(label.count).trimmingCharacters(in: .whitespaces) }
        }
        #expect(row("Properties") == "119", "the figure the status bar shows")
        #expect(row("Max depth") == "7", "the figure the inspector's Structure header shows")
        #expect(row("Nulls") == "6")
        #expect(result.out.contains("3.7 KB · UTF-8"))

        // Right-aligned, which is what IN-09 specifies — every value ends in the same column.
        let valueColumns = ["Objects", "Properties", "Characters"].compactMap { label in
            result.out.split(separator: "\n").first { $0.hasPrefix(label) }?.count
        }
        #expect(Set(valueColumns).count == 1, "rows are not aligned: \(valueColumns)")
    }

    @Test("identical documents diff to the artboard's own words")
    func identical() {
        let result = run(["diff", fixturePath, fixturePath])
        #expect(result.code == .ok)
        #expect(result.out == "Identical · 0 changes")
    }

    @Test("differences are listed by path with a summary, and exit 1 like diff(1)")
    func differences() throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("cli-diff-a.json")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("cli-diff-b.json")
        try #"{"keep":1,"gone":2,"num":1}"#.write(to: a, atomically: true, encoding: .utf8)
        try #"{"keep":1,"num":2,"new":3}"#.write(to: b, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }

        let result = run(["diff", a.path, b.path])
        #expect(result.code == .findings)
        #expect(result.out.contains("− $.gone"))
        #expect(result.out.contains("~ $.num"))
        #expect(result.out.contains("+ $.new"))
        #expect(result.out.contains("3 changes"))
    }

    @Test("--match identity turns a reordered record array into no changes at all")
    func identityMatching() throws {
        let a = FileManager.default.temporaryDirectory.appendingPathComponent("cli-rec-a.json")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("cli-rec-b.json")
        try #"[{"id":1,"v":"a"},{"id":2,"v":"b"}]"#.write(to: a, atomically: true, encoding: .utf8)
        try #"[{"id":2,"v":"b"},{"id":1,"v":"a"}]"#.write(to: b, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }

        #expect(run(["diff", a.path, b.path, "--match", "identity:id"]).code == .ok)
        #expect(run(["diff", a.path, b.path, "--match", "index"]).code == .findings)
        #expect(run(["diff", a.path, b.path, "--match", "sideways"]).code == .usage)
    }
}

@Suite("CLI · shell contract")
struct CLIShellContractTests {

    @Test("exit codes distinguish findings from misuse — CI reads these")
    func exitCodes() throws {
        #expect(ExitCode.ok.rawValue == 0)
        #expect(ExitCode.findings.rawValue == 1)
        #expect(ExitCode.usage.rawValue == 2)
        #expect(run(["parse", fixturePath]).code == .ok)
        #expect(try runOn("{", ["parse"]).code == .findings)
        #expect(run(["parse"]).code == .usage, "no file argument")
        #expect(run([]).code == .usage, "no command")
        #expect(run(["frobnicate"]).code == .usage)
    }

    @Test("help and version succeed and name every subcommand")
    func helpAndVersion() {
        let help = run(["--help"])
        #expect(help.code == .ok)
        for command in ["parse", "format", "stats", "diff"] {
            #expect(help.out.contains(command), "help omits \(command)")
        }
        #expect(run(["--version"]).out == JSONKit.version)
    }

    @Test("byte sizes render as the design's {size} placeholder does")
    func byteSizes() {
        #expect(Output.byteSize(512) == "512 B")
        #expect(Output.byteSize(3771) == "3.7 KB")
        #expect(Output.byteSize(1024 * 1024 * 3) == "3.0 MB")
    }
}
