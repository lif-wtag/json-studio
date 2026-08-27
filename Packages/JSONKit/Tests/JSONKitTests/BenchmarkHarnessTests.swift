import Foundation
import Synchronization
import Testing
@testable import JSONKit
@testable import JSONKitBenchmarks

// Phase 2, step 10 / Task 14. These test the harness, **not the timings** — this suite runs under
// `swift test`, which builds debug, where every budget would miss by an order of magnitude.
//
// What is worth testing here is the reporting logic, because that is what CI actually depends on:
// a harness that silently failed to notice a missed budget would be worse than no harness.

@Suite("Benchmark harness")
struct BenchmarkHarnessTests {

    private func fixtures() throws -> BenchmarkFixtures {
        try #require(
            BenchmarkFixtures(samplePayloadPath: TestFixture.samplePayloadURL.path),
            "the harness must read the one fixture the contract fixes"
        )
    }

    @Test("the suite covers the six §5 budgets that belong to the domain, at the stated sizes")
    func coversTheBudgets() throws {
        let benchmarks = BenchmarkSuite.all(try fixtures())
        #expect(benchmarks.count == 6)

        // Budgets transcribed from the build guide §5 table — if one drifts, this fails.
        let budgets = Dictionary(
            benchmarks.map { ("\($0.name)|\($0.input)", $0.budget) }, uniquingKeysWith: { a, _ in a }
        )
        #expect(budgets["tokenize + parse|101 KB"] == 10)
        #expect(budgets["tokenize + parse|1 MB"] == 100)
        #expect(budgets["tokenize + parse|10 MB"] == 1500)
        #expect(budgets["format (pretty)|1 MB"] == 80)
        #expect(budgets["structural diff|1 MB × 1 MB"] == 500)
        #expect(budgets["statistics walk|1 MB"] == 50)
    }

    @Test("fixtures are deterministic and hit their sizes, and every one is valid JSON")
    func fixturesAreDeterministic() throws {
        let f = try fixtures()
        let a = f.document(ofAtLeast: 100_000)
        let b = f.document(ofAtLeast: 100_000)
        #expect(a == b, "two runs must measure the same input or a regression means nothing")
        #expect(a.utf8.count >= 100_000)
        #expect(Parser().parse(a).isValid)

        // The variant differs, or the diff benchmark would measure its early-out.
        let variant = f.variant(of: a)
        #expect(variant != a)
        #expect(Parser().parse(variant).isValid)
    }

    @Test("the runner measures and reports against the budget")
    func runnerProducesResults() {
        // A Mutex rather than an @unchecked Sendable box: the benchmark body is @Sendable, and
        // Swift 6 is right to refuse a captured var even though this one never leaves the thread.
        let count = Mutex(0)
        let benchmark = Benchmark("noop", input: "none", budget: 1_000_000) {
            count.withLock { $0 += 1 }
        }
        let result = BenchmarkRunner.run(benchmark, iterations: 3)
        #expect(count.withLock { $0 } == BenchmarkRunner.warmups + 3,
                "warmups run but are not measured")
        #expect(result.measured >= 0)
        #expect(result.passed, "a no-op cannot miss a 1000 s budget")
    }

    @Test("a missed budget is detected and named — the whole point of the harness")
    func detectsMisses() {
        let missed = BenchmarkResult(name: "slow", input: "1 MB", measured: 120, budget: 100)
        let met = BenchmarkResult(name: "fine", input: "1 MB", measured: 50, budget: 100)
        #expect(!missed.passed)
        #expect(met.passed)

        let report = BenchmarkReport(results: [met, missed])
        #expect(!report.allPassed)
        #expect(report.render().contains("MISS"))
        #expect(report.render().contains("1 of 2 budgets MISSED"))
    }

    @Test("tight headroom is called out rather than reported as a clean pass")
    func flagsTightHeadroom() {
        // format (pretty) sits here in reality, which is why the harness says so every run.
        let tight = BenchmarkResult(name: "format (pretty)", input: "1 MB", measured: 76, budget: 80)
        #expect(tight.passed)
        #expect(tight.headroom < 15)
        let report = BenchmarkReport(results: [tight])
        #expect(report.allPassed)
        #expect(report.render().contains("Tight"), "a 5% margin must not read as simply fine")
    }

    @Test("a regression inside budget is still flagged — a pass/fail gate alone would miss it")
    func detectsRegressionsWithinBudget() {
        let before = BenchmarkResult(name: "parse", input: "1 MB", measured: 40, budget: 100)
        // Doubled in cost, still comfortably under budget.
        let after = BenchmarkResult(name: "parse", input: "1 MB", measured: 80, budget: 100)

        let report = BenchmarkReport(results: [after], baseline: [before])
        #expect(report.allPassed, "it does fit the budget")
        #expect(report.regressions.count == 1, "…and it is still a regression")
        #expect(report.render().contains("Regression"))

        // Ordinary noise must not cry wolf.
        let noise = BenchmarkResult(name: "parse", input: "1 MB", measured: 44, budget: 100)
        #expect(BenchmarkReport(results: [noise], baseline: [before]).regressions.isEmpty)
    }

    @Test("results round-trip through the baseline file's encoding")
    func baselineEncoding() throws {
        let results = [BenchmarkResult(name: "parse", input: "1 MB", measured: 66.1, budget: 100)]
        let data = try JSONEncoder().encode(results)
        let decoded = try JSONDecoder().decode([BenchmarkResult].self, from: data)
        #expect(decoded.first?.measured == 66.1)
        #expect(decoded.first?.name == "parse")
    }

    @Test("this build is debug, which is exactly why the timings are not asserted here")
    func debugBuildIsDetected() {
        // If this ever fails, `swift test` has started building release and the guard in
        // jsonkit-bench needs revisiting.
        #expect(BenchmarkRunner.isDebugBuild)
    }
}
