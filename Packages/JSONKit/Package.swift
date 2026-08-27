// swift-tools-version: 6.0
import PackageDescription

// Swift 6 language mode = complete strict concurrency checking (ADR-09). Applied everywhere.
let strictConcurrency: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
]

let package = Package(
    name: "JSONKit",
    // Pure Swift, no UI. Platforms are declared for availability only —
    // the package is buildable for iOS/Linux (ADR-05).
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(name: "JSONKit", targets: ["JSONKit"]),
        // CLI lives inside this package so `swift run --package-path Packages/JSONKit
        // jsonstudio-cli` works exactly as documented in the project contract. (§4 sketches it under
        // Tools/; the concrete build command wins — see Tools/README.md.)
        .executable(name: "jsonstudio-cli", targets: ["jsonstudio-cli"]),
    ],
    targets: [
        .target(
            name: "JSONKit",
            swiftSettings: strictConcurrency
        ),
        // The CLI's logic lives in a library target so it can be tested. CI depends on the CLI
        // (ADR-05: it is the only way the domain is exercisable with no UI), and an executable
        // target cannot be imported by a test target — so `jsonstudio-cli` is a one-line shim.
        .target(
            name: "JSONStudioCLI",
            dependencies: ["JSONKit"],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "jsonstudio-cli",
            dependencies: ["JSONStudioCLI"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "JSONKitTests",
            dependencies: ["JSONKit", "JSONStudioCLI"],
            // JSONTestSuite corpus and other fixtures live here (Phase 2).
            // Benchmarks/README.md is documentation, not a resource — exclude it so SwiftPM
            // stops warning about an unhandled file.
            exclude: ["Benchmarks/README.md"],
            resources: [.copy("Fixtures")],
            swiftSettings: strictConcurrency
        ),
    ]
)
