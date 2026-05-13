import SwiftUI

struct RootView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                onSettings: { openSettings() },
                onFullscreen: toggleFullscreen
            )

            WorkspaceView()
                .environmentObject(preferences)
        }
        .background(DesignTokens.Palette.bgApp.ignoresSafeArea())
        .frame(minWidth: 1024, minHeight: 640)
    }

    private func toggleFullscreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
    }
}
