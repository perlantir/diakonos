import Foundation

/// Spawns Claude Code / Codex as one-shot subprocesses per routed turn, with
/// session-id continuity across turns in the same chat conversation. v1.5
/// goal §b.2: continuity via `claude --print --output-format json` →
/// captures `session_id` → subsequent turns use `--resume <id>`.
///
/// Claude --print returns JSON like:
///   { "result": "...", "session_id": "<uuid>", ... }
/// Codex exec doesn't expose a session ID via --json natively in the same way;
/// for v1.5 codex routing uses one-shot per turn and documents the
/// continuity gap.
enum ChatRouter {

    static func invokeClaude(prompt: String,
                             sessionID: String?,
                             onSessionID: @escaping (String) -> Void) async -> String {
        guard let bin = ResolveCLI.find("claude") else {
            return "Claude Code CLI not found on PATH."
        }
        var args: [String] = ["--print", "--output-format", "json",
                              "--dangerously-skip-permissions"]
        if let sid = sessionID, !sid.isEmpty {
            args.append(contentsOf: ["--resume", sid])
        }
        let (stdout, _, _) = await Process.runCapturing(executable: bin.path,
                                                       arguments: args,
                                                       stdin: prompt)
        // Parse JSON to extract result + session_id
        if let data = stdout.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let result = (obj["result"] as? String) ?? ""
            if let sid = obj["session_id"] as? String {
                onSessionID(sid)
            }
            if result.isEmpty {
                return "[Claude Code returned empty response]"
            }
            return result
        }
        // Fallback: return stdout as-is (probably an error message)
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func invokeCodex(prompt: String,
                            sessionID: String?,
                            onSessionID: @escaping (String) -> Void) async -> String {
        guard let bin = ResolveCLI.find("codex") else {
            return "Codex CLI not found on PATH."
        }
        // codex exec is the non-interactive mode. --json output for parsing.
        // Codex's exec resume <session_id> supports continuity but session
        // capture-on-first-run is more involved than claude's; v1.5 ships
        // one-shot per turn for Codex with continuity logged as a v1.6 task.
        var args: [String] = ["exec", "--json",
                              "--dangerously-bypass-approvals-and-sandbox"]
        if let sid = sessionID, !sid.isEmpty {
            args = ["exec", "resume", sid, "--json",
                    "--dangerously-bypass-approvals-and-sandbox"]
        }
        let (stdout, _, _) = await Process.runCapturing(executable: bin.path,
                                                       arguments: args,
                                                       stdin: prompt)
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Best-effort session_id extraction: scan each line for a JSON
        // object with session_id.
        for line in trimmed.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sid = obj["session_id"] as? String {
                onSessionID(sid)
            }
        }
        // Use last non-empty stdout line as the response text. Codex's
        // --json emits multiple events; the last 'agent_message' event
        // usually contains the final answer, but the schema isn't stable
        // enough to parse exactly here. Document as known weak point.
        let lines = trimmed.split(separator: "\n").map(String.init)
        let lastNonEmpty = lines.reversed().first(where: { !$0.isEmpty }) ?? ""
        if lastNonEmpty.isEmpty { return "[Codex returned empty response]" }
        // If the last line is JSON, try to extract a message field.
        if let data = lastNonEmpty.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["message"] as? String { return m }
            if let r = obj["result"] as? String { return r }
            if let t = obj["text"] as? String { return t }
            // Fallback: pretty-print the JSON
            if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
               let s = String(data: pretty, encoding: .utf8) {
                return s
            }
        }
        return lastNonEmpty
    }
}

enum ResolveCLI {
    static func find(_ name: String) -> URL? {
        let common = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(NSHomeDirectory())/.local/bin/\(name)"
        ]
        for c in common where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let p = String(dir) + "/" + name
                if FileManager.default.isExecutableFile(atPath: p) {
                    return URL(fileURLWithPath: p)
                }
            }
        }
        return nil
    }
}

extension Process {
    /// Run a subprocess with optional stdin, capture stdout/stderr/exit.
    static func runCapturing(executable: String,
                             arguments: [String],
                             stdin: String? = nil,
                             timeoutSeconds: Double = 180) async -> (stdout: String, stderr: String, exit: Int32) {
        await Task.detached { () -> (String, String, Int32) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            // Augment PATH to reach common bin dirs even when launched from /Applications.
            let aug = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin"
            env["PATH"] = aug
            p.environment = env
            let inp = Pipe(); let out = Pipe(); let err = Pipe()
            p.standardInput = inp
            p.standardOutput = out
            p.standardError = err
            do {
                try p.run()
                if let s = stdin {
                    inp.fileHandleForWriting.write(s.data(using: .utf8) ?? Data())
                }
                try? inp.fileHandleForWriting.close()
                p.waitUntilExit()
            } catch {
                return ("", "spawn error: \(error)", -1)
            }
            let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let se = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (so, se, p.terminationStatus)
        }.value
    }
}
