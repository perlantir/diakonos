import SwiftUI
import AppKit
import SwiftTerm

/// Native macOS terminal pane. Spawns the user's `$SHELL` (or `/bin/zsh` fallback)
/// in `$HOME` via SwiftTerm's `LocalProcessTerminalView`. Real PTY, real $PATH,
/// real filesystem — v1.1 dropped the docker-exec-into-sandbox indirection.
///
/// Focus isolation: each instance is its own `LocalProcessTerminalView` (an NSView)
/// surfaced directly as the representable's NSView. No wrapper. SwiftTerm handles
/// `acceptsFirstResponder` so keystrokes land only on whichever pane the user clicked.
struct TerminalPaneView: NSViewRepresentable {
    /// Optional explicit working directory; defaults to `$HOME`.
    var workingDirectory: String? = nil
    /// Optional explicit shell command override. If nil, runs `$SHELL -l`.
    var commandOverride: TerminalCommand? = nil
    /// Identifier for state-comparison in `updateNSView` so we only respawn when
    /// the inputs actually change (e.g. when the Claude pane's folder changes).
    var spawnIdentity: String = ""

    var onTitleChange: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChange: onTitleChange)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let term = LocalProcessTerminalView(frame: .zero)
        term.translatesAutoresizingMaskIntoConstraints = false
        term.processDelegate = context.coordinator

        term.nativeBackgroundColor = NSColor(srgbRed: 0x0B/255.0,
                                             green: 0x12/255.0,
                                             blue: 0x20/255.0,
                                             alpha: 1.0)
        term.nativeForegroundColor = NSColor(white: 0.95, alpha: 1.0)

        spawn(into: term, coordinator: context.coordinator)
        return term
    }

    func updateNSView(_ term: LocalProcessTerminalView, context: Context) {
        let key = spawnKey()
        guard context.coordinator.lastSpawnKey != key else { return }
        term.terminate()
        spawn(into: term, coordinator: context.coordinator)
    }

    private func spawnKey() -> String {
        let cmd = commandOverride.map { "\($0.executable) \($0.args.joined(separator: "|"))" } ?? "<shell>"
        return "\(workingDirectory ?? "$HOME")|\(cmd)|\(spawnIdentity)"
    }

    private func spawn(into term: LocalProcessTerminalView, coordinator: Coordinator) {
        let cwd = workingDirectory ?? NSHomeDirectory()

        let executable: String
        let args: [String]
        let execName: String?

        if let override = commandOverride {
            executable = override.executable
            args = override.args
            execName = override.execName
        } else {
            executable = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            // Login shell so $PATH and friends populate via the user's shell rc files.
            args = ["-l"]
            execName = nil
        }

        term.startProcess(
            executable: executable,
            args: args,
            environment: nil,
            execName: execName,
            currentDirectory: cwd
        )
        coordinator.lastSpawnKey = spawnKey()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onTitleChange: (String) -> Void
        var lastSpawnKey: String = ""

        init(onTitleChange: @escaping (String) -> Void) {
            self.onTitleChange = onTitleChange
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { }
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            onTitleChange(title)
        }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { }
        func processTerminated(source: TerminalView, exitCode: Int32?) { }
    }
}

/// A custom executable + args + execName triple used when a pane wants to launch
/// something other than `$SHELL -l`. Used by the Claude Code pane.
struct TerminalCommand: Equatable {
    var executable: String
    var args: [String]
    var execName: String?
}
