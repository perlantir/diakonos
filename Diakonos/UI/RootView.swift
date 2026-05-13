import SwiftUI

struct RootView: View {
    @State private var agentMode: AgentMode = .manual
    @StateObject private var sandbox = CUASandboxManager()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                agentMode: $agentMode,
                sandboxState: sandbox.state,
                onSettings: openPreferences,
                onFullscreen: toggleFullscreen
            )

            WorkspaceView()
                .environmentObject(sandbox)
        }
        .background(DesignTokens.Palette.bgApp.ignoresSafeArea())
        .frame(minWidth: 1024, minHeight: 640)
        .onAppear { sandbox.start() }
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
