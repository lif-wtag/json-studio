import Foundation
import JSONKit

/// The six budgets from build guide §5 that belong to the domain.
///
/// The other three — keystroke to highlight, keystroke to validation, and the 0 ms main-thread
/// block — are properties of the **app**, measured with Instruments in Phase 3. They are not
/// omissions; nothing here can observe them.
public enum BenchmarkSuite {

    /// Builds every benchmark. Parsing the inputs up front means each measurement times one
    /// operation rather than the setup it needed.
    public static func all(_ fixtures: BenchmarkFixtures) -> [Benchmark] {
        let small = fixtures.document(ofAtLeast: 100_000)
        let medium = fixtures.document(ofAtLeast: 1_000_000)
        let large = fixtures.document(ofAtLeast: 10_000_000)
        let variant = fixtures.variant(of: medium)

        let smallSize = BenchmarkFixtures.describe(bytes: small.utf8.count)
        let mediumSize = BenchmarkFixtures.describe(bytes: medium.utf8.count)
        let largeSize = BenchmarkFixtures.describe(bytes: large.utf8.count)

        // Pre-parsed, so format / stats / diff time themselves and not the parse.
        guard let mediumTree = Parser().parse(medium).tree,
              let variantTree = Parser().parse(variant).tree
        else { return [] }

        return [
            Benchmark("tokenize + parse", input: smallSize, budget: 10) {
                _ = Parser().parse(small)
            },
            Benchmark("tokenize + parse", input: mediumSize, budget: 100) {
                _ = Parser().parse(medium)
            },
            Benchmark("tokenize + parse", input: largeSize, budget: 1500) {
                _ = Parser().parse(large)
            },
            Benchmark("format (pretty)", input: mediumSize, budget: 80) {
                _ = Formatter(options: .pretty).format(mediumTree, source: medium)
            },
            Benchmark("structural diff", input: "\(mediumSize) × \(mediumSize)", budget: 500) {
                _ = try? StructuralDiff().diff(mediumTree, variantTree)
            },
            Benchmark("statistics walk", input: mediumSize, budget: 50) {
                _ = try? StatisticsWalker().walk(mediumTree)
            },
        ]
    }

    /// Fewer iterations for the expensive ones: seven runs of a 10 MB parse is 10 s of wall clock
    /// for a figure that three runs already pin down.
    public static func iterations(for benchmark: Benchmark) -> Int {
        benchmark.budget >= 500 ? 3 : 7
    }
}
