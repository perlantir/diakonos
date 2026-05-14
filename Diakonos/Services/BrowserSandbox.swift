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

        // Python CDP helper: navigate current tab.
        let escaped = normalized.replacingOccurrences(of: "'", with: "'\\''")
        let helperCmd = "python3 /tmp/diakonos-nav.py 'navigate' '\(escaped)' 2>/tmp/diakonos-nav.err || echo HELPER_FAILED"
        _ = await postBashCapturing(helperCmd)
        // If the helper failed we just log to /tmp/diakonos-nav.err; user can
        // retry. v1.1's xdotool fallback was removed because xdotool isn't
        // installed in the cuabot image.
    }

    /// Reload current tab via CDP (Page.reload). v1.1/v1.2 used xdotool which
    /// is NOT installed in cuabot's image — that path silently failed.
    func reloadCurrent() async {
        await runHelper(action: "reload")
    }

    /// CDP Page.goBack.
    func goBack() async {
        await runHelper(action: "back")
    }

    /// CDP Page.goForward.
    func goForward() async {
        await runHelper(action: "forward")
    }

    /// Resize Chromium's viewport to W×H via CDP Browser.setWindowBounds.
    /// Used by BrowserPaneView when the pane's NSView size changes so the
    /// in-sandbox Chromium matches the viewer's aspect ratio.
    func setWindowSize(width: Int, height: Int) async {
        await ensureChromium()
        await ensureNavHelper()
        await runHelper(action: "resize", arg: "\(width)x\(height)")
    }

    /// Invoke the in-container Python helper with `action` (and optional arg).
    /// The helper handles Page.navigate / reload / back / forward and
    /// Browser.setWindowBounds via the CDP WebSocket.
    private func runHelper(action: String, arg: String = "") async {
        await ensureChromium()
        await ensureNavHelper()
        let escArg = arg.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = "python3 /tmp/diakonos-nav.py '\(action)' '\(escArg)' 2>/tmp/diakonos-nav.err || echo HELPER_FAILED"
        _ = await postBashCapturing(cmd)
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
    ///
    /// v1.5: --start-fullscreen so chromium fills the X display from launch,
    /// and after a brief delay we explicitly tell the window manager to
    /// fullscreen the window (covers the cases where --start-fullscreen
    /// didn't take effect). cuabot's /screenshot always returns 1280×720;
    /// chromium must fill the X display so the screenshot is all chromium
    /// instead of black margin (this was the v1.4 sizing bug).
    private func ensureChromium() async {
        let probe = "curl -s --max-time 1 -o /dev/null -w '%{http_code}' http://localhost:\(cdpPort)/json"
        let resp = await postBashCapturing(probe)
        if resp.contains("200") {
            // Already running — re-assert fullscreen idempotently.
            await postBash("DISPLAY=:100 wmctrl -r Chromium -b add,fullscreen 2>/dev/null || true")
            return
        }

        // Launch chromium on :100 with CDP and skip first-run prompts.
        let cmd = """
        DISPLAY=:100 setsid chromium --no-sandbox --no-first-run \
            --no-default-browser-check --disable-translate \
            --start-fullscreen --start-maximized \
            --remote-debugging-port=\(cdpPort) \
            --remote-debugging-address=127.0.0.1 \
            > /tmp/diakonos-chromium.log 2>&1 &
        """
        await postBash(cmd)
        // Give Chromium a moment to come up before the next /bash call hits it.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // Re-assert fullscreen — --start-fullscreen flag is sometimes
        // ignored when there's no window manager hint set yet.
        await postBash("DISPLAY=:100 wmctrl -r Chromium -b add,fullscreen 2>/dev/null || true")
    }

    /// Drop a tiny Python script into /tmp/diakonos-nav.py that uses
    /// websockets to call Page.navigate on the most recent page target.
    private func ensureNavHelper() async {
        guard !navHelperInstalled else { return }

        // 1) Make sure python3 + websockets are available.
        let installCmd = "pip3 install --user --quiet websockets 2>/dev/null || pip install --user --quiet websockets 2>/dev/null || true"
        await postBash(installCmd)

        // 2) Write the helper. Multi-action: navigate / reload / back /
        //    forward / resize. Single Python script so the WebSocket
        //    connection setup is shared.
        let script = """
        import json, sys, os, subprocess, urllib.request, asyncio

        CDP_PORT = \(cdpPort)
        # (mode_name, w, h) — cuabot's xrandr uses '754x394@50' / '2560x1440@50';
        # the third option '8192x4096' has no @ suffix.
        XRANDR_MODES = [('754x394@50', 754, 394), ('2560x1440@50', 2560, 1440)]

        def closest_mode(w, h):
            for name, mw, mh in XRANDR_MODES:
                if mw >= w and mh >= h:
                    return (name, mw, mh)
            return XRANDR_MODES[-1]

        def run_silently(*cmd):
            try:
                subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4)
            except Exception:
                pass

        async def cdp_session():
            try:
                import websockets
            except Exception:
                print('HELPER_FAILED: websockets not available')
                return None, None
            data = urllib.request.urlopen(f'http://localhost:{CDP_PORT}/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs:
                print('HELPER_FAILED: no tabs'); return None, None
            ws_url = tabs[0]['webSocketDebuggerUrl']
            ws = await websockets.connect(ws_url, ping_interval=None)
            return ws, tabs[0]

        async def send(ws, method, params=None, mid=1):
            await ws.send(json.dumps({'id': mid, 'method': method, 'params': params or {}}))
            return await ws.recv()

        async def dispatch_key(ws, name, modifiers):
            # CDP modifier bitmask: 1=Alt, 2=Ctrl, 4=Meta/Cmd, 8=Shift
            BITS = {'alt': 1, 'ctrl': 2, 'meta': 4, 'super': 4, 'cmd': 4, 'shift': 8}
            bits = 0
            for m in modifiers:
                bits |= BITS.get(m.lower(), 0)
            # Map name → (key, code, keyCode)
            SPECIAL = {
                'Return':    ('Enter',      'Enter',      13),
                'Enter':     ('Enter',      'Enter',      13),
                'Tab':       ('Tab',        'Tab',         9),
                'Escape':    ('Escape',     'Escape',     27),
                'Esc':       ('Escape',     'Escape',     27),
                'BackSpace': ('Backspace',  'Backspace',   8),
                'Backspace': ('Backspace',  'Backspace',   8),
                'Delete':    ('Delete',     'Delete',     46),
                'Left':      ('ArrowLeft',  'ArrowLeft',  37),
                'Right':     ('ArrowRight', 'ArrowRight', 39),
                'Up':        ('ArrowUp',    'ArrowUp',    38),
                'Down':      ('ArrowDown',  'ArrowDown',  40),
                'Home':      ('Home',       'Home',       36),
                'End':       ('End',        'End',        35),
                'Page_Up':   ('PageUp',     'PageUp',     33),
                'Page_Down': ('PageDown',   'PageDown',   34),
                'PageUp':    ('PageUp',     'PageUp',     33),
                'PageDown':  ('PageDown',   'PageDown',   34),
                'Space':     (' ',          'Space',      32),
            }
            for i in range(1, 13):
                SPECIAL[f'F{i}'] = (f'F{i}', f'F{i}', 111 + i)
            if name in SPECIAL:
                key, code, kc = SPECIAL[name]
                payload_down = {'type':'keyDown', 'key': key, 'code': code, 'windowsVirtualKeyCode': kc, 'modifiers': bits}
                payload_up   = {'type':'keyUp',   'key': key, 'code': code, 'windowsVirtualKeyCode': kc, 'modifiers': bits}
            else:
                # Printable single-char (with optional modifier chord). For
                # multi-char names not in SPECIAL, fall back to typing the
                # raw character.
                ch = name if len(name) == 1 else name[:1]
                if not ch:
                    print('HELPER_FAILED: empty key name')
                    return False
                payload_down = {'type':'keyDown', 'key': ch, 'text': ch, 'modifiers': bits}
                payload_up   = {'type':'keyUp',   'key': ch, 'modifiers': bits}
                if bits == 0:
                    payload_down['type'] = 'char'
                    payload_up = None
            await send(ws, 'Input.dispatchKeyEvent', payload_down, 50)
            if payload_up is not None:
                await send(ws, 'Input.dispatchKeyEvent', payload_up, 51)
            return True

        async def main(action, arg, arg2=''):
            ws, tab = await cdp_session()
            if ws is None: return 1
            try:
                if action == 'navigate':
                    await send(ws, 'Page.navigate', {'url': arg}, 1)
                elif action == 'reload':
                    await send(ws, 'Page.reload', {}, 1)
                elif action == 'back':
                    res = await send(ws, 'Page.getNavigationHistory', {}, 1)
                    h = json.loads(res); entries = h.get('result', {}).get('entries', [])
                    idx = h.get('result', {}).get('currentIndex', 0)
                    if idx > 0:
                        await send(ws, 'Page.navigateToHistoryEntry', {'entryId': entries[idx-1]['id']}, 2)
                elif action == 'forward':
                    res = await send(ws, 'Page.getNavigationHistory', {}, 1)
                    h = json.loads(res); entries = h.get('result', {}).get('entries', [])
                    idx = h.get('result', {}).get('currentIndex', 0)
                    if idx < len(entries) - 1:
                        await send(ws, 'Page.navigateToHistoryEntry', {'entryId': entries[idx+1]['id']}, 2)
                elif action == 'resize':
                    # v1.5 fix: cuabot's /screenshot returns a fixed 1280x720
                    # regardless of the X display size, so shrinking xrandr +
                    # setWindowBounds (the v1.4 approach) made chromium small
                    # while the screenshot stayed 1280x720 → 25% fill.
                    #
                    # Real fix: force chromium to fullscreen so it fills the
                    # entire X display, and cuabot's screenshot is 100%
                    # chromium content. We ignore `arg` (target size) — the
                    # screenshot is fixed-size, the pane handles aspect-fit
                    # rendering on the Mac side.
                    env = os.environ.copy(); env['DISPLAY'] = ':100'
                    subprocess.run(['wmctrl', '-r', 'Chromium', '-b', 'add,fullscreen'],
                                   check=False, env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=4)
                    subprocess.run(['wmctrl', '-r', 'Google', '-b', 'add,fullscreen'],
                                   check=False, env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=4)
                elif action == 'key':
                    # arg = name (Return, Tab, Escape, ...), arg2 = "ctrl,shift,..." or ""
                    modifiers = [m for m in (arg2.split(',') if arg2 else []) if m]
                    ok = await dispatch_key(ws, arg, modifiers)
                    if not ok: await ws.close(); return 1
                else:
                    print(f'HELPER_FAILED: unknown action {action}'); await ws.close(); return 1
                print('HELPER_OK')
                return 0
            finally:
                await ws.close()

        if __name__ == '__main__':
            action = sys.argv[1] if len(sys.argv) > 1 else 'navigate'
            arg    = sys.argv[2] if len(sys.argv) > 2 else ''
            arg2   = sys.argv[3] if len(sys.argv) > 3 else ''
            sys.exit(asyncio.run(main(action, arg, arg2)) or 0)
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
