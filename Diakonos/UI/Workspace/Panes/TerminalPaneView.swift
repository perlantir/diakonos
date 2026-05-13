import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI host for `SwiftTerm.LocalProcessTerminalView`. Spawns `docker exec -it`
/// against the cuabot Docker container so the user gets a real PTY into the sandbox.
struct TerminalPaneView: NSViewRepresentable {
    let containerName: String
    /// Executable launched inside the container — `/bin/bash` for the Terminal pane,
    /// `/home/user/.local/bin/claude` for the Claude Code pane, etc.
    var commandInContainer: String = "/bin/bash"
    /// Optional title-bar feedback closure.
    var onTitleChange: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTitleChange: onTitleChange)
    }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false

        let term = LocalProcessTerminalView(frame: .zero)
        term.translatesAutoresizingMaskIntoConstraints = false
        term.processDelegate = context.coordinator
        context.coordinator.term = term

        // Theme — match the design's terminal background tone.
        term.nativeBackgroundColor = NSColor(srgbRed: 0x0B/255.0, green: 0x12/255.0, blue: 0x20/255.0, alpha: 1.0)
        term.nativeForegroundColor = NSColor.white

        host.addSubview(term)
        NSLayoutConstraint.activate([
            term.topAnchor.constraint(equalTo: host.topAnchor),
            term.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            term.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            term.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])

        spawn(into: term)
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Container name / command can change if Nick restarts a sandbox. Restart
        // process when the configuration changes.
        guard let term = context.coordinator.term else { return }
        let key = "\(containerName)|\(commandInContainer)"
        if context.coordinator.lastSpawnKey != key {
            term.terminate()
            spawn(into: term)
        }
    }

    private func spawn(into term: LocalProcessTerminalView) {
        guard let docker = CUASandboxManager.dockerPath else {
            return
        }
        let args = ["exec", "-it", containerName, commandInContainer]
        term.startProcess(
            executable: docker.path,
            args: args,
            environment: nil,
            execName: "docker",
            currentDirectory: nil
        )
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        weak var term: LocalProcessTerminalView?
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
