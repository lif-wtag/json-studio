import JSONKit
import SwiftUI

/// Every `@AppStorage` key the app uses, in one place (SH-10).
///
/// Keys are strings scattered across call sites otherwise, and a typo in one of them is silent —
/// the reader gets the default and nothing complains. Naming them here means the Settings pane
/// that *writes* a preference and the view that *reads* it cannot disagree, and
/// `PreferencesTests` asserts the defaults match the domain's own.
enum Preferences {
    /// Whether a newly opened window shows the inspector. Per-window state after that: closing it
    /// in one document must not close it in the others.
    static let showInspectorInNewWindows = "general.showInspectorInNewWindows"

    static let editorFontSize = "editor.fontSize"

    /// `IndentPreference.storageKey` — named there because the enum owns its raw values.
    static let indent = IndentPreference.storageKey
    /// FM-03. Off means strictly uniform output: every container broken, one value per line.
    static let widthAwareFormatting = "formatting.widthAware"
    static let printWidth = "formatting.printWidth"
    static let trailingNewline = "formatting.trailingNewline"

    static let appearance = "appearance.colorScheme"

    // Defaults, so the Settings pane and every reader start from the same value.
    static let defaultShowInspector = true
    static let defaultEditorFontSize = Double(Tokens.Typography.editorBodySize)
    static let defaultWidthAware = true
    /// The design's artboard fixes this: it inlines lines of 77/78/79 columns and breaks one of
    /// 119, so any width in [87, 118] reproduces it and 100 sits inside.
    static let defaultPrintWidth = 100
    static let defaultTrailingNewline = false

    /// The bounds the stepper enforces. Below ~40 nothing inlines and the preference stops meaning
    /// anything; above ~200 a line stops fitting a pane at the 720pt minimum window.
    static let printWidthRange = 40...200
    static let editorFontSizeRange = 9.0...24.0
}

/// SH-06. Light / dark / system, applied through `.preferredColorScheme`.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` means "follow the system", which is what `preferredColorScheme(nil)` does.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The Formatting pane's four preferences, resolved into the options the Format command runs with.
///
/// A value type read from `@AppStorage` at the call site rather than an observable object, so the
/// menu item, the toolbar pill and the status bar all see the same numbers without a shared
/// mutable box between them.
nonisolated struct FormattingPreferences: Equatable {
    var indent: IndentPreference = .twoSpaces
    var widthAware: Bool = Preferences.defaultWidthAware
    var printWidth: Int = Preferences.defaultPrintWidth
    var trailingNewline: Bool = Preferences.defaultTrailingNewline

    /// What Format runs with. `printWidth: nil` turns width-awareness off entirely — every
    /// container breaks, one value per line, which is `FormatOptions.uniform`.
    var formatOptions: FormatOptions {
        FormatOptions(
            indent: indent.indent,
            printWidth: widthAware ? printWidth : nil,
            trailingNewline: trailingNewline
        )
    }

    /// Minify ignores indent and width by definition; the trailing newline is still the user's.
    var minifyOptions: FormatOptions {
        FormatOptions(compact: true, trailingNewline: trailingNewline)
    }

    func options(for command: DocumentCommand) -> FormatOptions? {
        switch command {
        case .format: formatOptions
        case .minify: minifyOptions
        case .compare: nil
        }
    }

    /// The text `command` produces from `source`, or `nil` if it must be refused.
    ///
    /// The whole rule lives here, in a value type, rather than on the document: it is a pure
    /// function of the source and these preferences, and keeping it pure is what lets it be tested
    /// without an app host and a main actor.
    ///
    /// **Refused against `source`, not against a published status.** The status bar's status lags
    /// the text by a parse, so a document that has just become invalid would still look
    /// formattable — and the parser recovers rather than throwing (ADR-02), so an invalid document
    /// *has* a tree. Formatting it emits valid JSON that silently drops whatever could not be
    /// parsed, which is the worst outcome a formatter has. `DocumentStatus.isFormattable` greys the
    /// pill and the menu item out; this is the check that actually holds.
    func formatted(_ source: String, for command: DocumentCommand) -> String? {
        guard let options = options(for: command) else { return nil }
        let result = Parser().parse(source)
        guard result.errors.isEmpty, result.tree != nil else { return nil }
        // Formatted against the source it was parsed from — the formatter re-emits scalars by
        // slicing their spans, which is what keeps `\u00e9` and `9007199254740993` byte-exact.
        return Formatter(options: options).format(result, source: source)
    }
}
