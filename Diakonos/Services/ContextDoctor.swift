import Foundation

/// Scans a project's AI-agent context files and flags conflicts /
/// missing pieces. Result is rendered by the Diagnostics tab's
/// "Check Context" action.
///
/// What it checks:
///   - Each canonical file (AGENTS.md / .diakonos/context.md /
///     CLAUDE.md) — exists?, hash, byte size
///   - CLAUDE.md imports AGENTS.md via `@AGENTS.md`? Common
///     convention; if CLAUDE.md exists but doesn't import AGENTS,
///     warn that Claude Code may diverge from the canonical view
///   - Test-command heuristic: search for "test" / "tests" sections
///     in AGENTS and CLAUDE; if both mention a test command and
///     they DIFFER, raise a conflict
///   - Stack heuristic: same pattern for "Stack" / "Build" sections
///
/// The result is a struct that's purely diagnostic — Diakonos does
/// nothing with the warnings except surface them.
enum ContextDoctor {

    struct Finding: Identifiable, Hashable {
        let id = UUID()
        let severity: Severity
        let title: String
        let detail: String

        enum Severity: String { case ok, warning, error }
    }

    struct Report {
        let projectRoot: URL
        let contextHash: String   // matches AGENTSReader.Project.contextHash
        let findings: [Finding]
    }

    static func diagnose(projectRoot: String) -> Report {
        let project = AGENTSReader.read(rootPath: projectRoot)
        var findings: [Finding] = []

        // File presence + size.
        for (label, body, relpath) in [
            ("AGENTS.md", project.agentsMD, "AGENTS.md"),
            (".diakonos/context.md", project.diakonosContextMD, ".diakonos/context.md"),
            ("CLAUDE.md", project.claudeMD, "CLAUDE.md"),
        ] {
            if let body = body {
                findings.append(Finding(
                    severity: .ok,
                    title: "\(label) present",
                    detail: "\(body.utf8.count) bytes at \(relpath)"
                ))
            } else {
                findings.append(Finding(
                    severity: relpath == "CLAUDE.md" ? .warning : .error,
                    title: "\(label) missing",
                    detail: "Expected at \(relpath). Re-select the project folder in the pane chip to auto-create templates."
                ))
            }
        }

        // CLAUDE.md should @AGENTS.md the canonical file.
        if let claude = project.claudeMD, project.agentsMD != nil {
            if !claude.contains("@AGENTS.md") {
                findings.append(Finding(
                    severity: .warning,
                    title: "CLAUDE.md doesn't import AGENTS.md",
                    detail: "Convention: CLAUDE.md should reference `@AGENTS.md` so Claude Code's loader pulls the canonical context. Without this, the two files can drift."
                ))
            } else {
                findings.append(Finding(
                    severity: .ok,
                    title: "CLAUDE.md imports AGENTS.md",
                    detail: "@AGENTS.md found in CLAUDE.md."
                ))
            }
        }

        // Test command heuristic: look for "test" sections in AGENTS
        // and CLAUDE and compare the first code-fence content.
        let agentsTests = firstCodeFence(under: "test", in: project.agentsMD)
        let claudeTests = firstCodeFence(under: "test", in: project.claudeMD)
        if let a = agentsTests, let c = claudeTests, a != c {
            findings.append(Finding(
                severity: .warning,
                title: "Test commands diverge",
                detail: "AGENTS.md → \"\(a.prefix(80))\"\nCLAUDE.md → \"\(c.prefix(80))\""
            ))
        }

        // Build command heuristic, same pattern.
        let agentsBuild = firstCodeFence(under: "build", in: project.agentsMD)
        let claudeBuild = firstCodeFence(under: "build", in: project.claudeMD)
        if let a = agentsBuild, let c = claudeBuild, a != c {
            findings.append(Finding(
                severity: .warning,
                title: "Build commands diverge",
                detail: "AGENTS.md → \"\(a.prefix(80))\"\nCLAUDE.md → \"\(c.prefix(80))\""
            ))
        }

        if !findings.contains(where: { $0.severity != .ok }) {
            findings.append(Finding(
                severity: .ok,
                title: "No conflicts found",
                detail: "Context appears consistent. context_hash: \(project.contextHash.prefix(12))…"
            ))
        }

        return Report(projectRoot: project.root,
                      contextHash: project.contextHash,
                      findings: findings)
    }

    /// Find the first fenced code block under a heading whose text
    /// (lowercased) contains `keyword`. Returns the fenced content
    /// or nil if not found.
    private static func firstCodeFence(under keyword: String, in body: String?) -> String? {
        guard let body else { return nil }
        let lines = body.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("#"),
               line.lowercased().contains(keyword) {
                // Walk forward until we find a fence.
                var j = i + 1
                while j < lines.count {
                    if lines[j].hasPrefix("```") {
                        // Capture until the closing fence.
                        var content = ""
                        var k = j + 1
                        while k < lines.count, !lines[k].hasPrefix("```") {
                            content += lines[k] + "\n"
                            k += 1
                        }
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { return trimmed }
                        break
                    }
                    // Stop scanning if we hit the next heading.
                    if lines[j].hasPrefix("#") { break }
                    j += 1
                }
            }
            i += 1
        }
        return nil
    }
}
