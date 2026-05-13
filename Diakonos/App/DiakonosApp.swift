import SwiftUI

@main
struct DiakonosApp: App {
    @StateObject private var preferences = Preferences()

    var body: some Scene {
        WindowGroup("Diakonos") {
            RootView()
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(DesignTokens.Palette.accentPrimary)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }

            // Cmd+1..4 focus the four pane positions. The notification's
            // object is the PaneSlotPosition raw value; WorkspaceView listens
            // and uses PaneFocusRegistry to make the underlying NSView the
            // first responder.
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

                Button("Focus Terminal 2") {
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
                .tint(DesignTokens.Palette.accentPrimary)
        }
    }
}
