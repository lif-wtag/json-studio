import Testing
@testable import JSONKit

// Phase 2 fills this out: TokenizerTests, ParserTests, ParserRecoveryTests, SpanAccuracyTests,
// RoundTripTests (JSONSerialization as oracle), DiffTests, PathTests, and the JSONTestSuite
// conformance corpus under Fixtures/. This smoke test only proves the package links.

@Suite("JSONKit skeleton")
struct JSONKitSkeletonTests {
    @Test("package exposes a version")
    func version() {
        #expect(!JSONKit.version.isEmpty)
    }

    @Test("source span geometry")
    func spanLength() {
        let span = SourceSpan(start: 4, end: 10)
        #expect(span.length == 6)
        #expect(!span.isEmpty)
    }

    @Test("path renders in $.a.b[0] form")
    func pathRendering() {
        let path = JSONPath([.key("a"), .key("b"), .index(0)])
        #expect(path.description == "$.a.b[0]")
    }
}
