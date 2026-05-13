import SwiftUI

struct RootView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                onSettings: openPreferences,
                onFullscreen: toggleFullscreen
            )

            WorkspaceView()
                .environmentObject(preferences)
        }
        .background(DesignTokens.Palette.bgApp.ignoresSafeArea())
        .frame(minWidth: 1024, minHeight: 640)
    }

    private func openPreferences() {
        #if os(macOS)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        #endif
    }

    private func toggleFullscreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
    }
}
