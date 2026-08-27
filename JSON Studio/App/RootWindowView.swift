import SwiftUI

/// The two-column main window: editor + inspector, both independently collapsible (ADR-03).
///
/// This is a placeholder layout so the shell is real and runnable. Phase 1b produces the
/// static window that matches the Claude Design export; Phase 3b wires the `NSTextView`
/// editor, Phase 3d the inspector tree, Phase 3c the status bar.
struct RootWindowView: View {
    /// The open document. Task 16 gives the panes real content; for now the window proves the
    /// document actually arrives — its text and detected encoding are shown rather than mocked.
    @ObservedObject var document: JSONDocument

    @State private var showInspector = true

    var body: some View {
        HSplitView {
            EditorPlaceholder(document: document)
            if showInspector {
                InspectorPlaceholder(document: document)
            }
        }
        .frame(
            minWidth: Tokens.Layout.windowMinWidth,
            minHeight: Tokens.Layout.windowMinHeight
        )
        .toolbar {
            // Task 16 builds the real toolbar from the artboard: Format · Minify · Compare
            // pills, the search field, then this toggle. No New/Open/Save — File menu only.
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
            }
        }
    }
}

/// Placeholder until Task 19 wraps `NSTextView`. It shows the document's actual text rather than
/// a caption, so this task's claim — that the document is read, decoded and handed over — is
/// visible rather than asserted.
private struct EditorPlaceholder: View {
    @ObservedObject var document: JSONDocument

    var body: some View {
        ScrollView {
            Text(document.text.isEmpty ? "Empty document" : document.text)
                .font(.system(size: Tokens.Typography.editorBodySize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Editor content is always opaque — never glass (ADR-08).
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Placeholder until Task 25. Reports what the domain makes of the document, which is the other
/// half of proving the link works: this is JSONKit running inside the app for the first time.
private struct InspectorPlaceholder: View {
    @ObservedObject var document: JSONDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text("Inspector — Task 25")
                .font(.headline)
            Text(document.summary)
                .font(Tokens.Typography.uiSecondary)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(Tokens.Spacing.m)
        .frame(
            minWidth: Tokens.Layout.inspectorMinWidth,
            idealWidth: Tokens.Layout.inspectorDefaultWidth,
            maxWidth: Tokens.Layout.inspectorMaxWidth,
            maxHeight: .infinity,
            alignment: .leading
        )
        // The inspector is dense small text; translucency costs legibility (ADR-08).
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    RootWindowView(document: JSONDocument())
}
