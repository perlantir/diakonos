import SwiftUI
import AppKit

/// Codex pane — runs `codex --dangerously-bypass-approvals-and-sandbox` natively
/// in a user-selected project folder.
///
/// Differences from `ClaudeCodePaneView`:
///   - Codex's YOLO flag is `--dangerously-bypass-approvals-and-sandbox`
///     (vs claude's `--dangerously-skip-permissions`).
///   - No auto-trust keystroke injection: with the YOLO flag set, codex does
///     not display a numeric trust prompt.
///   - Persisted folder under `Preferences.codexFolderPath`.
///   - OAuth handled by `codex login` (the CLI manages it on first launch).
struct CodexPaneView: View {
    @ObservedObject var preferences: Preferences
    var focusPosition: PaneSlotPosition? = nil
    var respawnTag: String = ""

    var body: some View {
        TerminalPaneView(
            workingDirectory: preferences.codexResolvedCwd,
            commandOverride: codexCommand(),
            spawnIdentity: "codex:\(preferences.codexResolvedCwd):\(respawnTag)",
            focusPosition: focusPosition,
            onSpawn: { _ in
                MCPRegistration.shared.ensureCodexRegistered()
            }
        )
    }

    private func codexCommand() -> TerminalCommand {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let cwd = preferences.codexResolvedCwd
        let escapedCwd = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let line = "cd \"\(escapedCwd)\" && exec codex --dangerously-bypass-approvals-and-sandbox"
        return TerminalCommand(
            executable: shell,
            args: ["-l", "-c", line],
            execName: nil
        )
    }
}

/// Folder chip for the Codex pane — mirrors ClaudeCodeFolderChip but reads /
/// writes `preferences.codexFolderPath`.
struct CodexFolderChip: View {
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
        .help(preferences.codexResolvedCwd)
    }

    private var displayName: String {
        let url = URL(fileURLWithPath: preferences.codexResolvedCwd)
        return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    }

    private func pickFolder() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose project folder for Codex"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: preferences.codexResolvedCwd,
                                 isDirectory: true)

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    preferences.codexFolderPath = url.path
                }
            }
        } else {
            if panel.runModal() == .OK, let url = panel.url {
                preferences.codexFolderPath = url.path
            }
        }
    }
}
