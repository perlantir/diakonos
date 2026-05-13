import SwiftUI
import AppKit

/// Claude Code pane — runs `claude --dangerously-skip-permissions` natively in a
/// user-selected project folder. Folder defaults to `$HOME`; user can change it
/// any time via the header chip; selection persists across launches in UserDefaults.
/// Changing the folder kills + respawns the claude process via the
/// `TerminalPaneView` spawnIdentity update.
struct ClaudeCodePaneView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        TerminalPaneView(
            workingDirectory: preferences.claudeCodeResolvedCwd,
            commandOverride: claudeCommand(),
            spawnIdentity: "claude:\(preferences.claudeCodeResolvedCwd)"
        )
    }

    /// `$SHELL -l -c "cd <cwd> && exec claude --dangerously-skip-permissions"`.
    /// Login shell so PATH and friends populate. `exec` so the shell hands the
    /// PTY to claude instead of becoming an extra hop.
    private func claudeCommand() -> TerminalCommand {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let cwd = preferences.claudeCodeResolvedCwd
        let escapedCwd = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let line = "cd \"\(escapedCwd)\" && exec claude --dangerously-skip-permissions"
        return TerminalCommand(
            executable: shell,
            args: ["-l", "-c", line],
            execName: nil
        )
    }
}

/// Header chip — shows folder name, click opens NSOpenPanel and updates preferences.
struct ClaudeCodeFolderChip: View {
    @ObservedObject var preferences: Preferences
    @State private var hovering = false

    var body: some View {
        Button(action: pickFolder) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .semibold))
                Text(displayName)
                    .font(Typography.text(Typography.Size.xs, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(DesignTokens.Palette.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.s2)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering
                          ? DesignTokens.Palette.bgSurface
                          : DesignTokens.Palette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preferences.claudeCodeResolvedCwd)
    }

    private var displayName: String {
        let url = URL(fileURLWithPath: preferences.claudeCodeResolvedCwd)
        return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose project folder for Claude Code"
        panel.directoryURL = URL(fileURLWithPath: preferences.claudeCodeResolvedCwd, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            preferences.claudeCodeFolderPath = url.path
        }
    }
}
