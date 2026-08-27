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
/// **Drawn to the artboard, not left to the system** (Task 16b). A plain `Button` in a macOS 26
/// toolbar renders borderless; the design specifies bordered pills. ADR-08's "toolbar gets whatever
/// the system applies" governs *materials* — no glass here — not the shape of a control.
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
        // **One group, drawn as the artboard draws it.** The three pills, a separator, the search
        // field, a separator, the inspector toggle — one right-aligned cluster with the design's
        // own spacing. Separate `ToolbarItem`s would let the system choose the gaps and drop the
        // separators, which is how Task 16 ended up with borderless buttons in an even row.
        ToolbarItemGroup(placement: .primaryAction) {
            ForEach(DocumentCommand.allCases) { command in
                Button { perform(command) } label: {
                    Label(command.title, systemImage: command.symbol)
                }
                .buttonStyle(ToolbarPillStyle())
                .disabled(!isEnabled(command))
                .help(helpText(for: command))
            }

            ToolbarSeparator()

            SearchField(query: $searchQuery)

            ToolbarSeparator()

            Toggle(isOn: $showsInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .toggleStyle(InspectorToggleStyle())
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
