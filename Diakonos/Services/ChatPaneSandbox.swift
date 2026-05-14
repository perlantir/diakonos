import Foundation
import AppKit

/// Per-chat-pane sandbox state. Each `.claudeChat` / `.chatgptChat` instance
/// runs its own non-headless Chromium inside the cuabot container, with its
/// own `--user-data-dir` (so logins persist) and its own `--remote-debugging-port`
/// (so CDP screenshots / input forwarding / Runtime.evaluate are isolated).
///
/// Non-headless is required: headless Chromium triggers Cloudflare Turnstile
/// on claude.ai (verified live during v1.5 probing). The non-headless windows
/// are launched off-screen at (4000, 4000) so they don't visually overlap the
/// Browser pane's foreground Chromium on display :100. CDP `Page.captureScreenshot`
/// captures content regardless of visibility.
@MainActor
final class ChatPaneSandbox: ObservableObject {

    enum Kind {
        case claudeChat
        case chatgptChat

        /// Short stable identifier, used by `RouteEnvelope.sourcePane`.
        var rawIdentifier: String {
            switch self {
            case .claudeChat:  return "claudeChat"
            case .chatgptChat: return "chatgptChat"
            }
        }

        var domain: String {
            switch self {
            case .claudeChat:  return "https://claude.ai"
            case .chatgptChat: return "https://chatgpt.com"
            }
        }
        var userDataDir: String {
            switch self {
            case .claudeChat:  return "/home/user/.config/chromium-claude"
            case .chatgptChat: return "/home/user/.config/chromium-chatgpt"
            }
        }
        var cdpPort: Int {
            switch self {
            case .claudeChat:  return 9223
            case .chatgptChat: return 9224
            }
        }
        var displayName: String {
            switch self {
            case .claudeChat:  return "Claude Chat"
            case .chatgptChat: return "ChatGPT"
            }
        }
    }

    @Published private(set) var state: SandboxState = .stopped
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var latestImage: NSImage? = nil
    /// Conversation ID (last URL path segment when the user is in a chat).
    @Published private(set) var conversationID: String? = nil
    @Published private(set) var currentURL: String = ""

    let kind: Kind
    private let cuabotPort: Int = 7842
    private var pollingTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

    init(kind: Kind) {
        self.kind = kind
    }

    private var cuabotBase: URL { URL(string: "http://localhost:\(cuabotPort)")! }

    // MARK: - Lifecycle

    func start() {
        guard pollingTask == nil else { return }
        state = .initializing
        statusMessage = "Spawning sandboxed \(kind.displayName)…"
        pollingTask = Task { [weak self] in
            await self?.ensureChromium()
            await self?.beginStreaming()
        }
    }

    func stop() {
        pollingTask?.cancel(); pollingTask = nil
        streamingTask?.cancel(); streamingTask = nil
        state = .stopped
    }

    // MARK: - Internals

    private func ensureChromium() async {
        // Probe — if CDP /json already responds, adopt.
        let probe = "curl -s --max-time 1 -o /dev/null -w '%{http_code}' http://localhost:\(kind.cdpPort)/json"
        let resp = await postBashCapturing(probe)
        if !resp.contains("200") {
            // Spawn non-headless chromium off-screen (4000,4000) so it doesn't
            // overlap the Browser pane's foreground chromium on :100.
            let cmd = """
            mkdir -p \(kind.userDataDir); \
            DISPLAY=:100 setsid chromium --no-sandbox --no-first-run \
                --no-default-browser-check --disable-translate \
                --user-data-dir=\(kind.userDataDir) \
                --window-position=4000,4000 --window-size=1280,800 \
                --remote-debugging-port=\(kind.cdpPort) \
                --remote-debugging-address=127.0.0.1 \
                "\(kind.domain)" \
                > /tmp/diakonos-chrome-\(kind.cdpPort).log 2>&1 &
            """
            await postBash(cmd)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
        state = .running
        statusMessage = "Running"
    }

    /// Stream screenshots via CDP Page.captureScreenshot at ~2 fps.
    private func beginStreaming() async {
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.captureFrame()
                try? await Task.sleep(nanoseconds: 500_000_000) // 2 fps
            }
        }
    }

    private func captureFrame() async {
        // Minimal CDP JSON-RPC via direct curl through cuabot /bash:
        // 1) /json/list to get page targetId + ws URL
        // 2) Send Page.captureScreenshot over websocket
        // For simplicity we use a tiny Python script (in-container) to grab
        // the screenshot in one call.
        // Base64-pack the inline Python so we don't have to fight bash
        // heredoc + shell-quoting + Swift-string-literal interpolation.
        let py = """
        import json, urllib.request, asyncio
        async def main():
            try:
                import websockets
            except Exception:
                print('NO_WS'); return
            data = urllib.request.urlopen('http://localhost:\(kind.cdpPort)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs:
                print('NO_TAB'); return
            ws_url = tabs[0]['webSocketDebuggerUrl']
            url = tabs[0].get('url', '')
            try:
                async with websockets.connect(ws_url, ping_interval=None, max_size=20_000_000) as ws:
                    await ws.send(json.dumps({'id':1,'method':'Page.captureScreenshot','params':{'format':'jpeg','quality':70}}))
                    for _ in range(40):
                        msg = await ws.recv()
                        obj = json.loads(msg)
                        if obj.get('id') == 1:
                            img = obj.get('result',{}).get('data','')
                            print('URL\\t' + url)
                            print('IMG\\t' + img)
                            return
            except Exception as e:
                print(f'ERR\\t{e}')
        asyncio.run(main())
        """
        let encoded = Data(py.utf8).base64EncodedString()
        let cmd = "echo '\(encoded)' | base64 -d | python3"
        let out = await postBashCapturing(cmd)
        var url = ""
        var b64 = ""
        for line in out.split(separator: "\n") {
            if line.hasPrefix("URL\t") { url = String(line.dropFirst(4)) }
            else if line.hasPrefix("IMG\t") { b64 = String(line.dropFirst(4)) }
        }
        if !b64.isEmpty, let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
            latestImage = img
        }
        if !url.isEmpty {
            currentURL = url
            conversationID = Self.extractConversationID(from: url, kind: kind)
        }
    }

    static func extractConversationID(from url: String, kind: Kind) -> String? {
        // claude.ai/chat/<uuid>  |  chatgpt.com/c/<uuid>
        guard let u = URL(string: url) else { return nil }
        let comps = u.pathComponents.filter { $0 != "/" }
        switch kind {
        case .claudeChat:
            if comps.count >= 2, comps[0] == "chat" { return comps[1] }
        case .chatgptChat:
            if comps.count >= 2, comps[0] == "c" { return comps[1] }
        }
        return nil
    }

    // MARK: - cuabot wire helpers

    private func postBash(_ command: String) async {
        var req = URLRequest(url: cuabotBase.appendingPathComponent("bash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["command": command])
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: req)
    }

    private func postBashCapturing(_ command: String) async -> String {
        var req = URLRequest(url: cuabotBase.appendingPathComponent("bash"))
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
}
