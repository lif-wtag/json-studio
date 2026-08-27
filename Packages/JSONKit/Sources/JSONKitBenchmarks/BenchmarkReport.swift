import Foundation

/// Renders results, and compares them against the previous run so a regression inside budget is
/// still visible — code that doubles in cost but stays under its limit is exactly the change that
/// slips through a pass/fail gate.
public struct BenchmarkReport: Sendable {
    public let results: [BenchmarkResult]
    public let baseline: [BenchmarkResult]

    public init(results: [BenchmarkResult], baseline: [BenchmarkResult] = []) {
        self.results = results
        self.baseline = baseline
    }

    public var allPassed: Bool { results.allSatisfy(\.passed) }

    /// A run is flagged when it is this much slower than the recorded baseline, even if it still
    /// fits the budget. Below this, ordinary machine noise would cry wolf.
    public static let regressionThreshold = 1.20

    public var regressions: [(BenchmarkResult, previous: Double)] {
        results.compactMap { result in
            guard let previous = baseline.first(where: {
                $0.name == result.name && $0.input == result.input
            }) else { return nil }
            guard result.measured > previous.measured * Self.regressionThreshold else { return nil }
            return (result, previous.measured)
        }
    }

    public func render() -> String {
        let nameWidth = max(20, results.map(\.name.count).max() ?? 0)
        let inputWidth = max(9, results.map(\.input.count).max() ?? 0)
        var lines: [String] = []

        lines.append(pad("operation", nameWidth) + "  " + pad("input", inputWidth)
            + "   measured     budget   headroom")
        lines.append(String(repeating: "─", count: nameWidth + inputWidth + 34))

        for result in results {
            let measured = String(format: "%8.1f ms", result.measured)
            let budget = String(format: "%6.0f ms", result.budget)
            let headroom = String(format: "%+6.0f%%", result.headroom)
            let verdict = result.passed ? "PASS" : "MISS"
            lines.append(pad(result.name, nameWidth) + "  " + pad(result.input, inputWidth)
                + "  " + measured + "  " + budget + "  " + headroom + "  " + verdict)
        }

        lines.append("")
        let missed = results.filter { !$0.passed }
        if missed.isEmpty {
            lines.append("All \(results.count) budgets met.")
        } else {
            lines.append("\(missed.count) of \(results.count) budgets MISSED: "
                + missed.map { "\($0.name) (\($0.input))" }.joined(separator: ", "))
        }

        // Tight headroom is worth naming before it becomes a miss on someone else's machine.
        let tight = results.filter { $0.passed && $0.headroom < 15 }
        if !tight.isEmpty {
            lines.append("Tight: " + tight.map {
                String(format: "%@ (%@) at %.0f%% headroom", $0.name, $0.input, $0.headroom)
            }.joined(separator: ", "))
        }

        for (result, previous) in regressions {
            lines.append(String(
                format: "Regression: %@ (%@) %.1f ms → %.1f ms, %.0f%% slower than the last run",
                result.name, result.input, previous, result.measured,
                (result.measured / previous - 1) * 100
            ))
        }
        return lines.joined(separator: "\n")
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
