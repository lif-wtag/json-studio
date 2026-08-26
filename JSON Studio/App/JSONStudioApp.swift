import SwiftUI

/// Application entry point.
///
/// Phase 3a replaces this `WindowGroup` with `DocumentGroup` + `JSONDocument`
/// (`ReferenceFileDocument`), so macOS owns document management — window-per-document,
/// system window tabs, Open Recent, autosave, version browsing, dirty state, and close
/// confirmation (ADR-03). There is no documents sidebar; the window is two columns.
@main
struct JSONStudioApp: App {
    var body: some Scene {
        WindowGroup {
            RootWindowView()
        }
        // Phase 3a: .commands { … } — full native menu bar
        // (App / File / Edit / JSON / View / Tools / Window / Help), Tools left sparse.

        Settings {
            SettingsView()
        }
    }
}
