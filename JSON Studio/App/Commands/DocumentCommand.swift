import SwiftUI

/// The three toolbar verbs, declared once (SH-01).
///
/// `CLAUDE.md`'s convention is that a command is defined in the menu bar and everything else
/// *references* it. Task 17 builds the menu bar, and this is what it will render from — the
/// toolbar pills below already do. Title, glyph and shortcut therefore exist in one place, so the
/// menu item and the pill cannot disagree, and the Phase 4 palette gets them for free.
///
/// **Three verbs, and there is no fourth.** A width-aware "Beautify" was proposed on 2026-08-26
/// and rejected — it means the same thing to a developer as Format — and width-awareness lives on
/// as `FormatOptions.printWidth`. Minify stays, against the design's own self-critique.
/// New / Open / Save are **not** here: a document app does not spend toolbar width on them.
enum DocumentCommand: String, CaseIterable, Identifiable {
    case format
    case minify
    case compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .format: "Format"
        case .minify: "Minify"
        case .compare: "Compare"
        }
    }

    /// The full sentence for the menu item and the palette row; the pill shows `title`.
    var menuTitle: String {
        switch self {
        case .format: "Format Document"
        case .minify: "Minify Document"
        case .compare: "Compare With…"
        }
    }

    /// SF Symbols standing in for the artboard's Phosphor glyphs: stacked lines of decreasing
    /// length for Format, converging chevrons for Minify, a two-branch diff for Compare.
    var symbol: String {
        switch self {
        case .format: "text.alignleft"
        case .minify: "arrow.right.and.line.vertical.and.arrow.left"
        case .compare: "arrow.triangle.branch"
        }
    }

    var shortcut: KeyboardShortcut {
        switch self {
        case .format: KeyboardShortcut("f", modifiers: [.command, .shift])
        case .minify: KeyboardShortcut("m", modifiers: [.command, .option])
        // Not specified by the design, unlike ⌘⇧F and ⌥⌘M — chosen here so the command has one
        // at all. Task 17 owns the final menu-bar mapping and may change it.
        case .compare: KeyboardShortcut("c", modifiers: [.command, .option])
        }
    }
}
