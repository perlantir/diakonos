import Foundation
import SwiftUI

/// Lifecycle + navigation for the cuabot-managed Chromium sandbox.
/// v1.2 changes over v1.1:
///   - `fetchCurrentURL()` queries CDP HTTP API inside the container so the
///     URL bar reflects what Chromium actually shows.
///   - `navigate(to:)` reuses the existing tab via a small inline Python
///     CDP helper (installed at /tmp/diakonos-nav.py on first use), and
///     falls back to xdotool Ctrl+L navigation if the helper is unavailable.
///   - `resetSandbox()` calls `npx cuabot --reset sandbox`.
///   - `openFloatingChromiumWindow()` spawns chromium in a NEW window without
///     reusing the embedded one (for the 3-dot "Open in floating window").
@MainActor
final class BrowserSandbox: ObservableObject {

    @Published private(set) var state: SandboxState = .stopped
    @Published private(set) var statusMessage: String = ""

    private let port: Int = 7842
    private let cdpPort: Int = 9222   // inside the container
    private var process: Process?
    private var pollingTask: Task<Void, Never>?
    private var navHelperInstalled = false

    private var baseURL: URL { URL(string: "http://localhost:\(port)")! }

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

    func resetSandbox() async {
        guard let npx = Self.npxPath else {
            statusMessage = "npx not found"; return
        }
        statusMessage = "Resetting sandbox…"
        state = .initializing

        // Kill any running Chromium inside the container first; then ask
        // cuabot to reset the sandbox state. The cuabot CLI for this is
        // `cuabot --reset sandbox`.
        let p = Process()
        p.executableURL = npx
        p.arguments = ["cuabot", "--reset", "sandbox"]
        p.environment = ProcessInfo.processInfo.environment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()

        navHelperInstalled = false
        await waitForReady()
    }

    // MARK: - Navigation

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

        // Make sure chromium is running (with CDP) and a nav helper is in place.
        await ensureChromium()
        await ensureNavHelper()

        // First try the Python CDP helper: navigate current tab.
        let escaped = normalized.replacingOccurrences(of: "'", with: "'\\''")
        let helperCmd = "python3 /tmp/diakonos-nav.py '\(escaped)' 2>/tmp/diakonos-nav.err || echo NAV_FAILED"
        let result = await postBashCapturing(helperCmd)
        if result.contains("NAV_FAILED") {
            // Fallback: xdotool Ctrl+L → type → Enter against the Chromium window.
            let xdoFallback = """
            DISPLAY=:100 xdotool search --onlyvisible --name 'Chromium\\|Chrome' windowactivate --sync \
              key --clearmodifiers ctrl+l \
              type '\(escaped)' \
              key --clearmodifiers Return 2>/dev/null || true
            """
            await postBash(xdoFallback)
        }
    }

    func reloadCurrent() async {
        await postBash("DISPLAY=:100 xdotool key --clearmodifiers F5 2>/dev/null || true")
    }

    func goBack() async {
        await postBash("DISPLAY=:100 xdotool key --clearmodifiers alt+Left 2>/dev/null || true")
    }

    func goForward() async {
        await postBash("DISPLAY=:100 xdotool key --clearmodifiers alt+Right 2>/dev/null || true")
    }

    /// Spawn a fresh Chromium window for the user's "pop-out" action.
    func openFloatingChromiumWindow() async {
        let cmd = "DISPLAY=:100 setsid chromium --no-sandbox --new-window 'about:blank' > /tmp/diakonos-chromium-popout.log 2>&1 &"
        await postBash(cmd)
    }

    /// Read Chromium's current tab URL via the CDP HTTP endpoint (inside the
    /// container). Returns nil if no tab.
    func fetchCurrentURL() async -> String? {
        let cmd = "curl -s --max-time 2 http://localhost:\(cdpPort)/json"
        let raw = await postBashCapturing(cmd)
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return nil }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        // First "page"-type entry is the active tab.
        for entry in arr where (entry["type"] as? String) == "page" {
            if let u = entry["url"] as? String { return u }
        }
        return nil
    }

    // MARK: - Internals

    /// Make sure Chromium is running inside the sandbox with CDP enabled.
    /// Cheap idempotent check: if `curl localhost:9222/json` doesn't return
    /// an array, spawn chromium.
    private func ensureChromium() async {
        let probe = "curl -s --max-time 1 -o /dev/null -w '%{http_code}' http://localhost:\(cdpPort)/json"
        let resp = await postBashCapturing(probe)
        if resp.contains("200") { return }

        // Launch chromium on :100 with CDP and skip first-run prompts.
        let cmd = """
        DISPLAY=:100 setsid chromium --no-sandbox --no-first-run \
            --no-default-browser-check --disable-translate \
            --remote-debugging-port=\(cdpPort) \
            --remote-debugging-address=127.0.0.1 \
            > /tmp/diakonos-chromium.log 2>&1 &
        """
        await postBash(cmd)
        // Give Chromium a moment to come up before the next /bash call hits it.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    /// Drop a tiny Python script into /tmp/diakonos-nav.py that uses
    /// websockets to call Page.navigate on the most recent page target.
    private func ensureNavHelper() async {
        guard !navHelperInstalled else { return }

        // 1) Make sure python3 + websockets are available.
        let installCmd = "pip3 install --user --quiet websockets 2>/dev/null || pip install --user --quiet websockets 2>/dev/null || true"
        await postBash(installCmd)

        // 2) Write the helper.
        let script = """
        import json, sys, urllib.request, asyncio
        async def main(url):
            try:
                import websockets
            except Exception:
                print('NAV_FAILED: websockets not available'); return 1
            data = urllib.request.urlopen('http://localhost:\(cdpPort)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs:
                print('NAV_FAILED: no tabs'); return 1
            ws_url = tabs[0]['webSocketDebuggerUrl']
            async with websockets.connect(ws_url, ping_interval=None) as ws:
                await ws.send(json.dumps({'id':1,'method':'Page.navigate','params':{'url':url}}))
                await ws.recv()
            print('NAV_OK')
            return 0
        if __name__ == '__main__':
            url = sys.argv[1] if len(sys.argv) > 1 else ''
            sys.exit(asyncio.run(main(url)) or 0)
        """
        // Write via base64 to avoid shell-quote escaping headaches.
        let b64 = Data(script.utf8).base64EncodedString()
        let write = "echo '\(b64)' | base64 -d > /tmp/diakonos-nav.py"
        await postBash(write)
        navHelperInstalled = true
    }

    private func runLifecycle() async {
        if let status = await fetchStatus() {
            apply(status: status)
            if status.ready { return await pollContinuously() }
            return await waitForReady()
        }

        guard let npx = Self.npxPath else {
            state = .error
            statusMessage = "npx not found. Install Node + cuabot."
            return
        }

        let p = Process()
        p.executableURL = npx
        p.arguments = ["cuabot", "--serve", String(port)]
        p.environment = ProcessInfo.processInfo.environment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch {
            state = .error
            statusMessage = "Failed to launch cuabot: \(error.localizedDescription)"
            return
        }
        process = p
        statusMessage = "Starting cuabot…"
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
        var req = URLRequest(url: baseURL.appendingPathComponent("bash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["command": command])
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: req)
    }

    private func postBashCapturing(_ command: String) async -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("bash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["command": command])
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return "" }
        struct Resp: Decodable { let stdout: String?; let stderr: String? }
        if let r = try? JSONDecoder().decode(Resp.self, from: data) {
            return r.stdout ?? ""
        }
        return ""
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
