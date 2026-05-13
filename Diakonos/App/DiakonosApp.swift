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

            CommandMenu("Pane") {
                Button("Focus Terminal") {
                    NotificationCenter.default.post(name: .diakonosFocusSlot,
                                                    object: PaneSlotPosition.topLeft.rawValue)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Focus Claude Code") {
                    NotificationCenter.default.post(name: .diakonosFocusSlot,
                                                    object: PaneSlotPosition.topRight.rawValue)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Focus Bottom-Left Pane") {
                    NotificationCenter.default.post(name: .diakonosFocusSlot,
                                                    object: PaneSlotPosition.bottomLeft.rawValue)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Focus Browser") {
                    NotificationCenter.default.post(name: .diakonosFocusSlot,
                                                    object: PaneSlotPosition.bottomRight.rawValue)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
        }

        Settings {
            PreferencesWindow(preferences: preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(preferences.accentColor)
        }
    }
}
