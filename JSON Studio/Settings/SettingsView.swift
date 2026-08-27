import JSONKit
import SwiftUI

/// Settings window (SH-10). General / Editor / Formatting / Appearance, backed by `@AppStorage`.
///
/// **Every control here is wired to something that works today.** A settings window full of
/// switches that do nothing is worse than a smaller one, so where a preference belongs to a later
/// task it is not drawn at all rather than drawn dead — word wrap, invisibles and folding are P4
/// and are simply absent.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gear") }
            EditorPane().tabItem { Label("Editor", systemImage: "text.alignleft") }
            FormattingPane().tabItem { Label("Formatting", systemImage: "curlybraces") }
            AppearancePane().tabItem { Label("Appearance", systemImage: "paintpalette") }
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

    var body: some View {
        Form {
            LabeledContent("Font size") {
                HStack(spacing: Tokens.Spacing.s) {
                    Slider(
                        value: $fontSize,
                        in: Preferences.editorFontSizeRange,
                        step: 1
                    )
                    Text("\(Int(fontSize)) pt")
                        .font(Tokens.Typography.statusBarFigure)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Text("SF Mono, at this size. The line-number gutter follows it.")
                .font(Tokens.Typography.uiSecondary)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct FormattingPane: View {
    @AppStorage(Preferences.indent) private var indent: IndentPreference = .twoSpaces
    @AppStorage(Preferences.widthAwareFormatting) private var widthAware = Preferences.defaultWidthAware
    @AppStorage(Preferences.printWidth) private var printWidth = Preferences.defaultPrintWidth
    @AppStorage(Preferences.trailingNewline) private var trailingNewline = Preferences.defaultTrailingNewline

    var body: some View {
        Form {
            Picker("Indentation", selection: $indent) {
                ForEach(IndentPreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            // FM-03: width-awareness is a preference on the one Format command, not a second verb.
            // A "Beautify" pill was proposed on 2026-08-26 and rejected — it means the same thing
            // to a developer as Format.
            Toggle("Keep short objects and arrays on one line", isOn: $widthAware)

            LabeledContent("Line width") {
                Stepper(value: $printWidth, in: Preferences.printWidthRange) {
                    Text("\(printWidth) columns")
                        .font(Tokens.Typography.statusBarFigure)
                }
            }
            .disabled(!widthAware)

            Toggle("End the file with a newline", isOn: $trailingNewline)

            Text("Turning the first option off gives strictly uniform output — every object and "
                 + "array broken, one value per line, which diffs cleanly by line.")
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
