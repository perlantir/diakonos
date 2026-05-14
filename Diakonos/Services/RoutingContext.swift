import Foundation

/// Composes the 5-layer routing context that prefaces each routed prompt.
///
/// Layers (highest authority last, so later layers override earlier):
///   1. **Protocol** — Diakonos's invariants. "You're being routed by
///      Diakonos. Respond per the reply_contract below. Don't `Code:`-
///      style trigger anything back, you'd loop." Versioned.
///   2. **Pane Mode card** — the role-card markdown for the target
///      surface (e.g., `implementer.claude-code@1.0.0`).
///   3. **User preferences** — short, picked from `Preferences` (e.g.,
///      response style, model, accent of focus). Empty for v1.7 Part A.
///   4. **Project** — AGENTS.md + .diakonos/context.md + CLAUDE.md
///      contents, concatenated with thin headers.
///   5. **Session** — per-route data: route_id, source_pane, etc.
///
/// The composed string is sent as the FIRST chunk of stdin to the
/// implementer's CLI (`claude --print` reads stdin), followed by the
/// user's actual task. The role-card itself instructs the implementer
/// how to interpret this preamble.
enum RoutingContext {

    /// The current protocol version. Bumped on breaking changes to the
    /// envelope or role-card format. Sessions snapshot this at creation
    /// time; subsequent protocol bumps don't retroactively affect them.
    static let protocolVersion = "1"

    /// Build the context preamble for a single route.
    static func compose(envelope: RouteEnvelope,
                        roleCardBody: String,
                        project: AGENTSReader.Project?) -> String {
        var out = ""
        // -- Layer 1: protocol
        out += """
        # Diakonos route — protocol v\(protocolVersion)

        You are running as the routed target of a Diakonos coordinator.
        The user typed a `Code:` (or `Codex:`) trigger in their chat
        interface, and Diakonos forwarded the task to you with the
        envelope below. Reply per the reply_contract. Do NOT emit a
        `Code:` / `Codex:` / `Exit:` line yourself — those are
        user-only triggers.

        """
        // -- Layer 2: role card
        out += """
        # Role
        \(roleCardBody.trimmingCharacters(in: .whitespacesAndNewlines))

        """
        // -- Layer 3: user prefs (placeholder for v1.7 Part A)
        // Reserved; intentionally empty.

        // -- Layer 4: project docs
        if let p = project {
            out += "# Project context\n"
            out += "Root: `\(p.root.path)`  ·  hash: `\(p.contextHash.prefix(12))…`\n\n"
            if let a = p.agentsMD, !a.isEmpty {
                out += "## AGENTS.md\n\n\(a.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            }
            if let d = p.diakonosContextMD, !d.isEmpty {
                out += "## .diakonos/context.md\n\n\(d.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            }
            if let c = p.claudeMD, !c.isEmpty {
                out += "## CLAUDE.md\n\n\(c.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
            }
        }
        // -- Layer 5: session / envelope (the route call itself)
        out += "# Route envelope\n\n"
        out += envelope.markdownYAML()
        out += "\n# Task\n\n\(envelope.task)\n"
        return out
    }
}
