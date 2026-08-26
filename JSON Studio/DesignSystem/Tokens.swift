import SwiftUI

/// Design tokens — layout metrics, type scale, spacing, radii, state treatments.
///
/// Authored in Phase 1; `Design/tokens.md` is the specification and wins on any disagreement.
/// Per locked decision #9, literal hex survives ONLY in `SyntaxTheme.swift` — every colour here
/// resolves to an AppKit semantic.
enum Tokens {

    // MARK: - Spacing (8pt grid)

    enum Spacing {
        /// The grid unit. Sizes below are multiples, except `xs`, the single sub-grid step.
        static let unit: CGFloat = 8

        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Layout

    enum Layout {
        /// 72 editor columns + gutter + insets + divider + `inspectorMinWidth`.
        static let windowMinWidth: CGFloat = 880
        /// Toolbar + 28 editor lines + status bar.
        static let windowMinHeight: CGFloat = 560
        static let windowDefaultWidth: CGFloat = 1180
        static let windowDefaultHeight: CGFloat = 760

        /// The width the Phase 3d inspector must stay readable at.
        static let inspectorMinWidth: CGFloat = 240
        static let inspectorIdealWidth: CGFloat = 320
        /// Beyond this the editor drops under 72 columns at minimum window width.
        static let inspectorMaxWidth: CGFloat = 480

        /// 4 digits of `gutterNumber` + marker column + insets.
        static let gutterMinWidth: CGFloat = 44
        /// Added per digit beyond four, so the gutter grows with the document.
        static let gutterDigitStep: CGFloat = 8
        /// Reserved for error markers (3c) and fold arrows (P4).
        static let gutterMarkerColumn: CGFloat = 10

        static let toolbarHeight: CGFloat = 52
        static let statusBarHeight: CGFloat = 24

        static let editorLeadingInset: CGFloat = 12
        static let editorTopInset: CGFloat = 8
        /// Integral by design: a fractional line height drifts against the ruler's rows.
        static let editorLineHeight: CGFloat = 17

        static let dividerWidth: CGFloat = 1
    }

    // MARK: - Radii

    enum Radius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 6
        static let large: CGFloat = 10
        static let palette: CGFloat = 12
    }

    // MARK: - Type

    /// SF Pro Text for UI, SF Mono for editor content — and for any JSON fragment shown outside
    /// the editor. A JSON value never renders in a proportional face.
    enum Typography {
        static let editorBodySize: CGFloat = 12
        static let gutterNumberSize: CGFloat = 11

        /// Editor content. Follows the editor font preference, not Dynamic Type.
        static func editorBody(size: CGFloat = editorBodySize) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        /// Tabular figures are mandatory: digits must not shift as line numbers change width.
        static let gutterNumber = Font.system(
            size: gutterNumberSize, weight: .regular, design: .monospaced
        ).monospacedDigit()

        static let uiBody = Font.system(size: 13, weight: .regular)
        static let uiSecondary = Font.system(size: 11, weight: .regular)
        static let uiSectionHeader = Font.system(size: 11, weight: .semibold)

        static let treeRow = Font.system(size: 12, weight: .regular)
        static let treeValue = Font.system(size: 12, weight: .regular, design: .monospaced)

        /// Tabular figures for counts, size, and cursor position.
        static let statusBar = Font.system(size: 11, weight: .regular).monospacedDigit()

        static let errorTitle = Font.system(size: 13, weight: .semibold)
        static let errorBody = Font.system(size: 12, weight: .regular)
        static let errorExcerpt = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Semantic surfaces

    /// Named so call sites read as intent rather than as an AppKit lookup. No literal hex here.
    enum Surface {
        static let window = Color(nsColor: .windowBackgroundColor)
        static let editor = Color(nsColor: .textBackgroundColor)
        static let control = Color(nsColor: .controlBackgroundColor)
        static let divider = Color(nsColor: .separatorColor)
        static let listSelection = Color(nsColor: .selectedContentBackgroundColor)
    }

    // MARK: - State treatments

    enum State {
        /// Hover applies to list rows only — text does not hover.
        static let rowHoverOpacity: Double = 0.6
        static let disabledOpacity: Double = 0.5

        /// Drag-over target: accent fill plus a border, never fill alone.
        static let dragOverFillOpacity: Double = 0.12
        static let dragOverBorderWidth: CGFloat = 2

        /// Error underline is 2pt wavy; warnings are 1pt dotted, so the two differ in shape
        /// as well as colour.
        static let errorUnderlineWidth: CGFloat = 2
        static let warningUnderlineWidth: CGFloat = 1
    }
}
