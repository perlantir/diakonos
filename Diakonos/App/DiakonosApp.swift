import SwiftUI

@main
struct DiakonosApp: App {
    var body: some Scene {
        WindowGroup("Diakonos") {
            RootView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
