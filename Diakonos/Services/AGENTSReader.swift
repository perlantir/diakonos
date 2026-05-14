import Foundation
import CryptoKit

/// Reads project-level AI-agent context from the canonical files inside a
/// chosen project folder, and seeds templates for any that are missing.
///
/// Canonical layout (v1.7):
///   - `AGENTS.md` — top-level canonical context, plain markdown.
///   - `.diakonos/context.md` — Diakonos-specific (not committed by
///     default; user may add to .gitignore).
///   - `CLAUDE.md` — recommended to import AGENTS via `@AGENTS.md`. Many
///     projects already have this from Claude Code's own conventions.
///
/// When a Claude Code / Codex pane selects a project folder, we check
/// these three. If `AGENTS.md` and `.diakonos/context.md` don't exist,
/// we drop templates so the user knows what they're for. We never
/// overwrite an existing file.
enum AGENTSReader {

    /// Snapshot of a project's agent context. `contextHash` is the SHA-256
    /// of the concatenated bodies (AGENTS + diakonosContext + Claude),
    /// stable for as long as none of the files change. Used by the route
    /// envelope so the AI can detect when it's working from a stale
    /// project view.
    struct Project {
        let root: URL
        let agentsMD: String?
        let diakonosContextMD: String?
        let claudeMD: String?
        let contextHash: String

        /// 200-char SUMMARY for injection into coordinator chat panes.
        var summary: String {
            // Prefer the first paragraph of AGENTS.md. Fallback: project
            // folder name + a hint that AGENTS.md is missing.
            if let agents = agentsMD, let first = firstParagraph(of: agents) {
                return first
            }
            return "Project \(root.lastPathComponent) — no AGENTS.md yet. See docs/v1.7-spec.md for the canonical format."
        }
    }

    /// Read all three canonical files. Returns a `Project` snapshot even
    /// when some are missing (their fields are nil). Does NOT seed
    /// templates — callers do that explicitly via `seedTemplatesIfMissing`.
    static func read(rootPath: String) -> Project {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let agents = readUTF8(root.appendingPathComponent("AGENTS.md"))
        let diakonos = readUTF8(root.appendingPathComponent(".diakonos/context.md"))
        let claude = readUTF8(root.appendingPathComponent("CLAUDE.md"))
        let hash = sha256("\(agents ?? "")\n---\n\(diakonos ?? "")\n---\n\(claude ?? "")")
        return Project(root: root,
                       agentsMD: agents,
                       diakonosContextMD: diakonos,
                       claudeMD: claude,
                       contextHash: hash)
    }

    /// If a file is missing, write a starter template so the user sees
    /// it next time they open the project. Idempotent — never overwrites.
    /// Returns the list of files actually created (for the in-app banner).
    @discardableResult
    static func seedTemplatesIfMissing(rootPath: String) -> [String] {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        var created: [String] = []
        // Only seed if we can read the parent dir — guards against
        // permissions surprises in sandboxed builds.
        guard FileManager.default.isReadableFile(atPath: rootPath) ||
              FileManager.default.isWritableFile(atPath: rootPath) else {
            return created
        }
        // AGENTS.md
        let agentsURL = root.appendingPathComponent("AGENTS.md")
        if !FileManager.default.fileExists(atPath: agentsURL.path),
           let template = bundleTemplate(named: "AGENTS.md.template") {
            try? template.write(to: agentsURL, atomically: true, encoding: .utf8)
            created.append("AGENTS.md")
        }
        // .diakonos/context.md (the directory may not exist)
        let dotDir = root.appendingPathComponent(".diakonos", isDirectory: true)
        let ctxURL = dotDir.appendingPathComponent("context.md")
        if !FileManager.default.fileExists(atPath: ctxURL.path),
           let template = bundleTemplate(named: "diakonos-context.md.template") {
            try? FileManager.default.createDirectory(at: dotDir,
                                                    withIntermediateDirectories: true)
            try? template.write(to: ctxURL, atomically: true, encoding: .utf8)
            created.append(".diakonos/context.md")
        }
        return created
    }

    // MARK: - Helpers

    private static func readUTF8(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func firstParagraph(of body: String) -> String? {
        // Trim leading whitespace/markdown headers; first non-empty
        // paragraph up to ~280 chars.
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var collected = ""
        for line in lines {
            let t = String(line).trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if !collected.isEmpty { break }
                continue
            }
            // Skip top-level heading
            if t.hasPrefix("#") && collected.isEmpty { continue }
            collected += (collected.isEmpty ? "" : " ") + t
            if collected.count > 280 { break }
        }
        if collected.isEmpty { return nil }
        return String(collected.prefix(280))
    }

    private static func bundleTemplate(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil,
                                        subdirectory: "templates") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
