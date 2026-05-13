import SwiftUI

struct WorkspaceToolbar: View {
    @Binding var agentMode: AgentMode
    let sandboxState: SandboxState
    var onSettings: () -> Void = {}
    var onFullscreen: () -> Void = {}

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s3) {
            WorkspaceDropdown(title: "Diakonos")

            Spacer()

            StatusIndicator(state: sandboxState)

            SegmentedToggle(
                selection: $agentMode,
                options: AgentMode.allCases,
                label: { $0.label }
            )

            HStack(spacing: 2) {
                IconButton(systemImage: "gearshape", action: onSettings)
                IconButton(systemImage: "arrow.up.left.and.arrow.down.right", action: onFullscreen)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s5)
        .padding(.vertical, DesignTokens.Spacing.s3)
        .frame(height: 56)
        .background(
            DesignTokens.Palette.bgApp
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DesignTokens.Palette.borderSoft)
                        .frame(height: 1)
                }
        )
    }
}
