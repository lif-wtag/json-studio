// jsonkit-bench — measures the build guide §5 budgets and fails when one is missed, so a
// regression is a build failure rather than a note.
//
//   swift run -c release --package-path Packages/JSONKit jsonkit-bench
//
// Release is not optional: see BenchmarkRunner.isDebugBuild.

import Foundation
import JSONKitBenchmarks

let arguments = Array(CommandLine.arguments.dropFirst())

func value(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    jsonkit-bench — build guide §5 budgets

    usage:
      swift run -c release --package-path Packages/JSONKit jsonkit-bench [options]

    options:
      --fixture <path>    sample payload (default Design/sample-payload.json)
      --baseline <path>   compare against, and with --record write to,
                          this file (default .benchmark-baseline.json)
      --record            overwrite the baseline with this run
      --allow-debug       measure anyway in a debug build (figures will be meaningless)

    exit codes:
      0  every budget met
      1  a budget was missed, or a benchmark regressed against the baseline
      2  the fixture could not be read, or the build is debug
    """)
    exit(0)
}

if BenchmarkRunner.isDebugBuild && !arguments.contains("--allow-debug") {
    // A debug build is roughly an order of magnitude slower, so every budget would "fail".
    // Printing a wall of red would teach its reader to ignore the report.
    FileHandle.standardError.write(Data("""
        jsonkit-bench: this is a DEBUG build — the figures would be meaningless and every budget \
        would miss.
          Run:  swift run -c release --package-path Packages/JSONKit jsonkit-bench
          (Stack-depth checks are the opposite: those belong in debug — ADR-01 Amendment 1a.)

        """.utf8))
    exit(2)
}

let fixturePath = value("--fixture") ?? "Design/sample-payload.json"
guard let fixtures = BenchmarkFixtures(samplePayloadPath: fixturePath) else {
    FileHandle.standardError.write(Data("""
        jsonkit-bench: cannot read \(fixturePath)
          Run from the repository root, or pass --fixture <path>.

        """.utf8))
    exit(2)
}

let baselinePath = value("--baseline") ?? ".benchmark-baseline.json"
let baseline: [BenchmarkResult] = {
    guard let data = FileManager.default.contents(atPath: baselinePath),
          let decoded = try? JSONDecoder().decode([BenchmarkResult].self, from: data)
    else { return [] }
    return decoded
}()

print("jsonkit-bench — best of N after \(BenchmarkRunner.warmups) warmups, release build")
print("fixture: \(fixturePath)")
if baseline.isEmpty {
    print("baseline: none recorded (\(baselinePath)) — run with --record to create one")
} else {
    print("baseline: \(baselinePath)")
}
print("")

let benchmarks = BenchmarkSuite.all(fixtures)
guard !benchmarks.isEmpty else {
    FileHandle.standardError.write(Data("jsonkit-bench: fixture did not parse\n".utf8))
    exit(2)
}

let results = benchmarks.map {
    BenchmarkRunner.run($0, iterations: BenchmarkSuite.iterations(for: $0))
}
let report = BenchmarkReport(results: results, baseline: baseline)
print(report.render())

if arguments.contains("--record") {
    if let data = try? JSONEncoder().encode(results) {
        try? data.write(to: URL(fileURLWithPath: baselinePath))
        print("\nBaseline written to \(baselinePath)")
    }
}

exit(report.allPassed && report.regressions.isEmpty ? 0 : 1)
