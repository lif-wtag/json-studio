// The executable is a shim. Everything it does lives in `JSONStudioCLI`, which a test target can
// import — an executable target cannot be. CI depends on this CLI (ADR-05), so it needs tests.

import Foundation
import JSONStudioCLI

var output = CommandOutput()
let code = Driver.run(Array(CommandLine.arguments.dropFirst()), into: &output)
output.flush()
exit(code.rawValue)
