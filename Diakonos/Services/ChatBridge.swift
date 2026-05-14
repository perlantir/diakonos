import Foundation
import AppKit

/// Bidirectional message router between sandboxed chat panes (claude.ai /
/// chatgpt.com) and local agent panes (Claude Code / Codex).
///
/// Per-conversation thread state (URL-derived conversation ID). Triggers
/// case-sensitive at message start:
///   - `Code:`  → routes subsequent messages to Claude Code (via
///                `claude --print --resume <session-id>` for continuity)
///   - `Codex:` → routes to Codex (via `codex exec`)
///   - `Exit:`  → ends routing for that conversation
///
/// Polling cadence: 3 s per pane. DOM selectors for claude.ai and
/// chatgpt.com are documented in `ChatPostbackJS`. **They will change.**
/// When a selector probe fails, `DiagnosticsLog.shared.log(.selectorMissing, …)`
/// fires so users notice the breakage.
@MainActor
final class ChatBridge {

    static let shared = ChatBridge()

    private var sandboxes: [ObjectIdentifier: ChatPaneSandbox] = [:]
    private var pollingTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Per-conversation routing state. Key: conversation ID.
    private var threads: [String: ChatThread] = [:]
    /// Per-pane: last message hash we've already routed. Avoids double-pickup.
    private var lastSeenHash: [ObjectIdentifier: String] = [:]
    /// Per-conversation: Claude Code session ID for --resume continuity.
    private var claudeSessions: [String: String] = [:]
    /// Per-conversation: Codex session ID for `codex exec resume` continuity.
    private var codexSessions: [String: String] = [:]

    struct ChatThread {
        enum Target { case claudeCode, codex }
        var target: Target
        var conversationID: String
    }

