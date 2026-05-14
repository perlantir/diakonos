import Foundation

/// Structured wrapper around every routed task. Encoded as
/// Markdown-with-YAML-frontmatter so the implementer can read it as
/// either prose or structured data. Sent as the lead-in of stdin to
/// the implementer's `--print` invocation.
///
/// Why structured? Implementers need to know:
///   - WHERE the project lives (absolute path → set as subprocess CWD)
///   - WHO routed (so it can reply back coherently)
///   - WHAT shape of reply Diakonos expects (the reply_contract)
///   - WHICH role-card version is in play (for audit + repro)
///   - WHICH context hash (so it can detect stale state).
///
/// Critically, `projectRoot` is the absolute path on the user's Mac. The
/// CWD-fix bug from v1.5/v1.6 was that `claude --print` ran in
/// Diakonos's launch CWD, not the project root. v1.7 sets
/// `Process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)`
/// before dispatching, AND echoes the path here for the implementer.
struct RouteEnvelope {
    let routeID: UUID
    let sourcePane: String          // e.g. "chat-pane:claude-web@topMid"
    let targetPane: String          // e.g. "claude-code:topRight"
    let projectRoot: String         // absolute filesystem path
    let contextHash: String         // sha256 of AGENTS+context+CLAUDE
    let roleCardID: String          // e.g. "implementer.claude-code"
    let roleCardVersion: String     // e.g. "1.0.0"
    let protocolVersion: String     // e.g. "1"
    let conversationID: String      // claude.ai chat UUID / chatgpt.com c UUID
    let task: String                // raw user text after `Code:` prefix
    let createdAt: Date

    /// Reply contract — what shape Diakonos expects in the response.
    /// Echoed in the envelope so the implementer's own context window
    /// has it.
    static let replyContractMarkdown = """
    ## Reply contract

    Reply with these sections, in this order:

    1. **Summary** — 1-3 sentences of what you did.
    2. **Files touched** — list of relative paths with one-line "why."
    3. **Commands run** — shell commands you executed (test, build, lint).
    4. **Tests** — what you verified, what you didn't.
    5. **Risks** — anything Diakonos's user should review before shipping.

    Keep it under ~400 words unless the task genuinely demands more.
    Diakonos posts your full reply back into the chat textarea; the
    user reviews + sends.
    """

    /// Render as Markdown with a YAML-style frontmatter block. The frontmatter
    /// is conventional `---`-delimited YAML; the body is the reply contract.
    func markdownYAML() -> String {
        let iso = ISO8601DateFormatter().string(from: createdAt)
        // Manual YAML emit — payloads are simple enough that we don't
        // need a YAML library (and Foundation doesn't ship one).
        let frontmatter = """
        ---
        route_id: \(routeID.uuidString)
        source_pane: \(yamlString(sourcePane))
        target_pane: \(yamlString(targetPane))
        project_root: \(yamlString(projectRoot))
        context_hash: \(contextHash)
        role_card: \(yamlString(roleCardID))
        role_card_version: \(yamlString(roleCardVersion))
        protocol_version: \(yamlString(protocolVersion))
        conversation_id: \(yamlString(conversationID))
        created_at: \(yamlString(iso))
        ---
        """
        return frontmatter + "\n\n" + Self.replyContractMarkdown + "\n"
    }

    /// Quote-and-escape for YAML. Conservative: always wrap in double
    /// quotes unless the value is an obvious safe scalar.
    private func yamlString(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        // Plain scalars: no quoting needed for [A-Za-z0-9_.\-/].
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-/:")
        if s.unicodeScalars.allSatisfy(allowed.contains) { return s }
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
