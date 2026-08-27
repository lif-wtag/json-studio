import SwiftUI

/// Application entry point.
///
/// **`DocumentGroup` owns document management** (ADR-03), and the list of what that buys is the
/// reason: window-per-document, system window tabs, Open Recent, autosave, version browsing,
/// dirty-state tracking, close confirmation, and external-change detection. A custom documents
/// sidebar would reimplement all of it, worse — so there isn't one, and the window is two columns.
@main
struct JSONStudioApp: App {
    /// SH-06. Applied to every scene, so the Settings window matches the documents rather than
    /// following the system while they don't.
    @AppStorage(Preferences.appearance) private var appearance: AppearancePreference = .system

    var body: some Scene {
        DocumentGroup(newDocument: { JSONDocument() }) { file in
            RootWindowView(document: file.document)
                .frame(
                    minWidth: Tokens.Layout.windowMinWidth,
                    minHeight: Tokens.Layout.windowMinHeight
                )
                .preferredColorScheme(appearance.colorScheme)
        }
        // The menu bar (SH-02/SH-03) is deliberately NOT here yet. It was built in Task 17 and
        // taken back out: `.commands { … }` made the hosted unit-test bundle hang, with every
        // main-actor test left unscheduled while the app's main thread sat idle. The feature is
        // fine; the interaction with the test host is not understood, and shipping a menu bar
        // that cannot be tested is worse than shipping none. It is its own task now.

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
