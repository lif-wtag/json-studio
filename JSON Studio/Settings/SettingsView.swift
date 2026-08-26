import SwiftUI

/// Settings window (SH-10). Four panes backed by `@AppStorage`. Placeholder tabs for now;
/// Phase 3a fills General / Editor / Formatting / Appearance.
struct SettingsView: View {
    var body: some View {
        TabView {
            Text("General").tabItem { Label("General", systemImage: "gear") }
            Text("Editor").tabItem { Label("Editor", systemImage: "text.alignleft") }
            Text("Formatting").tabItem { Label("Formatting", systemImage: "curlybraces") }
            Text("Appearance").tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 480, height: 320)
    }
}
