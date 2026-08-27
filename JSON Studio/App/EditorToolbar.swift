import SwiftUI

/// The unified toolbar (SH-01), as the artboard draws it:
/// **Format · Minify · Compare** pills, then the live search field, then the inspector toggle.
///
/// What is deliberately absent is as much of the specification as what is present. There is **no
/// New / Open / Save** — a document app does not spend toolbar width on commands the File menu
/// already owns and `DocumentGroup` already provides — and no fourth verb.
///
/// The document title, its folder, the edited dot and the traffic lights all appear in the
/// artboard because it is drawing a whole window. They are the system's, not ours:
/// `DocumentGroup` supplies the titlebar's proxy icon and subtitle, so rebuilding them here would
/// replace working platform behaviour (drag-out, right-click path menu, version browsing) with a
/// picture of it.
///
/// **Shortcuts are not declared here.** `DocumentCommand` carries them and Task 17's menu bar
/// declares them, once — the convention is that the toolbar *references* a command rather than
/// defining a second one. Until then the tooltip shows the shortcut so it is at least discoverable.
struct EditorToolbar: ToolbarContent {
    let status: DocumentStatus
    @Binding var searchQuery: String
    @Binding var showsInspector: Bool
    let perform: (DocumentCommand) -> Void

    var body: some ToolbarContent {
        // Every item sits at the trailing edge, in this order, as the artboard draws it: the
        // pills, then the search field, then the inspector toggle. The leading edge belongs to
        // the system's traffic lights and document title.
        ToolbarItemGroup(placement: .primaryAction) {
            ForEach(DocumentCommand.allCases) { command in
                Button { perform(command) } label: {
                    Label(command.title, systemImage: command.symbol)
                }
                .labelStyle(.titleAndIcon)
                .disabled(!isEnabled(command))
                .help(helpText(for: command))
            }
        }

        ToolbarItem(placement: .primaryAction) {
            SearchField(query: $searchQuery)
        }

        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $showsInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .toggleStyle(.button)
            .help(showsInspector ? "Hide the inspector" : "Show the inspector")
        }
    }

    /// Format and Minify need a document that parsed cleanly. The parser recovers rather than
    /// throwing (ADR-02), so an invalid document still *has* a tree — formatting it would emit
    /// valid JSON that silently differs from what the developer wrote. The CLI already refuses for
    /// this reason; the button refuses the same way rather than quietly producing a lie.
    private func isEnabled(_ command: DocumentCommand) -> Bool {
        switch command {
        case .format, .minify: status.isFormattable
        case .compare: false     // Task 27 opens the compare window.
        }
    }

    private func helpText(for command: DocumentCommand) -> String {
        switch command {
        case .compare:
            return "Compare with another document — coming in the compare workspace"
        case .format, .minify:
            guard status.isFormattable else {
                return "\(command.menuTitle) — unavailable while the document has errors"
            }
            return "\(command.menuTitle) (\(command.shortcut.displayText))"
        }
    }
}

/// The live search field (SR-01): query and match counter in one control, not the native find bar.
///
/// The counter is Task 22's — it needs the editor's matches to count. The field is real now
/// because the toolbar's proportions depend on it: at the 720pt minimum window it is what decides
/// whether the three pills still fit.
private struct SearchField: View {
    @Binding var query: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs + Tokens.Spacing.xxs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.editorBody())
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .frame(width: Tokens.Layout.searchFieldWidth, height: Tokens.Layout.controlHeight)
        .background(Tokens.Surface.field, in: .rect(cornerRadius: Tokens.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .strokeBorder(
                    isFocused ? Color.accentColor : Tokens.Surface.divider,
                    lineWidth: Tokens.State.selectionRingWidth
                )
        }
        .accessibilityLabel("Search this document")
    }
}

extension KeyboardShortcut {
    /// `⌘⇧F` — for a tooltip, where the system does not draw the shortcut for us.
    var displayText: String {
        var text = ""
        if modifiers.contains(.control) { text += "\u{2303}" }
        if modifiers.contains(.option) { text += "\u{2325}" }
        if modifiers.contains(.shift) { text += "\u{21E7}" }
        if modifiers.contains(.command) { text += "\u{2318}" }
        return text + String(key.character).uppercased()
    }
}
