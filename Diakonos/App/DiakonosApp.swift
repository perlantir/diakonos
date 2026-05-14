import SwiftUI

@main
struct DiakonosApp: App {
    @StateObject private var preferences = Preferences()

    init() {
        XpraSuppressor.suppressOnLaunch()
        // v1.4: bootstrap MCP registration synchronously BEFORE any pane
        // spawns so claude/codex see the server at their startup.
        MCPRegistration.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup("Diakonos") {
            RootView()
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(preferences.accentColor)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }

            // v1.6: Cmd+1..6 broadcast a 1-based index. WorkspaceView
            // resolves the index against the current pane count's reading
            // order (4: TL/TR/BL/BR; 6: TL/TM/TR/BL/BM/BR). Slots 5 and 6
            // are inactive while in 4-pane mode.
            CommandMenu("Pane") {
                paneFocusButton(label: "Focus Pane 1", index: 1, key: "1")
                paneFocusButton(label: "Focus Pane 2", index: 2, key: "2")
                paneFocusButton(label: "Focus Pane 3", index: 3, key: "3")
                paneFocusButton(label: "Focus Pane 4", index: 4, key: "4")
                paneFocusButton(label: "Focus Pane 5 (6-pane only)", index: 5, key: "5")
                paneFocusButton(label: "Focus Pane 6 (6-pane only)", index: 6, key: "6")
            }
        }

        Settings {
            PreferencesWindow(preferences: preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(preferences.accentColor)
        }
    }

    @ViewBuilder
    private func paneFocusButton(label: String, index: Int, key: KeyEquivalent) -> some View {
        Button(label) {
            NotificationCenter.default.post(name: .diakonosFocusIndex, object: index)
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}
