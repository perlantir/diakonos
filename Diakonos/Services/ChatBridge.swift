import Foundation
import AppKit

/// v1.7 ChatBridge — thin polling shell on top of `TriggerDetector` /
/// `RouteStateMachine` / `RouteDispatcher`. The old v1.5/v1.6 routing
/// logic (single ~200-line file) is replaced by composition.
///
/// Pipeline per poll:
///   1. CDP scrape latest **user-authored** message via the hardened
///      `ChatPostbackJS` selectors (returns "id|||text").
///   2. Dedupe by stable per-message ID (not text hash).
///   3. `TriggerDetector.classify` decides whether a route fires,
///      enforcing all v1.7 §5 safety rules (no quotes/code-blocks,
///      no `\Code:` escape, only user-authored — DOM attribution
///      already enforced by the selector).
///   4. If first route per conversation, prompt NSAlert with
///      Confirm / Cancel / Always (skip future prompts in this conversation).
///   5. Compose envelope + 5-layer context, dispatch via
///      `RouteDispatcher`, log every state transition into the
///      per-session JSONL.
///   6. Post the reply back into the chat textarea (NO auto-submit).
///
/// Only **chat-kind** sandboxes (`.claudeChat`, `.chatgptChat`) register
/// with the bridge. Browser-pane content never reaches the trigger
/// detector — that's the prompt-injection guardrail.
@MainActor
final class ChatBridge {

    static let shared = ChatBridge()

    private var sandboxes: [ObjectIdentifier: ChatPaneSandbox] = [:]
    private var pollingTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Per-conversation active thread. Carries target + role-card snapshot.
    private var threads: [String: Thread] = [:]
    /// Stable per-message dedupe by ID instead of v1.5's text hashing.
    private var lastSeenMessageID: [ObjectIdentifier: String] = [:]
    /// Per-conversation: claude / codex session IDs for --resume continuity.
    private var claudeSessions: [String: String] = [:]
    private var codexSessions: [String: String] = [:]
    /// Per-conversation: user has pressed "Always" in the first-route
    /// confirm modal, suppress further prompts in this conversation.
    /// In-memory only for v1.7; persistence is v1.8.
    private var skipConfirmInConversation: Set<String> = []
    /// In-flight confirm modal guard so multiple polls don't stack alerts.
    private var awaitingConfirmInConversation: Set<String> = []
    /// Per-conversation: PaneMode lookup for the registered sandbox. So
    /// .soloChat sandboxes can be polled (URL tracking, conversation ID)
    /// but never trigger routing.
    private var modeForSandbox: [ObjectIdentifier: () -> PaneMode] = [:]

    struct Thread {
        let target: TriggerDetector.RouteTarget
        let conversationID: String
        let snapshot: RouteSnapshot
    }

    // MARK: - Registration

    /// Registers a chat sandbox with the bridge. `modeProvider` is queried
    /// on each poll so the bridge sees live mode changes from the header
    /// chip without needing explicit re-registration.
    func register(sandbox: ChatPaneSandbox,
                  modeProvider: @escaping () -> PaneMode) {
        let key = ObjectIdentifier(sandbox)
        if sandboxes[key] != nil { return }
        sandboxes[key] = sandbox
        modeForSandbox[key] = modeProvider
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
        modeForSandbox[key] = nil
        DiagnosticsLog.shared.log(.info, "unregistered \(sandbox.kind.displayName)")
    }

    // MARK: - Routing-badge lookup (for RoutingBadge view)

    func activeTarget(for sandbox: ChatPaneSandbox) -> TriggerDetector.RouteTarget? {
        guard let convo = sandbox.conversationID else { return nil }
        return threads[convo]?.target
    }
    func activeTarget(forSlotPosition position: PaneSlotPosition) -> TriggerDetector.RouteTarget? {
        for sandbox in sandboxes.values {
            guard let convo = sandbox.conversationID,
                  let t = threads[convo]?.target else { continue }
            return t
        }
        return nil
    }

    // MARK: - Polling

