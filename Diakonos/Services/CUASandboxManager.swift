import Foundation
import SwiftUI

/// Owns the lifecycle of the cua sandbox shared by all Diakonos panes.
///
/// v1 design: one cuabot server (`npx cuabot --serve`) + one Docker container
/// (`cuabot-xpra`) hosts the sandbox. All terminal panes shell into this
/// container via `docker exec`. Browser pane (WKWebView) bypasses the sandbox
/// entirely (D6).
///
/// Phase 2 discovery: cuabot exposes HTTP on port 7842 with /status, /bash,
/// /screenshot, /click, /type, /key. There is no PTY/stream endpoint, so
/// interactive shells use `docker exec -it cuabot-xpra <shell>`.
@MainActor
final class CUASandboxManager: ObservableObject {

    /// User-visible aggregate sandbox state for the toolbar.
    @Published private(set) var state: SandboxState = .stopped

    /// Last status string returned by cuabot (diagnostic only).
    @Published private(set) var lastStatusMessage: String = ""

    /// Name of the underlying Docker container. Determined once the cuabot
    /// server reports ready. v1 expectation: "cuabot-xpra".
    @Published private(set) var containerName: String? = nil

    /// HTTP port cuabot's server is reachable on.
    let serverPort: Int = 7842

    private let supervisor = CUAProcessSupervisor()
    private let client = CUAHTTPClient(port: 7842)
    private var pollingTask: Task<Void, Never>?

    /// Locate `npx`. Without it, cuabot cannot be started.
    private static let npxPath: URL? = {
        for candidate in [
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            "/usr/bin/npx"
        ] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }()

    /// Locate `docker` for shell PTYs.
    static let dockerPath: URL? = {
        for candidate in [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }()

    // MARK: - Lifecycle

    /// Best-effort start. If the cuabot server is already up (manual `npx cuabot --serve`
    /// in another terminal), we adopt it instead of starting a new one.
    func start() {
        guard pollingTask == nil else { return }

        state = .initializing
        lastStatusMessage = "Checking for existing cuabot server…"

        pollingTask = Task { [weak self] in
            await self?.runLifecycle()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        supervisor.terminate()
        state = .stopped
        lastStatusMessage = "Stopped"
        containerName = nil
    }

    // MARK: - Internals

    private func runLifecycle() async {
        // 1) See if a server is already responding.
        if let status = await client.tryStatus() {
            await apply(status: status)
            if status.ready {
                return await beginContinuousPolling()
            }
            return await waitForReady()
        }

        // 2) Nothing listening — try to start one.
        guard let npx = CUASandboxManager.npxPath else {
            state = .error
            lastStatusMessage = "npx not found on PATH. Install Node.js, then `npm i -g cua` per docs/cua-integration.md."
            return
        }

        do {
            try supervisor.start(
                executable: npx,
                arguments: ["cuabot", "--serve", String(serverPort)]
            )
            lastStatusMessage = "Starting cuabot server…"
        } catch {
            state = .error
            lastStatusMessage = "Failed to spawn cuabot: \(error.localizedDescription)"
            return
        }

        await waitForReady()
    }

    private func waitForReady(maxAttempts: Int = 120) async {
        for _ in 0..<maxAttempts {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let status = await client.tryStatus() else { continue }
            await apply(status: status)
            if status.ready { break }
        }
        await beginContinuousPolling()
    }

    private func beginContinuousPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let status = await client.tryStatus() else {
                state = .warning
                lastStatusMessage = "Server unreachable"
                continue
            }
            await apply(status: status)
        }
    }

    private func apply(status: CUAHTTPClient.StatusResponse) async {
        if status.ready {
            state = .running
            lastStatusMessage = "Healthy"
        } else {
            state = .initializing
            lastStatusMessage = "cuabot starting…"
        }
        // Heuristic: cuabot's `container` field looks like "running on port 10000"
        // — Docker container name is "cuabot-xpra" for the default session.
        // Verified empirically during Phase 2.
        if containerName == nil, status.container != nil {
            containerName = "cuabot-xpra"
        }
    }
}
