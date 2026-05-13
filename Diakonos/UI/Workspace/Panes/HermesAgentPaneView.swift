import SwiftUI
import AppKit
import SwiftTerm

/// Hermes Agent Chat pane.
///
/// `hermes` is not pre-installed in the cua image. v1 stand-in: spawn a login bash
/// inside the sandbox under HERMES_AGENT=1 with the pane header tinted Hermes orange
/// and a warm-orange terminal foreground. v0.2 will detect a host-installed hermes
/// and use it when available.
struct HermesAgentPaneView: NSViewRepresentable {
    let containerName: String
    var onTitleChange: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onTitleChange: onTitleChange) }

    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false

        let term = LocalProcessTerminalView(frame: .zero)
        term.translatesAutoresizingMaskIntoConstraints = false
        term.processDelegate = context.coordinator
        context.coordinator.term = term

        term.nativeBackgroundColor = NSColor(srgbRed: 0x1A/255.0, green: 0x12/255.0, blue: 0x08/255.0, alpha: 1.0)
        term.nativeForegroundColor = NSColor(srgbRed: 0xFB/255.0, green: 0xBF/255.0, blue: 0x24/255.0, alpha: 1.0)

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
        guard let term = context.coordinator.term else { return }
        if context.coordinator.lastSpawnKey != containerName {
            term.terminate()
            spawn(into: term)
        }
    }

    private func spawn(into term: LocalProcessTerminalView) {
        guard let docker = CUASandboxManager.dockerPath else { return }
        // -e injects an env var the user-installed hermes (if present) can detect.
        // v1 fallback uses login bash inside the same sandbox.
        let args = ["exec", "-it",
                    "-e", "HERMES_AGENT=1",
                    "-e", "PS1=hermes \\$ ",
                    containerName,
                    "/bin/bash", "--login"]
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
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) { onTitleChange(title) }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { }
        func processTerminated(source: TerminalView, exitCode: Int32?) { }
    }
}
