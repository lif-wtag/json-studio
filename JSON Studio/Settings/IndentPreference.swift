import JSONKit
import SwiftUI

/// The configured indent (FM-03), shown in the status bar (SH-04) and used by Format.
///
/// A separate enum from `FormatOptions.Indent` because `@AppStorage` needs a `RawRepresentable`
/// with a stable raw value, and pinning JSONKit's associated-value enum to a defaults key would
/// make a domain type responsible for a storage format. The label still comes from the domain —
/// `FormatOptions.Indent.label` exists for exactly this line of the status bar.
enum IndentPreference: String, CaseIterable, Sendable, Identifiable {
    case twoSpaces = "2"
    case fourSpaces = "4"
    case tabs = "tab"

    /// The defaults key. Task 17's Formatting pane edits the same one.
    static let storageKey = "formatting.indent"

    var id: String { rawValue }

    var indent: FormatOptions.Indent {
        switch self {
        case .twoSpaces: .spaces(2)
        case .fourSpaces: .spaces(4)
        case .tabs: .tab
        }
    }

    /// "2 spaces", "4 spaces", "Tabs".
    var label: String { indent.label }
}
