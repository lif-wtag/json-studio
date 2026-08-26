import SwiftUI

/// Design tokens — layout metrics, type scale, spacing, radii, state treatments.
///
/// **Placeholder.** The real values are authored in `Design/tokens.md` (Phase 1) and imported
/// from the Claude Design export (Phase 1b), then dropped in here. Per ADR-09, literal hex
/// survives ONLY in `SyntaxTheme.swift` and the six diff/validation semantics — every colour
/// here must resolve to an AppKit semantic (`separatorColor`, `textBackgroundColor`,
/// `controlBackgroundColor`, `Color.primary`, `.accentColor`, …).
enum Tokens {
    enum Spacing {
        /// 8pt grid.
        static let unit: CGFloat = 8
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 16
    }

    enum Layout {
        static let inspectorMinWidth: CGFloat = 240   // Phase 1: confirm against tokens.md
        static let inspectorIdealWidth: CGFloat = 300
        static let inspectorMaxWidth: CGFloat = 420
        static let windowMinWidth: CGFloat = 720
        static let windowMinHeight: CGFloat = 420
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
    }

    enum Font {
        /// SF Mono for editor content; SF Pro Text for UI (the system default).
        static let editor = SwiftUI.Font.system(.body, design: .monospaced)
    }
}
