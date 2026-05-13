import SwiftUI

/// Claude Code pane: SwiftTerm running `claude` inside the cua sandbox.
struct ClaudeCodePaneView: View {
    let containerName: String

    var body: some View {
        TerminalPaneView(
            containerName: containerName,
            commandInContainer: "/home/user/.local/bin/claude"
        )
    }
}
