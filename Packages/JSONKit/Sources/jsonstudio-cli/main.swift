// jsonstudio-cli — exercises JSONKit with no UI, so the domain is runnable in CI and by hand
// before any app exists (ADR-05).
//
//   swift run --package-path Packages/JSONKit jsonstudio-cli parse  <file>
//   swift run --package-path Packages/JSONKit jsonstudio-cli format <file>
//   swift run --package-path Packages/JSONKit jsonstudio-cli stats  <file>
//   swift run --package-path Packages/JSONKit jsonstudio-cli diff    <a> <b>
//
// Phase 2 wires these subcommands to the real engine. For now the skeleton parses arguments
// and reports that the commands are not yet implemented.

import Foundation
import JSONKit

func usage() {
    print("""
    jsonstudio-cli \(JSONKit.version)
    usage:
      jsonstudio-cli parse  <file>
      jsonstudio-cli format <file>
      jsonstudio-cli stats  <file>
      jsonstudio-cli diff   <file-a> <file-b>
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    usage()
    exit(EXIT_FAILURE)
}

switch command {
case "parse", "format", "stats", "diff":
    FileHandle.standardError.write(Data("\(command): not yet implemented (Phase 2)\n".utf8))
    exit(EXIT_FAILURE)
case "-h", "--help", "help":
    usage()
default:
    FileHandle.standardError.write(Data("unknown command: \(command)\n".utf8))
    usage()
    exit(EXIT_FAILURE)
}
