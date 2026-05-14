import Foundation

/// Subprocess dispatcher for routed tasks. Replaces v1.5's `ChatRouter`
/// (which is preserved as a thin alias during the v1.7 transition).
///
/// Three contract differences from v1.5:
///   1. **CWD is set explicitly** via `Process.currentDirectoryURL =
///      URL(fileURLWithPath: projectRoot)`. v1.5/v1.6's bug:
///      `runCapturing` never set it, so `claude --print` ran in
///      Diakonos's launch CWD. Empirical test in `Process+CWDProbe`
///      verifies this is fixed.
///   2. **The composed context preamble** (Protocol/RoleCard/Project/
///      envelope, from `RoutingContext.compose`) is sent BEFORE the
///      raw task text on stdin.
///   3. **Per-target argv** is owned here, not split across ChatRouter
///      branches. Claude: `--print --output-format json --dangerously-
///      skip-permissions [--resume <sid>]`. Codex: `exec --json
///      --dangerously-bypass-approvals-and-sandbox [resume <sid>]`.
@MainActor
enum RouteDispatcher {

    struct Result {
        let body: String                  // visible response text
        let sessionID: String?            // captured session_id, if any
        let stderr: String
        let exitCode: Int32
    }

    /// Dispatch the routed task to Claude Code.
    static func dispatchClaude(envelope: RouteEnvelope,
                               preamble: String,
                               sessionID: String?) async -> Result {
        guard let bin = ResolveCLI.find("claude") else {
            return Result(body: "Claude Code CLI not found on PATH.",
                          sessionID: nil, stderr: "", exitCode: -1)
        }
        var args: [String] = ["--print", "--output-format", "json",
                              "--dangerously-skip-permissions"]
        if let sid = sessionID, !sid.isEmpty {
            args.append(contentsOf: ["--resume", sid])
        }
        let stdin = preamble + "\n" + envelope.task
        let (so, se, code) = await Process.runWithCWD(executable: bin.path,
                                                     arguments: args,
                                                     cwd: envelope.projectRoot,
                                                     stdin: stdin)
        if let data = so.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let body = (obj["result"] as? String) ?? ""
            let sid = obj["session_id"] as? String
            if body.isEmpty {
                return Result(body: "[Claude Code returned empty response]",
                              sessionID: sid, stderr: se, exitCode: code)
            }
            return Result(body: body, sessionID: sid, stderr: se, exitCode: code)
        }
        // Fallback: raw stdout (probably an error message).
        return Result(body: so.trimmingCharacters(in: .whitespacesAndNewlines),
                      sessionID: nil, stderr: se, exitCode: code)
    }

    /// Dispatch the routed task to Codex.
    static func dispatchCodex(envelope: RouteEnvelope,
                              preamble: String,
                              sessionID: String?) async -> Result {
        guard let bin = ResolveCLI.find("codex") else {
            return Result(body: "Codex CLI not found on PATH.",
                          sessionID: nil, stderr: "", exitCode: -1)
        }
        var args: [String] = ["exec", "--json",
                              "--dangerously-bypass-approvals-and-sandbox"]
        if let sid = sessionID, !sid.isEmpty {
            args = ["exec", "resume", sid, "--json",
                    "--dangerously-bypass-approvals-and-sandbox"]
        }
        let stdin = preamble + "\n" + envelope.task
        let (so, se, code) = await Process.runWithCWD(executable: bin.path,
                                                     arguments: args,
                                                     cwd: envelope.projectRoot,
                                                     stdin: stdin)
        // Codex's JSON stream isn't fully canonical; preserve v1.5
        // best-effort extraction.
        let trimmed = so.trimmingCharacters(in: .whitespacesAndNewlines)
        var sid: String? = nil
        for line in trimmed.split(separator: "\n") {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let s = obj["session_id"] as? String {
                sid = s
            }
        }
        let lines = trimmed.split(separator: "\n").map(String.init)
        let lastNonEmpty = lines.reversed().first(where: { !$0.isEmpty }) ?? ""
        if lastNonEmpty.isEmpty {
            return Result(body: "[Codex returned empty response]",
                          sessionID: sid, stderr: se, exitCode: code)
        }
        if let data = lastNonEmpty.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["message"] as? String { return Result(body: m, sessionID: sid, stderr: se, exitCode: code) }
            if let r = obj["result"]  as? String { return Result(body: r, sessionID: sid, stderr: se, exitCode: code) }
            if let t = obj["text"]    as? String { return Result(body: t, sessionID: sid, stderr: se, exitCode: code) }
        }
        return Result(body: lastNonEmpty, sessionID: sid, stderr: se, exitCode: code)
    }
}

extension Process {
    /// Run a subprocess with the given CWD. Same surface as v1.5
    /// `runCapturing` plus the new `cwd` parameter — the CWD-fix bug
    /// from v1.6 is that the v1.5 helper didn't accept/apply one.
    static func runWithCWD(executable: String,
                           arguments: [String],
                           cwd: String,
                           stdin: String? = nil,
                           timeoutSeconds: Double = 180) async -> (stdout: String, stderr: String, exit: Int32) {
        await Task.detached { () -> (String, String, Int32) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            p.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
            var env = ProcessInfo.processInfo.environment
            let aug = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin"
            env["PATH"] = aug
            // Also export PWD so anything that reads $PWD agrees with the OS CWD.
            env["PWD"] = cwd
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

/// Startup self-test for the CWD fix. Runs at app launch, logs to NSLog,
/// fails loudly in DEBUG. Empirically proves that
/// `Process.runWithCWD(.., cwd:)` actually sets the subprocess CWD —
/// independent of whether end-to-end routing has been wired up.
///
/// Uses `/bin/pwd -L` to get the *logical* CWD (no symlink resolution).
/// `/bin/pwd` defaults to physical on macOS, which would resolve `/tmp`
/// → `/private/tmp` and break a strict-equality check. -L matches what
/// the shell shows.
enum CWDSelfTest {
    @MainActor
    static func run() async {
        let expected = "/tmp"
        let (out, _, code) = await Process.runWithCWD(
            executable: "/bin/pwd", arguments: ["-L"], cwd: expected, stdin: nil
        )
        let observed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept either /tmp (logical) or /private/tmp (physical, in case
        // -L isn't honored on some macOS versions). Both prove the CWD
        // was applied.
        let ok = code == 0 && (observed == expected || observed == "/private\(expected)")
        if ok {
            NSLog("[Diakonos] CWDSelfTest PASS — /bin/pwd in cwd=\(expected) returned \(observed)")
        } else {
            let msg = "[Diakonos] CWDSelfTest FAIL — expected \(expected), got \(observed.isEmpty ? "<empty>" : observed) (exit \(code))"
            NSLog("%@", msg)
            #if DEBUG
            assertionFailure(msg)
            #endif
        }
    }
}
