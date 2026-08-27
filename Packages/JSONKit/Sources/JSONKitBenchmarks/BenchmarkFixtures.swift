import Foundation
import JSONKit

/// Inputs at the sizes build guide §5 names, built **deterministically** so two runs on the same
/// machine are comparable and a regression means the code changed.
///
/// They are built by repeating `Design/sample-payload.json` inside an array rather than by
/// synthesising JSON, because the project contract fixes that one fixture for every test and demo
/// — and because its shape is what makes the numbers mean anything: deep nesting, a 481-character
/// German string, a 32-element numeric array, unicode, nulls, and `9007199254740993`. Synthetic
/// JSON of uniform shape would measure a different program.
public struct BenchmarkFixtures: Sendable {
    public let unit: String

    /// Loads the sample payload. Returns nil rather than synthesising a substitute: a benchmark
    /// measuring input nobody specified is worse than one that does not run.
    public init?(samplePayloadPath: String) {
        guard let text = try? String(contentsOfFile: samplePayloadPath, encoding: .utf8) else {
            return nil
        }
        self.unit = text
    }

    /// A document of at least `bytes`, as an array of whole copies of the fixture.
    public func document(ofAtLeast bytes: Int) -> String {
        var parts: [String] = []
        var total = 0
        while total < bytes {
            parts.append(unit)
            total += unit.utf8.count
        }
        return "[" + parts.joined(separator: ",") + "]"
    }

    /// A second document differing from `document` in one field per copy — the realistic compare
    /// case, and the one that exercises the diff rather than its early-out.
    public func variant(of document: String) -> String {
        document.replacingOccurrences(of: "\"method\": \"GET\"", with: "\"method\": \"PUT\"")
    }

    public static func describe(bytes: Int) -> String {
        bytes >= 1_000_000 ? "\(bytes / 1_000_000) MB" : "\(bytes / 1000) KB"
    }
}
