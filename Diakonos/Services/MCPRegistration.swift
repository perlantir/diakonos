import Foundation
import AppKit

/// Registers Diakonos's computer-use MCP bridge with the user's Claude Code
/// and Codex CLIs. Idempotent — re-running is a no-op (re-adds with the same
/// command path).
///
/// The MCP server is `Resources/mcp_browser.py` shipped inside Diakonos.app.
/// Each agent pane's `onSpawn` calls `ensureClaudeRegistered()` /
/// `ensureCodexRegistered()` once per Diakonos run so the server is wired
/// before the user's first turn in the agent.
@MainActor
final class MCPRegistration {
    static let shared = MCPRegistration()

    nonisolated static let serverName = "diakonos-browser"

    private var scriptURL: URL? {
        Bundle.main.url(forResource: "mcp_browser", withExtension: "py")
    }

    // MARK: - Public API

    /// **Synchronous** bootstrap. Called from `DiakonosApp.init()` before any
    /// pane spawns so the MCP server is in the agent's config at the moment
    /// the agent starts up. v1.3 registered inside `onSpawn`, AFTER the PTY
    /// already invoked claude/codex — claude reads `~/.claude.json` at
    /// startup and never re-reads, so the v1.3 server entry was visible at
    /// the Mac shell level but not inside the running pane. That was the
    /// v1.3 headline bug. v1.4 fixes it by writing the config first.
    ///
    /// Idempotent: each call removes any existing `diakonos-browser` entry
    /// and re-adds, so a re-launch picks up a new Diakonos bundle path
    /// (DerivedData vs /Applications) automatically.
    func bootstrap() {
        guard let script = scriptURL else {
            NSLog("[Diakonos MCP] mcp_browser.py not found in bundle resources")
            return
        }
        // Synchronous calls — both CLIs return in ~0.5s. Total ~1s added to
        // app launch, acceptable.
        Self.registerClaude(scriptPath: script.path)
        Self.registerCodex(scriptPath: script.path)
    }

    /// Legacy methods kept as no-ops so v1.3 callers (panes' onSpawn) compile
    /// without ceremony. Bootstrap-on-launch makes them obsolete.
    func ensureClaudeRegistered() { /* handled by bootstrap() now */ }
    func ensureCodexRegistered() { /* handled by bootstrap() now */ }

    // MARK: - Internals

    nonisolated private static func registerClaude(scriptPath: String) {
        // claude mcp add --scope user diakonos-browser -- python3 <path>
        guard let claude = Self.find(executable: "claude",
                                     candidates: [
                                        "/opt/homebrew/bin/claude",
                                        "/usr/local/bin/claude",
                                        "\(NSHomeDirectory())/.claude/local/claude"
                                     ]) else {
            NSLog("[Diakonos MCP] claude CLI not found on PATH; skipping registration")
            return
        }
        // Remove first (silently ignore failure) so re-adds don't fail noisily.
        _ = run(claude.path, ["mcp", "remove", "--scope", "user", serverName])
        let result = run(claude.path,
                         ["mcp", "add", "--scope", "user", serverName,
                          "--", "python3", scriptPath])
        NSLog("[Diakonos MCP] claude register: \(result.summary)")
    }

    nonisolated private static func registerCodex(scriptPath: String) {
        // codex mcp add diakonos-browser -- python3 <path>
        guard let codex = Self.find(executable: "codex",
                                    candidates: [
                                        "/opt/homebrew/bin/codex",
                                        "/usr/local/bin/codex"
                                    ]) else {
            NSLog("[Diakonos MCP] codex CLI not found on PATH; skipping registration")
            return
        }
        _ = run(codex.path, ["mcp", "remove", serverName])
        let result = run(codex.path,
                         ["mcp", "add", serverName,
                          "--", "python3", scriptPath])
        NSLog("[Diakonos MCP] codex register: \(result.summary)")
    }

    // MARK: - Helpers

    nonisolated private static func find(executable: String, candidates: [String]) -> URL? {
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                return URL(fileURLWithPath: c)
            }
        }
        // PATH walk as last resort.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = String(dir) + "/" + executable
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }

    struct RunResult { let code: Int32; let stdout: String; let stderr: String
        var summary: String {
            "exit=\(code) stdout=\(stdout.prefix(120)) stderr=\(stderr.prefix(120))"
        }
    }

    nonisolated private static func run(_ executablePath: String, _ arguments: [String]) -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        // Reach the user's typical CLI tool paths even if PATH inherits oddly.
        let augmentedPath = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = augmentedPath
        p.environment = env

        let out = Pipe(); let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return RunResult(code: -1, stdout: "", stderr: "\(error)")
        }
        let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let se = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(code: p.terminationStatus, stdout: so, stderr: se)
    }
}
