import Foundation
import SwiftUI
import Testing
@testable import JSON_Studio
import JSONKit

// Task 17. Preferences are the one place where a typo is silent — a misspelled `@AppStorage` key
// reads the default and nothing complains — and where the app can quietly disagree with the
// domain about what "format" means. Both are asserted here.

@Suite("Preferences")
struct PreferencesTests {

    // MARK: - The domain pin

    @Test("the shipped defaults are the domain's own, not a second opinion")
    func defaultsMatchTheDomain() {
        // If `FormatOptions.pretty` ever changes, this fails rather than leaving the app
        // formatting differently from the CLI and the benchmarks.
        #expect(FormattingPreferences().formatOptions == FormatOptions.pretty)
        #expect(Preferences.defaultPrintWidth == 100)
        #expect(Preferences.defaultEditorFontSize == Double(Tokens.Typography.editorBodySize))
    }

    @Test("turning width-awareness off gives the domain's uniform preset exactly")
    func widthAwareOffIsUniform() {
        var preferences = FormattingPreferences()
        preferences.widthAware = false
        #expect(preferences.formatOptions == FormatOptions.uniform)
        // The stored width survives being switched off, so toggling back does not lose it.
        #expect(preferences.printWidth == Preferences.defaultPrintWidth)
    }

    @Test("minify ignores indent and width but keeps the user's trailing newline")
    func minifyOptions() {
        var preferences = FormattingPreferences(indent: .tabs, widthAware: true, printWidth: 60)
        preferences.trailingNewline = true

        let options = preferences.minifyOptions
        #expect(options.compact)
        #expect(options.trailingNewline)
        #expect(FormattingPreferences().minifyOptions == FormatOptions.minified)
    }

    @Test("compare has no format options — it is not a formatting verb")
    func compareHasNoOptions() {
        #expect(FormattingPreferences().options(for: .compare) == nil)
        #expect(FormattingPreferences().options(for: .format) != nil)
        #expect(FormattingPreferences().options(for: .minify) != nil)
    }

    // MARK: - Indent

    @Test("indent labels come from the domain, so the status bar and the pane cannot disagree")
    func indentLabels() {
        #expect(IndentPreference.twoSpaces.label == FormatOptions.Indent.spaces(2).label)
        #expect(IndentPreference.fourSpaces.label == FormatOptions.Indent.spaces(4).label)
        #expect(IndentPreference.tabs.label == FormatOptions.Indent.tab.label)
        #expect(IndentPreference.twoSpaces.label == "2 spaces")
        #expect(IndentPreference.tabs.label == "Tabs")
    }

    @Test("indent raw values are stable — changing one silently resets everyone's preference")
    func indentRawValuesAreStable() {
        #expect(IndentPreference.twoSpaces.rawValue == "2")
        #expect(IndentPreference.fourSpaces.rawValue == "4")
        #expect(IndentPreference.tabs.rawValue == "tab")
    }

    // MARK: - Appearance

    @Test("system appearance means follow the system, which is a nil scheme")
    func appearanceMapping() {
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.light.colorScheme == .light)
        #expect(AppearancePreference.dark.colorScheme == .dark)
    }

    // MARK: - Keys

    @Test("every storage key is distinct — two preferences sharing one would overwrite each other")
    func keysAreDistinct() {
        let keys = [
            Preferences.showInspectorInNewWindows, Preferences.editorFontSize,
            Preferences.indent, Preferences.widthAwareFormatting,
            Preferences.printWidth, Preferences.trailingNewline, Preferences.appearance,
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test("the width range keeps the preference meaningful at both ends")
    func printWidthRange() {
        // The artboard is reproduced by any width in [87, 118], so the range has to contain it.
        #expect(Preferences.printWidthRange.contains(87))
        #expect(Preferences.printWidthRange.contains(118))
        #expect(Preferences.printWidthRange.contains(Preferences.defaultPrintWidth))
    }
}

@Suite("Document commands")
struct DocumentCommandTests {

    @Test("no two commands share a shortcut — the menu bar would silently drop one")
    func shortcutsAreUnique() {
        let shortcuts = DocumentCommand.allCases.map {
            "\($0.shortcut.modifiers.rawValue)-\($0.shortcut.key.character)"
        }
        #expect(Set(shortcuts).count == DocumentCommand.allCases.count)
    }

    @Test("the two shortcuts the design specifies are the ones declared")
    func specifiedShortcuts() {
        // `Design/tokens.md` §5 fixes Format at ⌘⇧F and records Minify as ⌥⌘M. Compare's ⌥⌘C was
        // chosen rather than specified — see the run log.
        #expect(DocumentCommand.format.shortcut.key.character == "f")
        #expect(DocumentCommand.format.shortcut.modifiers == [.command, .shift])
        #expect(DocumentCommand.minify.shortcut.key.character == "m")
        #expect(DocumentCommand.minify.shortcut.modifiers == [.command, .option])
    }

    @Test("the menu title is a sentence and the pill title is a word")
    func titles() {
        #expect(DocumentCommand.format.title == "Format")
        #expect(DocumentCommand.format.menuTitle == "Format Document")
        // The menu title is also the undo action name, so it has to read after "Undo ".
        #expect(DocumentCommand.minify.menuTitle == "Minify Document")
    }

    @Test("there are three verbs and there is no fourth")
    func threeVerbs() {
        // A width-aware "Beautify" was proposed on 2026-08-26 and rejected; width-awareness lives
        // on as `FormattingPreferences.widthAware`. Minify stays, against the design's own
        // self-critique. Both decisions are settled — this fails if either is quietly reopened.
        #expect(DocumentCommand.allCases.count == 3)
    }
}
