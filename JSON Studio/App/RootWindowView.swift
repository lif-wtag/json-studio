import SwiftUI

/// The two-column main window: editor + inspector, both independently collapsible (ADR-03).
///
/// This is a placeholder layout so the shell is real and runnable. Phase 1b produces the
/// static window that matches the Claude Design export; Phase 3b wires the `NSTextView`
/// editor, Phase 3d the inspector tree, Phase 3c the status bar.
struct RootWindowView: View {
    @State private var showInspector = true

    var body: some View {
        HSplitView {
            EditorPlaceholder()
            if showInspector {
                InspectorPlaceholder()
            }
        }
        // Phase 1 supplies the real minimum window size from Design/tokens.md.
        .frame(minWidth: 720, minHeight: 420)
        .toolbar {
            // Phase 3a: New / Open / Save · Format / Minify · Compare · inspector toggle.
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

private struct EditorPlaceholder: View {
    var body: some View {
        Text("Editor — Phase 3b (NSTextView + TextKit 2)")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Editor content is always opaque — never glass (ADR-08).
            .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct InspectorPlaceholder: View {
    var body: some View {
        Text("Inspector — Phase 3d")
            .foregroundStyle(.secondary)
            // Minimum inspector width from the build guide (§3d).
            .frame(minWidth: 240, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

#Preview {
    RootWindowView()
}
