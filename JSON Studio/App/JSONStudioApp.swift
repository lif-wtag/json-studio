import SwiftUI

/// Application entry point.
///
/// **`DocumentGroup` owns document management** (ADR-03), and the list of what that buys is the
/// reason: window-per-document, system window tabs, Open Recent, autosave, version browsing,
/// dirty-state tracking, close confirmation, and external-change detection. A custom documents
/// sidebar would reimplement all of it, worse — so there isn't one, and the window is two columns.
@main
struct JSONStudioApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { JSONDocument() }) { file in
            RootWindowView(document: file.document)
                .frame(
                    minWidth: Tokens.Layout.windowMinWidth,
                    minHeight: Tokens.Layout.windowMinHeight
                )
        }
        // Task 17 adds `.commands { … }` — the full native menu bar, where every shortcut is
        // defined rather than in ad-hoc key handlers.

        Settings {
            SettingsView()
        }
    }
}
