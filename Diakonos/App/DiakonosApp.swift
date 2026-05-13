import SwiftUI

@main
struct DiakonosApp: App {
    @StateObject private var preferences = Preferences()

    var body: some Scene {
        WindowGroup("Diakonos") {
            RootView()
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            PreferencesWindow(preferences: preferences)
                .preferredColorScheme(preferences.colorScheme)
        }
    }
}
