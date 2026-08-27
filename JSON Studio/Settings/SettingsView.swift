import JSONKit
import SwiftUI

/// Settings window (SH-10). General / Editor / Formatting / Appearance, backed by `@AppStorage`.
///
/// **Every control here is wired to something that works today.** A settings window full of
/// switches that do nothing is worse than a smaller one, so a preference that belongs to a later
/// task is not drawn at all rather than drawn dead.
///
/// Task 16b reconciled this against `Design/screens/Settings.dc.html`: the font-size control is a
/// stepper over the artboard's 10–18, not a slider over an invented 9–24, and **indentation lives
/// in the Editor pane**, where the design puts it.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gear") }
            EditorPane().tabItem { Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right") }
            FormattingPane().tabItem { Label("Formatting", systemImage: "text.alignleft") }
            AppearancePane().tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
        }
        .frame(width: 460)
        .scenePadding()
    }
}

private struct GeneralPane: View {
    @AppStorage(Preferences.showInspectorInNewWindows)
    private var showInspector = Preferences.defaultShowInspector

    var body: some View {
        Form {
            Toggle("Show the inspector in new windows", isOn: $showInspector)
            Text("Closing the inspector in one window leaves the others alone; this only sets "
                 + "what a newly opened document starts with.")
                .font(Tokens.Typography.uiSecondary)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct EditorPane: View {
    @AppStorage(Preferences.editorFontSize)
    private var fontSize = Preferences.defaultEditorFontSize
    @AppStorage(Preferences.indent) private var indent: IndentPreference = .twoSpaces

    var body: some View {
        Form {
            // A stepper with the range printed beside it, as the artboard draws it. Task 17
            // shipped a slider over an invented 9–24; both were wrong.
            LabeledContent("Font size") {
                HStack(spacing: Tokens.Spacing.s) {
                    Stepper(value: $fontSize, in: Preferences.editorFontSizeRange, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .font(Tokens.Typography.statusBarFigure)
                    }
                    .fixedSize()
                    Text("SF Mono · \(Int(Preferences.editorFontSizeRange.lowerBound))–"
                         + "\(Int(Preferences.editorFontSizeRange.upperBound))")
                        .font(Tokens.Typography.uiSecondary)
                        .foregroundStyle(.secondary)
                }
            }

            // **Indentation lives here, not in Formatting** — the artboard puts it in the Editor
            // pane, and it governs typing (auto-indent) as much as it governs Format's output.
            // The storage key is unchanged, so nobody's existing preference resets.
            Picker("Indentation", selection: $indent) {
                ForEach(IndentPreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            // The artboard also draws an "Editing" block — close brackets, auto-indent, highlight
            // the current line, highlight matching brackets, wrap, invisibles — and a "Validation"
            // debounce. Every one is a preference on a feature that does not exist yet: Tasks 19,
            // 21 and 23, and two are P4. They land with their features rather than as switches
            // that do nothing, which is the rule the rest of this window follows.
        }
        .formStyle(.grouped)
    }
}

private struct FormattingPane: View {
    @AppStorage(Preferences.widthAwareFormatting) private var widthAware = Preferences.defaultWidthAware
    @AppStorage(Preferences.printWidth) private var printWidth = Preferences.defaultPrintWidth
    @AppStorage(Preferences.trailingNewline) private var trailingNewline = Preferences.defaultTrailingNewline

    var body: some View {
        Form {
            // FM-03: width-awareness is a preference on the one Format command, not a second verb.
            // A "Beautify" pill was proposed on 2026-08-26 and rejected — it means the same thing
            // to a developer as Format.
            Toggle("Keep short objects and arrays on one line", isOn: $widthAware)

            LabeledContent("Line width") {
                Stepper(value: $printWidth, in: Preferences.printWidthRange) {
                    Text("\(printWidth) columns")
                        .font(Tokens.Typography.statusBarFigure)
                }
                .fixedSize()
            }
            .disabled(!widthAware)

            Toggle("End the file with a newline", isOn: $trailingNewline)

            Text("Turning the first option off gives strictly uniform output — every object and "
                 + "array broken, one value per line, which diffs cleanly by line. Indentation is "
                 + "in the Editor pane.")
                .font(Tokens.Typography.uiSecondary)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePane: View {
    @AppStorage(Preferences.appearance) private var appearance: AppearancePreference = .system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("The syntax palette is authored independently for light and dark — dark is not "
                 + "an inversion — so both were measured against their own editor ground.")
                .font(Tokens.Typography.uiSecondary)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
