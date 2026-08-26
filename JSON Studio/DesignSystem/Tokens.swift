import SwiftUI

/// Design tokens — layout metrics, type scale, spacing, radii, state treatments.
///
/// Values come from the approved Claude Design project ("JSON Studio — Run 1"), reconciled in
/// `Design/tokens.md`, which is the specification and wins on any disagreement. Per locked
/// decision #9, literal hex survives ONLY in `SyntaxTheme.swift` — the syntax palette, the six
/// semantics, and the editor ground (ADR-10). Every colour here resolves to an AppKit semantic.
enum Tokens {

    // MARK: - Spacing

    /// 8pt base grid, with 4pt for dense rows (tree, palette, status bar).
    enum Spacing {
        static let unit: CGFloat = 8
        static let denseUnit: CGFloat = 4

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
        /// 640 when the inspector is collapsed.
        static let windowMinWidth: CGFloat = 720
        static let windowMinWidthInspectorCollapsed: CGFloat = 640
        static let windowMinHeight: CGFloat = 480
        /// The size every Run 1 artefact is drawn at.
        static let windowDefaultWidth: CGFloat = 1280
        static let windowDefaultHeight: CGFloat = 836

        /// Below this the inspector must collapse rather than squeeze the editor.
        static let editorMinWidth: CGFloat = 420

        static let inspectorDefaultWidth: CGFloat = 280
        /// The floor: below it the tree's value column would have to drop entirely.
        static let inspectorMinWidth: CGFloat = 240
        static let inspectorMaxWidth: CGFloat = 400

        /// The design's documented deviation from a 44pt minimum: the fold caret sits left of a
        /// two-digit number without crowding. Still grows with digit count.
        static let gutterWidth: CGFloat = 48
        static let gutterDigitStep: CGFloat = 8
        static let gutterTrailingInset: CGFloat = 8

        static let toolbarHeight: CGFloat = 52
        static let statusBarHeight: CGFloat = 24
        static let controlHeight: CGFloat = 26
        /// 176, not the design's 208 — Beautify (FM-13) took a pill's width.
        static let searchFieldWidth: CGFloat = 176

        static let editorTopInset: CGFloat = 8
        static let editorLeadingInset: CGFloat = 10
        /// SF Mono 12 × 1.45. Fractional by design — the ruler must use the same value so its
        /// rows stay locked to the text.
        static let editorLineHeight: CGFloat = 17.4

        static let treeRowHeight: CGFloat = 21
        static let treeIndentPerLevel: CGFloat = 13
        static let treeRowBaseInset: CGFloat = 6

        /// Command palette (Phase 4 — SH-14). Metrics recorded now so the design need not be
        /// re-derived later.
        static let paletteWidth: CGFloat = 560
        static let paletteRowHeight: CGFloat = 32
        static let paletteTopOffset: CGFloat = 132

        static let dividerWidth: CGFloat = 1

        /// Row inset for a tree node at the given depth.
        static func treeInset(depth: Int) -> CGFloat {
            treeRowBaseInset + CGFloat(depth) * treeIndentPerLevel
        }
    }

    // MARK: - Radii

    /// The design carries exactly two.
    enum Radius {
        /// Toolbar pills, search field, segmented control, tree rows.
        static let control: CGFloat = 6
        /// Window, command palette, popovers, sheets.
        static let surface: CGFloat = 10
    }

    // MARK: - Type

    /// SF Pro Text for UI, SF Mono for editor content — and for tree keys and values, all
    /// figures in the status bar, and any JSON shown outside the editor.
    enum Typography {
        static let editorBodySize: CGFloat = 12
        static let gutterNumberSize: CGFloat = 11

        /// Follows the editor font preference, not Dynamic Type.
        static func editorBody(size: CGFloat = editorBodySize) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        /// Tabular figures are mandatory: digits must not shift as the gutter widens.
        static let gutterNumber = Font.system(
            size: gutterNumberSize, weight: .regular, design: .monospaced
        ).monospacedDigit()

        static let uiBody = Font.system(size: 13, weight: .regular)
        /// The document title in the toolbar; the design sets it at weight 590.
        static let uiTitle = Font.system(size: 13, weight: .semibold)
        static let uiSecondary = Font.system(size: 11, weight: .regular)
        /// Uppercase, tracked 0.06em at the call site.
        static let uiSectionHeader = Font.system(size: 11, weight: .semibold)

        /// The design sets tree keys and values in mono, not SF Pro.
        static let treeKey = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let treeValue = Font.system(
            size: 11, weight: .regular, design: .monospaced
        ).monospacedDigit()

        static let statusBarLabel = Font.system(size: 11, weight: .regular)
        static let statusBarFigure = Font.system(
            size: 11, weight: .regular, design: .monospaced
        ).monospacedDigit()

        static let paletteQuery = Font.system(size: 15, weight: .regular)
        static let paletteRow = Font.system(size: 13, weight: .regular)
        static let paletteShortcut = Font.system(size: 11, weight: .regular, design: .monospaced)

        static let errorTitle = Font.system(size: 13, weight: .semibold)
        static let errorBody = Font.system(size: 12, weight: .regular)
        static let errorExcerpt = Font.system(size: 12, weight: .regular, design: .monospaced)

        /// Tracking for `uiSectionHeader`, in points at 11pt.
        static let sectionHeaderTracking: CGFloat = 0.66
    }

    // MARK: - Semantic surfaces

    /// Named so call sites read as intent. No literal hex — the editor ground is the one
    /// exception, and it lives in `SyntaxTheme.editorGround` (ADR-10).
    enum Surface {
        static let window = Color(nsColor: .windowBackgroundColor)
        static let control = Color(nsColor: .controlBackgroundColor)
        static let field = Color(nsColor: .textBackgroundColor)
        static let divider = Color(nsColor: .separatorColor)
        static let listSelection = Color(nsColor: .selectedContentBackgroundColor)
    }

    // MARK: - State treatments

    enum State {
        /// Accent fill and border for a selected tree row and the active inspector toggle.
        static let accentFillOpacity: Double = 0.14
        static let accentBorderOpacity: Double = 0.44
        static let selectionRingWidth: CGFloat = 1

        static let disabledOpacity: Double = 0.5

        /// Error underline is 2pt wavy; warnings are 1pt dotted, so the two differ in shape as
        /// well as colour.
        static let errorUnderlineWidth: CGFloat = 2
        static let warningUnderlineWidth: CGFloat = 1

        /// 1px inset ring, not a fill — so it never sits under the bracket glyph's text.
        static let matchedBracketRingWidth: CGFloat = 1

        /// Overlay scroll indicator.
        static let scrollIndicatorWidth: CGFloat = 8
    }

    // MARK: - Glass (ADR-08, Amendment 1)

    /// **Command palette only.** Popovers and sheets use `.popover` / `.sheet` and take the system
    /// material — Liquid Glass on macOS 26, the right vibrancy on 15 — with Reduce Transparency and
    /// Increase Contrast handled for us. These values exist for the one floating surface that has
    /// no system presentation behind it.
    enum Glass {
        static let blurRadius: CGFloat = 28
        static let blurRadiusDark: CGFloat = 30
        static let saturation: Double = 1.8
        static let scrimOpacity: Double = 0.16
        static let scrimOpacityDark: Double = 0.34
        /// Reduce Transparency raises the scrim, since the surface itself goes opaque.
        static let scrimOpacityOpaque: Double = 0.22
        static let scrimOpacityOpaqueDark: Double = 0.5
    }
}
