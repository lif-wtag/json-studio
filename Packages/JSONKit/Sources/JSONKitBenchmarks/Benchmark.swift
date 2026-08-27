import Foundation

/// One measured operation and the budget it must stay inside (build guide §5).
public struct Benchmark: Sendable {
    public let name: String
    /// The input's size, for the report — "1 MB", "1 MB × 1 MB".
    public let input: String
    /// Build guide §5, in milliseconds.
    public let budget: Double
    let body: @Sendable () -> Void

    public init(_ name: String, input: String, budget: Double, body: @escaping @Sendable () -> Void) {
        self.name = name
        self.input = input
        self.budget = budget
        self.body = body
    }
}

public struct BenchmarkResult: Sendable, Codable {
    public let name: String
    public let input: String
    public let measured: Double
    public let budget: Double

    public var passed: Bool { measured <= budget }
    /// How much of the budget is unspent. Negative when the budget is missed.
    public var headroom: Double { (budget - measured) / budget * 100 }
}

public enum BenchmarkRunner {

    /// Discarded runs before measuring. The first pass pays for lazy allocation and a cold cache,
    /// and reporting it would overstate every figure — a cold `parse` measured 102 ms against a
    /// 100 ms budget where the warm figure is 67 ms.
    public static let warmups = 2

    /// **Best of N, not mean or median.** A microbenchmark is racing the scheduler, so slow runs
    /// are contamination rather than signal: the minimum is the closest estimate of what the code
    /// actually costs. It also makes a regression unambiguous — the floor moved.
    public static func run(_ benchmark: Benchmark, iterations: Int) -> BenchmarkResult {
        for _ in 0..<warmups { benchmark.body() }
        var best = Double.infinity
        for _ in 0..<max(1, iterations) {
            let start = DispatchTime.now().uptimeNanoseconds
            benchmark.body()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            best = min(best, elapsed)
        }
        return BenchmarkResult(
            name: benchmark.name, input: benchmark.input, measured: best, budget: benchmark.budget
        )
    }

    /// `true` when this build cannot produce meaningful figures.
    ///
    /// A debug build is roughly an order of magnitude slower, so every budget would "fail" and the
    /// report would train its reader to ignore it. Refusing is more useful than a red wall — and
    /// it mirrors the split ADR-01 Amendment 1a established: **measure speed in release, measure
    /// stack depth in debug.**
    public static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
