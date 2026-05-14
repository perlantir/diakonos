import SwiftUI

struct RootView: View {
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.openSettings) private var openSettings
    /// v1.6: lifted from `WorkspaceView` to here so the toolbar can drive
    /// the 4/6 pane-count toggle. Both descendants pick it up via
    /// `.environmentObject(layout)`.
    @StateObject private var layout = WorkspaceLayout()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                onSettings: { openSettings() },
                onFullscreen: toggleFullscreen
            )

            WorkspaceView()
                .environmentObject(preferences)
        }
        .environmentObject(layout)
        .background(DesignTokens.Palette.bgApp.ignoresSafeArea())
        .frame(minWidth: 1024, minHeight: 640)
    }

    private func toggleFullscreen() {
        #if os(macOS)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
    }
}