    private func poll(sandbox: ChatPaneSandbox) async {
        let key = ObjectIdentifier(sandbox)
        // Mode gate: .soloChat sandboxes are polled (URL tracking) but
        // never route. .coordinator is the only mode that fires.
        guard let modeProvider = modeForSandbox[key] else { return }
        let mode = modeProvider()
        guard sandbox.state == .running, let convo = sandbox.conversationID else { return }

        if mode != .coordinator {
            return
        }

        // Scrape "id|||text" using the hardened user-only selectors.
        let js: String
        switch sandbox.kind {
        case .claudeChat:  js = ChatPostbackJS.readLatestUserMessageClaude
        case .chatgptChat: js = ChatPostbackJS.readLatestUserMessageChatGPT
        }
        guard let raw = await CDPInput.evaluate(port: sandbox.kind.cdpPort, expression: js) else { return }
        let unquoted = unquoteJSON(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !unquoted.isEmpty, unquoted != "null" else {
            if unquoted == "null" {
                DiagnosticsLog.shared.log(.selectorMissing,
                    "\(sandbox.kind.displayName): no user message found (DOM may have changed)")
            }
            return
        }
        // Split "id|||text"
        guard let sep = unquoted.range(of: "|||") else { return }
        let messageID = String(unquoted[..<sep.lowerBound])
        let message = String(unquoted[sep.upperBound...])
        guard !message.isEmpty else { return }

        let dedupeKey = "\(convo)|\(messageID)"
        guard lastSeenMessageID[key] != dedupeKey else { return }
        lastSeenMessageID[key] = dedupeKey

        await handle(sandbox: sandbox, conversationID: convo, message: message, messageID: messageID)
    }

    private func handle(sandbox: ChatPaneSandbox,
                        conversationID: String,
                        message: String,
                        messageID: String) async {
        let activeTarget = threads[conversationID]?.target
        guard let trigger = TriggerDetector.classify(rawUserMessage: message,
                                                     activeThreadTarget: activeTarget) else {
            return
        }
        switch trigger {
        case .exit:
            threads[conversationID] = nil
            DiagnosticsLog.shared.log(.triggerDetected, "Exit: cleared thread for \(conversationID.prefix(8))")
            SessionEventLog.append(.init(timestamp: Date(),
                                         kind: .routeClosed,
                                         routeID: UUID(),
                                         conversationID: conversationID,
                                         state: .closed,
                                         detail: "user typed Exit:"))
            return

        case .startThread(let target, let payload):
            // First route per conversation: confirm modal, unless user
            // has previously pressed "Always" in this conversation.
            if !skipConfirmInConversation.contains(conversationID) {
                guard await showFirstRouteConfirm(target: target,
                                                  conversationID: conversationID,
                                                  payloadPreview: payload) else {
                    return
                }
            }
            // Snapshot the role-card version + protocol version at thread
            // creation. Settings edits after this point do NOT affect the
            // running thread.
            let snapshot = makeSnapshot(target: target, projectRoot: resolvedProjectRoot(forTarget: target))
            threads[conversationID] = Thread(target: target,
                                             conversationID: conversationID,
                                             snapshot: snapshot)
            await runRoute(sandbox: sandbox, conversationID: conversationID,
                           target: target, payload: payload)

        case .continueThread(let payload):
            guard let thread = threads[conversationID] else { return }
            await runRoute(sandbox: sandbox, conversationID: conversationID,
                           target: thread.target, payload: payload)
        }
    }

    private func runRoute(sandbox: ChatPaneSandbox,
                          conversationID: String,
                          target: TriggerDetector.RouteTarget,
                          payload: String) async {
        let projectRoot = resolvedProjectRoot(forTarget: target)
        let project = AGENTSReader.read(rootPath: projectRoot)
        let card = roleCard(forTarget: target, surface: sandbox.kind)
        let envelope = RouteEnvelope(
            routeID: UUID(),
            sourcePane: "chat:\(sandbox.kind.rawIdentifier)",
            targetPane: "\(target.rawValue):terminal",
            projectRoot: projectRoot,
            contextHash: project.contextHash,
            roleCardID: card.id,
            roleCardVersion: card.version.string,
            protocolVersion: RoutingContext.protocolVersion,
            conversationID: conversationID,
            task: payload,
            createdAt: Date()
        )
        let snapshot = threads[conversationID]?.snapshot ?? makeSnapshot(target: target,
                                                                          projectRoot: projectRoot)
        let sm = RouteStateMachine(routeID: envelope.routeID,
                                   envelope: envelope,
                                   snapshot: snapshot)
        sm.onTransition = { prev, next in
            SessionEventLog.append(.init(
                timestamp: Date(),
                kind: Self.eventKind(for: next),
                routeID: envelope.routeID,
                conversationID: conversationID,
                state: next,
                detail: "\(prev) → \(next)"
            ))
        }
        sm.transition(to: .routeDraftDetected)
        sm.transition(to: .awaitingDispatch)
        DiagnosticsLog.shared.log(.routedToAgent,
            "→ \(target.displayName): \(snippet(payload))  [\(projectRoot)]")

        sm.transition(to: .sentToTarget)
        sm.transition(to: .targetRunning)
        let preamble = RoutingContext.compose(envelope: envelope,
                                              roleCardBody: card.body,
                                              project: project)
        let result: RouteDispatcher.Result
        switch target {
        case .claudeCode:
            result = await RouteDispatcher.dispatchClaude(envelope: envelope,
                                                         preamble: preamble,
                                                         sessionID: claudeSessions[conversationID])
            if let s = result.sessionID { claudeSessions[conversationID] = s }
        case .codex:
            result = await RouteDispatcher.dispatchCodex(envelope: envelope,
                                                        preamble: preamble,
                                                        sessionID: codexSessions[conversationID])
            if let s = result.sessionID { codexSessions[conversationID] = s }
        }
        sm.transition(to: .replyCaptured)
        DiagnosticsLog.shared.log(.responseFromAgent, "← \(snippet(result.body))")
        // Postback (no auto-submit).
        let postJS: String
        switch sandbox.kind {
        case .claudeChat:  postJS = ChatPostbackJS.setTextareaClaude(result.body)
        case .chatgptChat: postJS = ChatPostbackJS.setTextareaChatGPT(result.body)
        }
        _ = await CDPInput.evaluate(port: sandbox.kind.cdpPort, expression: postJS)
        sm.transition(to: .draftPostedToChat)
        sm.transition(to: .awaitingUserReview)
        DiagnosticsLog.shared.log(.postedToChat,
            "Set textarea in \(sandbox.kind.displayName). User must press Send.")
    }

    // MARK: - Helpers

    /// Reach back to the user's chosen project folder. v1.7 Part A
    /// reads from `Preferences.claudeCodeResolvedCwd` (Claude) /
    /// `Preferences.codexResolvedCwd` (Codex). Part B will let the
    /// coordinator panel target a specific implementer pane.
    private func resolvedProjectRoot(forTarget target: TriggerDetector.RouteTarget) -> String {
        // Access Preferences through a side-channel — ChatBridge is a
        // singleton, no env injection. We honour the user-set folder
        // (set via the pane header chip + persisted in UserDefaults).
        let prefs = Preferences()
        switch target {
        case .claudeCode: return prefs.claudeCodeResolvedCwd
        case .codex:      return prefs.codexResolvedCwd
        }
    }

    private func roleCard(forTarget target: TriggerDetector.RouteTarget,
                          surface: ChatPaneSandbox.Kind) -> RoleCard {
        // For routing, the role card describes the IMPLEMENTER target.
        let id: String
        switch target {
        case .claudeCode: id = BuiltInRoleCardID.implementerClaudeCode.rawValue
        case .codex:      id = BuiltInRoleCardID.implementerCodex.rawValue
        }
        if let latest = RoleCardStore.shared.latestVersion(forId: id) { return latest }
        // Fallback if disk is empty (shouldn't happen after seedFromBundle).
        return RoleCard(id: id, version: .initial, body: "")
    }

    private func makeSnapshot(target: TriggerDetector.RouteTarget,
                              projectRoot: String) -> RouteSnapshot {
        let id: String
        switch target {
        case .claudeCode: id = BuiltInRoleCardID.implementerClaudeCode.rawValue
        case .codex:      id = BuiltInRoleCardID.implementerCodex.rawValue
        }
        let card = RoleCardStore.shared.latestVersion(forId: id)
        let project = AGENTSReader.read(rootPath: projectRoot)
        return RouteSnapshot(
            roleCardID: id,
            roleCardVersion: card?.version.string ?? "0.0.0",
            protocolVersion: RoutingContext.protocolVersion,
            projectContextHash: project.contextHash,
            createdAt: Date()
        )
    }

    /// Show window-modal confirm for the FIRST route in a conversation.
    /// Buttons: Confirm (one-shot), Cancel (drop), Always (skip future).
    private func showFirstRouteConfirm(target: TriggerDetector.RouteTarget,
                                       conversationID: String,
                                       payloadPreview: String) async -> Bool {
        if awaitingConfirmInConversation.contains(conversationID) { return false }
        awaitingConfirmInConversation.insert(conversationID)
        defer { awaitingConfirmInConversation.remove(conversationID) }

        let alert = NSAlert()
        alert.messageText = "Route to \(target.displayName)?"
        alert.informativeText = """
        Diakonos detected a `\(target == .claudeCode ? "Code" : "Codex"):` trigger in this conversation.

        Task: \(snippet(payloadPreview))

        The task will run in your chosen project folder. Choose Always to skip this prompt for the rest of this conversation.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Route")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Always (this conversation)")
        let resp = await MainActor.run { alert.runModal() }
        switch resp {
        case .alertFirstButtonReturn:
            return true
        case .alertThirdButtonReturn:
            skipConfirmInConversation.insert(conversationID)
            return true
        default:
            return false
        }
    }

    private static func eventKind(for state: RouteState) -> SessionEventLog.Event.Kind {
        switch state {
        case .idle, .routeDraftDetected:              return .routeDetected
        case .awaitingDispatch, .sentToTarget:        return .routeSent
        case .targetRunning:                          return .routeRunning
        case .replyCaptured:                          return .routeReply
        case .draftPostedToChat, .awaitingUserReview: return .routePosted
        case .closed:                                 return .routeClosed
        }
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

    private func snippet(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 80 ? String(oneLine.prefix(80)) + "…" : oneLine
    }
}
