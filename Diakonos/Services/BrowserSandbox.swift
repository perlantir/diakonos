import Foundation
import SwiftUI

/// Slim, Browser-pane-local replacement for v1's CUASandboxManager. Owns the
/// lifecycle of the cua sandbox *only* because the Browser pane needs it for
/// sandboxed Chromium streaming. Other v1.1 panes are pure native and don't
/// touch this.
///
/// Lifecycle policy:
///   1. Probe `GET http://localhost:7842/status`. If a server's up and ready,
///      adopt it. If up but not ready, wait.
///   2. If not up at all, try `npx cuabot --serve 7842` in a child process.
///   3. If `npx` is missing, surface a permanent `.error` with guidance.
///
/// Browser pane consumes `@Published var state`, `xpraURL`, and uses
/// `navigate(to:)` to drive Chromium inside the sandbox.
@MainActor
final class BrowserSandbox: ObservableObject {

    @Published private(set) var state: SandboxState = .stopped
    @Published private(set) var statusMessage: String = ""

    private let port: Int = 7842
    private let containerPort: Int = 10000
    private var process: Process?
    private var pollingTask: Task<Void, Never>?

    var xpraURL: URL {
        URL(string: "http://localhost:\(containerPort)/")!
    }

    private var baseURL: URL {
        URL(string: "http://localhost:\(port)")!
    }

    // MARK: - Lifecycle

    func start() {
        guard pollingTask == nil else { return }
        state = .initializing
        statusMessage = "Checking for cuabot…"
        pollingTask = Task { [weak self] in await self?.runLifecycle() }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        process?.terminate()
        process = nil
        state = .stopped
        statusMessage = "Stopped"
    }

    // MARK: - Navigation

    /// Asks Chromium-in-sandbox to navigate. If no Chromium is running yet,
    /// this also launches it on the Xpra display.
    func navigate(to urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized: String
        if trimmed.contains("://") {
            normalized = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            normalized = "https://\(trimmed)"
        } else {
            let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            normalized = "https://duckduckgo.com/?q=\(q)"
        }

        // Escape for shell single-quote nesting.
        let escapedURL = normalized.replacingOccurrences(of: "'", with: "'\\''")
        // Detach: if chromium's already running, this opens a new tab in the
        // existing instance via Chromium's own remote-debugging. If nothing
        // is running, it starts chromium and opens the URL.
        let cmd = "DISPLAY=:100 setsid chromium --no-sandbox --no-first-run --no-default-browser-check --disable-translate '\(escapedURL)' > /tmp/diakonos-chromium.log 2>&1 &"
        await postBash(cmd)
    }

    /// Reload the current Chromium tab via xdotool keystroke injection (Cmd+R / F5).
    func reloadCurrent() async {
        await postBash("DISPLAY=:100 xdotool key --clearmodifiers F5 2>/dev/null || true")
    }

    func goBack() async {
        await postBash("DISPLAY=:100 xdotool key --clearmodifiers alt+Left 2>/dev/null || true")
    }

    func goForward() async {
        await postBash("DISPLAY=:100 xdotool key --clearmodifiers alt+Right 2>/dev/null || true")
    }

    // MARK: - Internals

    private func runLifecycle() async {
        if let status = await fetchStatus() {
            apply(status: status)
            if status.ready { return await pollContinuously() }
            return await waitForReady()
        }

        guard let npx = BrowserSandbox.npxPath else {
            state = .error
            statusMessage = "npx not found. Install Node.js + cuabot (see README) to enable the Browser pane."
            return
        }

        let p = Process()
        p.executableURL = npx
        p.arguments = ["cuabot", "--serve", String(port)]
        p.environment = ProcessInfo.processInfo.environment
        p.standardOutput = Pipe()
        p.standardError = Pipe()

        do {
            try p.run()
            process = p
            statusMessage = "Starting cuabot…"
        } catch {
            state = .error
            statusMessage = "Failed to launch cuabot: \(error.localizedDescription)"
            return
        }

        await waitForReady()
    }

    private func waitForReady(maxAttempts: Int = 120) async {
        for _ in 0..<maxAttempts {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let status = await fetchStatus() else { continue }
            apply(status: status)
            if status.ready { break }
        }
        await pollContinuously()
    }

    private func pollContinuously() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let status = await fetchStatus() else {
                state = .warning
                statusMessage = "cuabot unreachable"
                continue
            }
            apply(status: status)
        }
    }

    private struct StatusPayload: Decodable, Sendable {
        let ok: Bool
        let ready: Bool
        let container: String?
        let containerPort: Int?
    }

    private func fetchStatus() async -> StatusPayload? {
        var req = URLRequest(url: baseURL.appendingPathComponent("status"))
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(StatusPayload.self, from: data)
    }

    private func apply(status: StatusPayload) {
        if status.ready {
            state = .running
            statusMessage = "Sandboxed Chromium ready"
        } else {
            state = .initializing
            statusMessage = "cuabot booting…"
        }
    }

    private func postBash(_ command: String) async {
        guard state == .running else { return }
        var req = URLRequest(url: baseURL.appendingPathComponent("bash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["command": command])
        _ = try? await URLSession.shared.data(for: req)
    }

    private static let npxPath: URL? = {
        for c in ["/opt/homebrew/bin/npx", "/usr/local/bin/npx", "/usr/bin/npx"] {
            if FileManager.default.isExecutableFile(atPath: c) {
                return URL(fileURLWithPath: c)
            }
        }
        return nil
    }()
}