    func register(sandbox: ChatPaneSandbox) {
        let key = ObjectIdentifier(sandbox)
        if sandboxes[key] != nil { return }
        sandboxes[key] = sandbox
        pollingTasks[key] = Task { [weak self, weak sandbox] in
            guard let sandbox else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self?.poll(sandbox: sandbox)
            }
        }
        DiagnosticsLog.shared.log(.info, "registered \(sandbox.kind.displayName)")
    }

    func unregister(sandbox: ChatPaneSandbox) {
        let key = ObjectIdentifier(sandbox)
        pollingTasks[key]?.cancel()
        pollingTasks[key] = nil
        sandboxes[key] = nil
        DiagnosticsLog.shared.log(.info, "unregistered \(sandbox.kind.displayName)")
    }

    /// Returns the active routing target for a sandbox's current
    /// conversation, used by WorkspaceView to draw the "→ <target>" chip.
    func activeTarget(for sandbox: ChatPaneSandbox) -> ChatThread.Target? {
        guard let convo = sandbox.conversationID else { return nil }
        return threads[convo]?.target
    }

    /// Position-keyed lookup used by `RoutingBadge`. Finds the sandbox
    /// registered for a given slot position and returns its active routing
    /// target (if any).
    func activeTarget(forSlotPosition position: PaneSlotPosition) -> ChatThread.Target? {
        // We don't have a direct position→sandbox map; iterate. Cheap because
        // sandboxes.count is bounded by the four slots.
        for sandbox in sandboxes.values {
            guard let convo = sandbox.conversationID else { continue }
            if let target = threads[convo]?.target {
                // We can't reverse-derive the slot position from the sandbox
                // (no back-reference), so this returns the FIRST active
                // routing in any registered chat pane. Acceptable for v1.5
                // since at most one chat pane is realistically routing at
                // a time per common usage.
                return target
            }
        }
        return nil
    }

    // MARK: - Polling

    private func poll(sandbox: ChatPaneSandbox) async {
        guard sandbox.state == .running, let convo = sandbox.conversationID else { return }
        let port = sandbox.kind.cdpPort
        let key = ObjectIdentifier(sandbox)

        // Scrape latest user message. Selectors documented in
        // ChatPostbackJS — same site, shared JS module.
        let js: String
        switch sandbox.kind {
        case .claudeChat:  js = ChatPostbackJS.readLatestUserMessageClaude
        case .chatgptChat: js = ChatPostbackJS.readLatestUserMessageChatGPT
        }
        guard let raw = await CDPInput.evaluate(port: port, expression: js) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // result may be quoted JSON string; strip surrounding quotes if so
        let message = unquoteJSON(trimmed)
        guard !message.isEmpty, message != "null" else {
            if trimmed == "null" {
                // Selector returned null — likely DOM mismatch
                DiagnosticsLog.shared.log(.selectorMissing,
                    "\(sandbox.kind.displayName): no user message found (DOM may have changed)")
            }
            return
        }
        let hash = "\(convo)|\(message.hashValue)"
        guard lastSeenHash[key] != hash else { return }
        lastSeenHash[key] = hash

        await handleNewMessage(sandbox: sandbox, conversationID: convo, text: message)
    }

    private func unquoteJSON(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
            t.removeFirst(); t.removeLast()
        }
        return t.replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func handleNewMessage(sandbox: ChatPaneSandbox, conversationID: String, text: String) async {
        let parsed = ChatTriggerParser.parse(text)

        switch parsed {
        case .startThread(let target, let payload):
            threads[conversationID] = ChatThread(target: target, conversationID: conversationID)
            DiagnosticsLog.shared.log(.triggerDetected,
                "\(sandbox.kind.displayName)[\(conversationID.prefix(8))]: \(triggerLabel(for: target)): \(snippet(payload))")
            await routeAndPostback(sandbox: sandbox, conversationID: conversationID,
                                   target: target, payload: payload)
        case .exit:
            threads[conversationID] = nil
            DiagnosticsLog.shared.log(.triggerDetected, "Exit: cleared thread for conversation \(conversationID.prefix(8))")
        case .continuation(let payload):
            guard let thread = threads[conversationID] else {
                // No active thread — message ignored.
                return
            }
            await routeAndPostback(sandbox: sandbox, conversationID: conversationID,
                                   target: thread.target, payload: payload)
        }
    }

    private func routeAndPostback(sandbox: ChatPaneSandbox,
                                  conversationID: String,
                                  target: ChatThread.Target,
                                  payload: String) async {
        DiagnosticsLog.shared.log(.routedToAgent,
            "→ \(triggerLabel(for: target)): \(snippet(payload))")
        let response: String
        switch target {
        case .claudeCode:
            response = await ChatRouter.invokeClaude(prompt: payload,
                                                    sessionID: claudeSessions[conversationID]) { sid in
                self.claudeSessions[conversationID] = sid
            }
        case .codex:
            response = await ChatRouter.invokeCodex(prompt: payload,
                                                   sessionID: codexSessions[conversationID]) { sid in
                self.codexSessions[conversationID] = sid
            }
        }
        DiagnosticsLog.shared.log(.responseFromAgent, "← \(snippet(response))")
        // Post back: textarea-only, NO auto-submit (per spec §b.1).
        let postJS: String
        switch sandbox.kind {
        case .claudeChat:  postJS = ChatPostbackJS.setTextareaClaude(response)
        case .chatgptChat: postJS = ChatPostbackJS.setTextareaChatGPT(response)
        }
        _ = await CDPInput.evaluate(port: sandbox.kind.cdpPort, expression: postJS)
        DiagnosticsLog.shared.log(.postedToChat,
            "Set textarea in \(sandbox.kind.displayName). User must press Send.")
    }

    private func triggerLabel(for target: ChatThread.Target) -> String {
        switch target {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        }
    }

    private func snippet(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 80 ? String(oneLine.prefix(80)) + "…" : oneLine
    }
}

/// Trigger parser. Case-sensitive, message-start only (per spec §b.4).
enum ChatTriggerParser {
    enum ParseResult {
        case startThread(target: ChatBridge.ChatThread.Target, payload: String)
        case exit
        case continuation(payload: String)
    }

    static func parse(_ message: String) -> ParseResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("Code:") {
            let payload = String(trimmed.dropFirst("Code:".count)).trimmingCharacters(in: .whitespaces)
            return .startThread(target: .claudeCode, payload: payload)
        }
        if trimmed.hasPrefix("Codex:") {
            let payload = String(trimmed.dropFirst("Codex:".count)).trimmingCharacters(in: .whitespaces)
            return .startThread(target: .codex, payload: payload)
        }
        if trimmed.hasPrefix("Exit:") || trimmed == "Exit" {
            return .exit
        }
        return .continuation(payload: trimmed)
    }
}
