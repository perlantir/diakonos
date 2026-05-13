import SwiftUI
import AppKit
import SwiftTerm

/// One-line constant — flip to disable Claude Code's auto-trust keystroke
/// injection if the prompt-injection misbehaves on a future claude version.
private let claudeAutoTrustEnabled = true

/// Claude Code pane — runs `claude --dangerously-skip-permissions` natively in a
/// user-selected project folder. Folder defaults to `$HOME`; user can change it
/// any time via the header chip; selection persists across launches in
/// UserDefaults. Changing the folder kills + respawns claude.
///
/// On every spawn, after a 1500 ms delay we inject `1\r` (`'1'` followed by
/// Enter) to auto-accept the "Do you trust this folder?" prompt. If the prompt
/// isn't shown (folder already trusted), the `1` lands harmlessly in the input
/// box — minor UX nit, easy to recover from. Constant above disables.
struct ClaudeCodePaneView: View {
    @ObservedObject var preferences: Preferences
    var focusPosition: PaneSlotPosition? = nil
    var respawnTag: String = ""

    var body: some View {
        TerminalPaneView(
            workingDirectory: preferences.claudeCodeResolvedCwd,
            commandOverride: claudeCommand(),
            spawnIdentity: "claude:\(preferences.claudeCodeResolvedCwd):\(preferences.preferredModel):\(respawnTag)",
            additionalEnvironment: EnvironmentBuilder.aiEnv(preferences: preferences),
            focusPosition: focusPosition,
            onSpawn: { term in
                guard claudeAutoTrustEnabled else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let bytes: [UInt8] = Array("1\r".utf8)
                    term.process.send(data: bytes[...])
                }
            }
        )
    }

    /// `$SHELL -l -c "cd <cwd> && exec claude --dangerously-skip-permissions"`.
    /// Login shell so PATH and friends populate. `exec` so the shell hands the
    /// PTY directly to claude.
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
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose project folder for Claude Code"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: preferences.claudeCodeResolvedCwd,
                                 isDirectory: true)

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    preferences.claudeCodeFolderPath = url.path
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                preferences.claudeCodeFolderPath = url.path
            }
        }
    }
}
