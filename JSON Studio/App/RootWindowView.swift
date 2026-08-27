import JSONKit
import SwiftUI

/// The two-column main window: editor + inspector, both independently collapsible (ADR-03).
///
/// This is the window chrome from `Design/screens/Window.dc.html` — the split, the toolbar and the
/// status bar, all real. The panes themselves are still placeholders: the `NSTextView` editor is
/// Task 19 and the inspector tree is Task 25.
///
/// **No documents sidebar.** `DocumentGroup` owns window-per-document, tabs, Open Recent, autosave,
/// version browsing, dirty state and close confirmation, and a sidebar would reimplement them.
struct RootWindowView: View {
    @ObservedObject var document: JSONDocument

    @AppStorage(IndentPreference.storageKey) private var indent: IndentPreference = .twoSpaces
    @Environment(\.undoManager) private var undoManager

    @State private var showsInspector = true
    @State private var searchQuery = ""
    /// Task 22 publishes the real caret from the text view. Until the editor exists, every
    /// document sits at its start — which is where a caret genuinely is in one nobody has clicked.
    @State private var cursor = CursorPosition()

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                EditorPane(document: document)
                if showsInspector {
                    InspectorPane(status: document.status)
                }
            }
            StatusBarView(status: document.status, cursor: cursor, indent: indent.indent)
        }
        .frame(
            minWidth: showsInspector
                ? Tokens.Layout.windowMinWidth
                : Tokens.Layout.windowMinWidthInspectorCollapsed,
            minHeight: Tokens.Layout.windowMinHeight
        )
        .toolbar {
            EditorToolbar(
                status: document.status,
                searchQuery: $searchQuery,
                showsInspector: $showsInspector,
                perform: { command in
                    document.perform(command, indent: indent.indent, undoManager: undoManager)
                }
            )
        }
        // A document restored from autosave or opened before the view existed still needs its
        // first status; asking again is cheap and idempotent, since a matching result is dropped.
        .task { document.scheduleStatusRefresh() }
    }
}

/// Placeholder until Task 19 wraps `NSTextView` with TextKit 2.
///
/// It shows the document's actual text, so the claim that the file is read, decoded and handed
/// over stays visible rather than asserted. The ground is `SyntaxTheme.editorGround` — the
/// authored colour of ADR-10, not `textBackgroundColor` — so light and dark already match the
/// artboard and Task 19 inherits the right surface.
private struct EditorPane: View {
    @ObservedObject var document: JSONDocument

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(document.text.isEmpty ? "Empty document" : document.text)
                .font(Tokens.Typography.editorBody())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Tokens.Layout.editorTopInset)
                .padding(.leading, Tokens.Layout.editorLeadingInset)
        }
        .frame(minWidth: Tokens.Layout.editorMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        // Editor content is never glass (ADR-08).
        .background(SyntaxTheme.standard.editorGround.color(for: scheme))
    }
}

/// Placeholder until Task 25, which builds the Tree / Info / Statistics tabs, the Structure header
/// and the persistent path bar (IN-15).
///
/// It reports what the domain makes of the document, which keeps the pane honest: these are
/// JSONKit's numbers, measured off the main actor, not a mock.
private struct InspectorPane: View {
    let status: DocumentStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Structure")
                .font(Tokens.Typography.uiSectionHeader)
                .tracking(Tokens.Typography.sectionHeaderTracking)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            if let statistics = status.statistics {
                Grid(alignment: .leading, horizontalSpacing: Tokens.Spacing.m,
                     verticalSpacing: Tokens.Spacing.xs) {
                    row("objects", statistics.objects)
                    row("arrays", statistics.arrays)
                    row("properties", statistics.properties)
                    row("max depth", statistics.maxDepth)
                }
            } else {
                Text("Tree — Task 25")
                    .font(Tokens.Typography.uiSecondary)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Tokens.Spacing.s)
        .frame(
            minWidth: Tokens.Layout.inspectorMinWidth,
            idealWidth: Tokens.Layout.inspectorDefaultWidth,
            maxWidth: Tokens.Layout.inspectorMaxWidth,
            maxHeight: .infinity,
            alignment: .leading
        )
        // Dense small text; translucency costs legibility, so the inspector is never glass (ADR-08).
        .background(Tokens.Surface.control)
    }

    private func row(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
                .font(Tokens.Typography.uiSecondary)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(Tokens.Typography.treeValue)
                .gridColumnAlignment(.trailing)
        }
    }
}

#Preview {
    RootWindowView(document: JSONDocument())
        .frame(width: Tokens.Layout.windowMinWidth, height: Tokens.Layout.windowMinHeight)
}
