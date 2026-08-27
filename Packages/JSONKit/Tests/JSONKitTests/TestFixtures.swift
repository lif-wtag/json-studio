import Foundation
import Testing

// The project contract fixes one fixture for every test, mockup and demo:
// `Design/sample-payload.json`. It is read from the repository rather than copied into the test
// bundle deliberately — a second copy would drift from the one the design screens are drawn
// against, and then two files would both claim to be the sample payload.
//
// Foundation appears here and nowhere in the library: JSONKit itself stays Foundation-free for
// portability (ADR-05), but the tests run on a host that has it.

enum TestFixture {
    /// Repository root, found by walking up from this file rather than from the working
    /// directory, so the tests pass under `swift test`, Xcode and CI alike.
    static let repositoryRoot: URL = {
        // …/Packages/JSONKit/Tests/JSONKitTests/TestFixtures.swift → five components up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static let samplePayloadURL = repositoryRoot.appendingPathComponent("Design/sample-payload.json")
}

/// The sample payload's text. Throws rather than force-unwrapping so a missing fixture reports
/// itself as a failed test instead of a crashed process.
func sampleJSON() throws -> String {
    try String(contentsOf: TestFixture.samplePayloadURL, encoding: .utf8)
}
