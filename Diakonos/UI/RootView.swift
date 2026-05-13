import SwiftUI

struct RootView: View {
    @State private var agentMode: AgentMode = .manual
    @State private var sandboxState: SandboxState = .initializing

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                agentMode: $agentMode,
                sandboxState: sandboxState,
                onSettings: openPreferences,
                onFullscreen: toggleFullscreen
            )

            WorkspaceView()
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

#Preview {
    RootView()
        .frame(width: 1440, height: 900)
}
