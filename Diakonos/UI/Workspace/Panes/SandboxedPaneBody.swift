import SwiftUI

/// Renders the appropriate body for a pane depending on the shared sandbox's state.
/// While the sandbox is initializing/stopped/errored, shows `InitializingPaneBody`;
/// once ready, shows a `TerminalPaneView` (or pane-specific live content for Phase 3).
struct SandboxedPaneBody<Live: View>: View {
    let kind: PaneKind
    let state: SandboxState
    let containerName: String?
    @ViewBuilder let live: (_ containerName: String) -> Live

    var body: some View {
        ZStack {
            if state == .running, let name = containerName {
                live(name)
            } else {
                InitializingPaneBody(kind: kind)
                    .overlay(alignment: .bottom) {
                        if state == .error {
                            Text("Sandbox error — check cuabot logs.")
                                .font(Typography.text(Typography.Size.xs))
                                .foregroundStyle(DesignTokens.Palette.statusError)
                                .padding(.bottom, DesignTokens.Spacing.s3)
                        }
                    }
            }
        }
    }
}
