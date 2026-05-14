import Foundation

/// CDP input forwarding for chat-pane chromium instances. Each pane has its
/// own CDP port (claudeChat=9223, chatgptChat=9224). All calls flow through
/// cuabot's `/bash` endpoint to a one-shot Python invocation that talks
/// CDP over WebSocket.
///
/// Reusing cuabot /bash for this is slightly more expensive per call than
/// keeping a persistent WebSocket from Swift, but it avoids exposing
/// additional ports on the container and keeps the architecture matching
/// the rest of v1.x.
enum CDPInput {

    static func click(port: Int, x: Int, y: Int, button: String = "left") async {
        let py = """
        import json, urllib.request, asyncio
        async def main():
            try:
                import websockets
            except Exception:
                print('NO_WS'); return
            data = urllib.request.urlopen('http://localhost:\(port)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs: print('NO_TAB'); return
            async with websockets.connect(tabs[0]['webSocketDebuggerUrl'], ping_interval=None) as ws:
                for kind in ('mousePressed', 'mouseReleased'):
                    await ws.send(json.dumps({'id':1,'method':'Input.dispatchMouseEvent','params':{'type':kind,'x':\(x),'y':\(y),'button':'\(button)','clickCount':1}}))
                    await ws.recv()
                print('OK')
        asyncio.run(main())
        """
        await runPython(py)
    }

    static func scroll(port: Int, x: Int, y: Int, dy: Int) async {
        let py = """
        import json, urllib.request, asyncio
        async def main():
            try: import websockets
            except Exception: print('NO_WS'); return
            data = urllib.request.urlopen('http://localhost:\(port)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs: return
            async with websockets.connect(tabs[0]['webSocketDebuggerUrl'], ping_interval=None) as ws:
                await ws.send(json.dumps({'id':1,'method':'Input.dispatchMouseEvent','params':{'type':'mouseWheel','x':\(x),'y':\(y),'deltaX':0,'deltaY':\(dy)}}))
                await ws.recv()
        asyncio.run(main())
        """
        await runPython(py)
    }

    static func dispatchType(port: Int, text: String) async {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: "\\n")
        let py = """
        import json, urllib.request, asyncio
        async def main():
            try: import websockets
            except Exception: print('NO_WS'); return
            data = urllib.request.urlopen('http://localhost:\(port)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs: return
            async with websockets.connect(tabs[0]['webSocketDebuggerUrl'], ping_interval=None) as ws:
                for ch in "\(escaped)":
                    await ws.send(json.dumps({'id':1,'method':'Input.dispatchKeyEvent','params':{'type':'char','text':ch}}))
                    await ws.recv()
        asyncio.run(main())
        """
        await runPython(py)
    }

    static func dispatchKey(port: Int, name: String, modifiers: [String]) async {
        // Modifier bitmask: 1=Alt, 2=Ctrl, 4=Meta/Super, 8=Shift
        var bits = 0
        for m in modifiers {
            switch m.lowercased() {
            case "alt": bits |= 1
            case "ctrl": bits |= 2
            case "super", "meta", "cmd": bits |= 4
            case "shift": bits |= 8
            default: break
            }
        }
        let mapping: [String: (key: String, code: String, kc: Int)] = [
            "Return":    ("Enter",      "Enter",      13),
            "Tab":       ("Tab",        "Tab",         9),
            "Escape":    ("Escape",     "Escape",     27),
            "BackSpace": ("Backspace",  "Backspace",   8),
            "Delete":    ("Delete",     "Delete",     46),
            "Left":      ("ArrowLeft",  "ArrowLeft",  37),
            "Right":     ("ArrowRight", "ArrowRight", 39),
            "Up":        ("ArrowUp",    "ArrowUp",    38),
            "Down":      ("ArrowDown",  "ArrowDown",  40),
            "Home":      ("Home",       "Home",       36),
            "End":       ("End",        "End",        35),
            "Page_Up":   ("PageUp",     "PageUp",     33),
            "Page_Down": ("PageDown",   "PageDown",   34)
        ]
        let key, code: String
        let kc: Int
        if let m = mapping[name] {
            key = m.key; code = m.code; kc = m.kc
        } else {
            key = name; code = name; kc = Int(name.unicodeScalars.first?.value ?? 0)
        }
        let py = """
        import json, urllib.request, asyncio
        async def main():
            try: import websockets
            except Exception: print('NO_WS'); return
            data = urllib.request.urlopen('http://localhost:\(port)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs: return
            async with websockets.connect(tabs[0]['webSocketDebuggerUrl'], ping_interval=None) as ws:
                for t in ('keyDown','keyUp'):
                    await ws.send(json.dumps({'id':1,'method':'Input.dispatchKeyEvent','params':{'type':t,'key':'\(key)','code':'\(code)','windowsVirtualKeyCode':\(kc),'modifiers':\(bits)}}))
                    await ws.recv()
        asyncio.run(main())
        """
        await runPython(py)
    }

    /// Evaluate a JS expression in the page and return the string result.
    /// Used by ChatBridge for DOM scraping (read user messages, current URL,
    /// etc.) and by post-back JS (set textarea value).
    static func evaluate(port: Int, expression: String) async -> String? {
        let escaped = expression.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")
                                .replacingOccurrences(of: "\n", with: "\\n")
        let py = """
        import json, urllib.request, asyncio
        async def main():
            try: import websockets
            except Exception: print('NO_WS'); return
            data = urllib.request.urlopen('http://localhost:\(port)/json', timeout=2).read()
            tabs = [t for t in json.loads(data) if t.get('type')=='page']
            if not tabs: print('NO_TAB'); return
            async with websockets.connect(tabs[0]['webSocketDebuggerUrl'], ping_interval=None) as ws:
                await ws.send(json.dumps({'id':1,'method':'Runtime.evaluate','params':{'expression':"\(escaped)",'returnByValue':True,'awaitPromise':True}}))
                for _ in range(40):
                    msg = await ws.recv()
                    obj = json.loads(msg)
                    if obj.get('id') == 1:
                        v = obj.get('result',{}).get('result',{}).get('value')
                        print('VAL', json.dumps(v) if v is not None else 'null')
                        return
        asyncio.run(main())
        """
        let out = await runPythonCapturing(py)
        if let range = out.range(of: "VAL ") {
            return String(out[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - cuabot wire

    private static let cuabotURL = URL(string: "http://localhost:7842")!

    private static func runPython(_ source: String) async {
        let encoded = Data(source.utf8).base64EncodedString()
        let cmd = "echo '\(encoded)' | base64 -d | python3"
        var req = URLRequest(url: cuabotURL.appendingPathComponent("bash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["command": cmd])
        req.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func runPythonCapturing(_ source: String) async -> String {
        let encoded = Data(source.utf8).base64EncodedString()
        let cmd = "echo '\(encoded)' | base64 -d | python3"
        var req = URLRequest(url: cuabotURL.appendingPathComponent("bash"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["command": cmd])
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return "" }
        struct Resp: Decodable { let stdout: String?; let stderr: String? }
        if let r = try? JSONDecoder().decode(Resp.self, from: data) {
            return r.stdout ?? ""
        }
        return ""
    }
}
