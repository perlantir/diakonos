import Foundation
import AppKit

/// v1.7 ChatBridge — polling shell + three-mode postback orchestrator.
///
/// Postback modes (per chat pane, via `PostbackMode`):
///
///   - `.manual`: scrape user-authored messages → trigger → dispatch
///     → DOM-stash response and show in-chat banner; user reviews and
///     presses Send. **Never** scrapes assistant messages for triggers
///     (DOM attribution + selector).
///
///   - `.autoSend`: same as Manual plus Diakonos clicks the Send
///     button after a ~300 ms settle so React's onChange fires before
///     submit. Assistant replies STILL do not route — they're
///     assistant-authored, selector ignores them.
///
///   - `.fullAuto`: the autonomous loop. Bridge ALSO scrapes
///     assistant-authored last messages. A leading `Code:` / `Codex:`
///     / `Exit:` from the assistant routes a new turn. Guarded by:
///       (a) per-conversation first-route confirm (reused);
///       (b) per-conversation max-turns counter (Preferences.fullAutoMaxTurns,
///           default 10) — pauses the loop and reverts to `.manual`;
///       (d) red "AUTO N/MAX" chip + always-visible Stop button in
///           the pane header.
///
/// Browser-pane content is structurally excluded: only chat-kind
/// sandboxes register with the bridge.
@MainActor
final class ChatBridge {

    static let shared = ChatBridge()

    private var sandboxes: [ObjectIdentifier: ChatPaneSandbox] = [:]
    private var pollingTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Per-conversation active thread.
    private var threads: [String: Thread] = [:]
    /// Stable per-message dedupe by ID instead of v1.5's text hashing.
    /// One slot for user-message ID, one for assistant-message ID
    /// (FullAuto scrapes both).
    private var lastSeenUserID:      [ObjectIdentifier: String] = [:]
    private var lastSeenAssistantID: [ObjectIdentifier: String] = [:]
    /// Per-conversation: claude / codex session IDs for --resume.
    private var claudeSessions: [String: String] = [:]
    private var codexSessions: [String: String] = [:]
    /// User pressed "Always" on a per-conversation first-route confirm.
    private var skipConfirmInConversation: Set<String> = []
    /// In-flight confirm modal guard so multiple polls don't stack.
    private var awaitingConfirmInConversation: Set<String> = []
    /// Per-sandbox live providers for routing + postback mode.
    private var modeForSandbox:     [ObjectIdentifier: () -> PaneMode] = [:]
    private var postbackForSandbox: [ObjectIdentifier: () -> PostbackMode] = [:]
    private var slotIDForSandbox:   [ObjectIdentifier: UUID] = [:]
    /// Per-conversation Full Auto state (turn count + stop flag).
    private var autoTurnCount: [String: Int] = [:]
    private var stopRequested: Set<String> = []

    struct Thread {
        let target: TriggerDetector.RouteTarget
        let conversationID: String
        let snapshot: RouteSnapshot
    }

    // MARK: - Registration

    /// Register a chat sandbox. `modeProvider` returns the slot's
    /// routing role (`.soloChat` vs `.coordinator`). `postbackProvider`
    /// returns the postback mode (`.manual`/`.autoSend`/`.fullAuto`).
    /// `slotID` lets the bridge call back to flip the pane's postback
    /// to `.manual` on Stop/max-turns.
    func register(sandbox: ChatPaneSandbox,
                  slotID: UUID,
                  modeProvider: @escaping () -> PaneMode,
                  postbackProvider: @escaping () -> PostbackMode) {
        let key = ObjectIdentifier(sandbox)
        if sandboxes[key] != nil { return }
        sandboxes[key] = sandbox
        modeForSandbox[key] = modeProvider
        postbackForSandbox[key] = postbackProvider
        slotIDForSandbox[key] = slotID
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
        postbackForSandbox[key] = nil
        slotIDForSandbox[key] = nil
        DiagnosticsLog.shared.log(.info, "unregistered \(sandbox.kind.displayName)")
    }

    // MARK: - Routing-badge lookup

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
    /// Live FullAuto status for the header chip (turn count + max).
    func autoStatus(forSlotPosition position: PaneSlotPosition,
                    layout: WorkspaceLayout) -> (turn: Int, max: Int, active: Bool) {
        let prefs = Preferences()
        // Find sandbox by slot id via slotIDForSandbox map.
        guard let slot = layout.slot(at: position),
              let key = slotIDForSandbox.first(where: { $0.value == slot.id })?.key,
              let sandbox = sandboxes[key],
              let convo = sandbox.conversationID else {
            return (0, prefs.fullAutoMaxTurns, false)
        }
        let postback = postbackForSandbox[key]?() ?? .manual
        let active = postback == .fullAuto && threads[convo] != nil
        return (autoTurnCount[convo] ?? 0, prefs.fullAutoMaxTurns, active)
    }

    // MARK: - Stop button

    /// Halt any Full Auto loop for the conversation tied to the slot
    /// and demote the slot's postback to `.manual`. Posts a system
    /// notification so a banner can surface in the pane.
    /// Returns within ~1s by setting an in-memory flag the next poll
    /// checks; in-flight subprocess completes but the loop won't
    /// schedule another turn.
    func stopAutoLoop(slotID: UUID, layout: WorkspaceLayout) {
        // Find the conversation for this slot.
        guard let (sandboxKey, sandbox) = sandboxes.first(where: {
            slotIDForSandbox[$0.key] == slotID
        }) else { return }
        if let convo = sandbox.conversationID {
            stopRequested.insert(convo)
            autoTurnCount[convo] = 0
            threads[convo] = nil
            SessionEventLog.append(.init(
                timestamp: Date(), kind: .routeClosed, routeID: UUID(),
                conversationID: convo, state: .closed,
                detail: "user pressed Stop — auto-loop halted"
            ))
        }
        // Demote to Manual.
        layout.setPostback(slotID, postback: .manual)
        DiagnosticsLog.shared.log(.info, "Stop pressed — \(sandbox.kind.displayName) returned to Manual")
        NotificationCenter.default.post(
            name: .diakonosAutoStopped,
            object: ["slotID": slotID.uuidString, "sandbox": sandbox.kind.displayName]
        )
        _ = sandboxKey
    }

    // MARK: - Polling

    private func poll(sandbox: ChatPaneSandbox) async {
        let key = ObjectIdentifier(sandbox)
        guard let modeProvider = modeForSandbox[key],
              let postbackProvider = postbackForSandbox[key] else { return }
        let mode = modeProvider()
        let postback = postbackProvider()
        guard sandbox.state == .running, let convo = sandbox.conversationID else { return }

        // Only .coordinator routes. .soloChat sandboxes are polled for
        // URL tracking but never trigger.
        if mode != .coordinator { return }

        // 1) Always scrape the latest user message.
        if let (msgID, msg) = await scrapeLatestMessage(sandbox: sandbox, fromAssistant: false),
           lastSeenUserID[key] != "\(convo)|\(msgID)" {
            lastSeenUserID[key] = "\(convo)|\(msgID)"
            await handle(sandbox: sandbox, conversationID: convo, message: msg,
                         postbackMode: postback, source: .user)
        }

        // 2) In FullAuto, additionally scrape assistant messages.
        // The autonomous-loop opt-in. Bridge sees assistant Code:/Codex:/Exit:
        // and routes a new turn — bounded by max-turns + Stop button.
        if postback == .fullAuto, !stopRequested.contains(convo) {
            if let (msgID, msg) = await scrapeLatestMessage(sandbox: sandbox, fromAssistant: true),
               lastSeenAssistantID[key] != "\(convo)|\(msgID)" {
                lastSeenAssistantID[key] = "\(convo)|\(msgID)"
                await handle(sandbox: sandbox, conversationID: convo, message: msg,
                             postbackMode: postback, source: .assistant)
            }
        }
    }

    /// Per-message source. In FullAuto, both user AND assistant trigger;
    /// in other modes, ONLY user.
    private enum MessageSource { case user, assistant }

    private func scrapeLatestMessage(sandbox: ChatPaneSandbox,
                                     fromAssistant: Bool) async -> (id: String, text: String)? {
        let js: String
        switch (sandbox.kind, fromAssistant) {
        case (.claudeChat, false):  js = ChatPostbackJS.readLatestUserMessageClaude
        case (.claudeChat, true):   js = ChatPostbackJS.readLatestAssistantMessageClaude
        case (.chatgptChat, false): js = ChatPostbackJS.readLatestUserMessageChatGPT
        case (.chatgptChat, true):  js = ChatPostbackJS.readLatestAssistantMessageChatGPT
        }
        guard let raw = await CDPInput.evaluate(port: sandbox.kind.cdpPort, expression: js) else { return nil }
        let unquoted = unquoteJSON(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !unquoted.isEmpty, unquoted != "null" else { return nil }
        guard let sep = unquoted.range(of: "|||") else { return nil }
        let id = String(unquoted[..<sep.lowerBound])
        let text = String(unquoted[sep.upperBound...])
        if text.isEmpty { return nil }
        return (id, text)
    }

    private func handle(sandbox: ChatPaneSandbox,
                        conversationID: String,
                        message: String,
                        postbackMode: PostbackMode,
                        source: MessageSource) async {
        let activeTarget = threads[conversationID]?.target
        guard let trigger = TriggerDetector.classify(rawUserMessage: message,
                                                     activeThreadTarget: activeTarget) else {
            return
        }
        switch trigger {
        case .exit:
            threads[conversationID] = nil
            autoTurnCount[conversationID] = 0
            DiagnosticsLog.shared.log(.triggerDetected, "Exit: cleared thread for \(conversationID.prefix(8))")
            SessionEventLog.append(.init(timestamp: Date(),
                                         kind: .routeClosed,
                                         routeID: UUID(),
                                         conversationID: conversationID,
                                         state: .closed,
                                         detail: "\(source == .user ? "user" : "assistant") typed Exit:"))
            return

        case .startThread(let target, let payload):
            // First-route confirm. Even in .fullAuto mode, a NEW
            // conversation still triggers the per-conv opt-in modal —
            // safeguard (a). Once "Always" is pressed, future routes
            // skip the modal.
            if !skipConfirmInConversation.contains(conversationID) {
                guard await showFirstRouteConfirm(target: target,
                                                  conversationID: conversationID,
                                                  payloadPreview: payload,
                                                  postbackMode: postbackMode) else {
                    return
                }
            }
            let snapshot = makeSnapshot(target: target,
                                        projectRoot: resolvedProjectRoot(forTarget: target))
            threads[conversationID] = Thread(target: target,
                                             conversationID: conversationID,
                                             snapshot: snapshot)
            await runRoute(sandbox: sandbox, conversationID: conversationID,
                           target: target, payload: payload, postback: postbackMode)

        case .continueThread(let payload):
            guard let thread = threads[conversationID] else { return }
            await runRoute(sandbox: sandbox, conversationID: conversationID,
                           target: thread.target, payload: payload, postback: postbackMode)
        }
    }

    private func runRoute(sandbox: ChatPaneSandbox,
                          conversationID: String,
                          target: TriggerDetector.RouteTarget,
                          payload: String,
                          postback: PostbackMode) async {
        // Max-turns check (FullAuto only).
        if postback == .fullAuto {
            let count = autoTurnCount[conversationID] ?? 0
            let maxTurns = Preferences().fullAutoMaxTurns
            if count >= maxTurns {
                DiagnosticsLog.shared.log(.info, "FullAuto max-turns \(maxTurns) reached — pausing loop")
                threads[conversationID] = nil
                if let slotID = slotIDForSandbox[ObjectIdentifier(sandbox)] {
                    NotificationCenter.default.post(
                        name: .diakonosAutoMaxTurns,
                        object: ["slotID": slotID.uuidString, "max": maxTurns]
                    )
                }
                return
            }
            autoTurnCount[conversationID] = count + 1
        }
        if stopRequested.contains(conversationID) {
            stopRequested.remove(conversationID)
            return
        }

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

        // Postback — three modes:
        if stopRequested.contains(conversationID) {
            stopRequested.remove(conversationID)
            return
        }
        await postReply(sandbox: sandbox, body: result.body, postback: postback)
        sm.transition(to: .draftPostedToChat)
        sm.transition(to: .awaitingUserReview)
        DiagnosticsLog.shared.log(.postedToChat,
            "Set textarea in \(sandbox.kind.displayName) (\(postback.displayName)).")
    }

    /// Three-mode postback.
    private func postReply(sandbox: ChatPaneSandbox,
                           body: String,
                           postback: PostbackMode) async {
        // Manual / AutoSend / FullAuto all set the textarea first via
        // `ChatPostbackJS.setTextarea*`. In v1.7 Part B, the JS also
        // shows an in-chat banner above the composer when the user had
        // typed something — see `ChatPostbackJS` updates.
        let setJS: String
        switch sandbox.kind {
        case .claudeChat:  setJS = ChatPostbackJS.setTextareaClaude(body)
        case .chatgptChat: setJS = ChatPostbackJS.setTextareaChatGPT(body)
        }
        _ = await CDPInput.evaluate(port: sandbox.kind.cdpPort, expression: setJS)
        if !postback.sendsAutomatically { return }

        // Auto-send: ~300ms wait so React's onChange settles, then click Send.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let clickJS: String
        switch sandbox.kind {
        case .claudeChat:  clickJS = ChatPostbackJS.clickSendClaude
        case .chatgptChat: clickJS = ChatPostbackJS.clickSendChatGPT
        }
        _ = await CDPInput.evaluate(port: sandbox.kind.cdpPort, expression: clickJS)
        DiagnosticsLog.shared.log(.info, "auto-Send fired (\(postback.displayName))")
    }

    // MARK: - Helpers

    private func resolvedProjectRoot(forTarget target: TriggerDetector.RouteTarget) -> String {
        let prefs = Preferences()
        switch target {
        case .claudeCode: return prefs.claudeCodeResolvedCwd
        case .codex:      return prefs.codexResolvedCwd
        }
    }

    private func roleCard(forTarget target: TriggerDetector.RouteTarget,
                          surface: ChatPaneSandbox.Kind) -> RoleCard {
        let id: String
        switch target {
        case .claudeCode: id = BuiltInRoleCardID.implementerClaudeCode.rawValue
        case .codex:      id = BuiltInRoleCardID.implementerCodex.rawValue
        }
        if let latest = RoleCardStore.shared.latestVersion(forId: id) { return latest }
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

    private func showFirstRouteConfirm(target: TriggerDetector.RouteTarget,
                                       conversationID: String,
                                       payloadPreview: String,
                                       postbackMode: PostbackMode) async -> Bool {
        if awaitingConfirmInConversation.contains(conversationID) { return false }
        awaitingConfirmInConversation.insert(conversationID)
        defer { awaitingConfirmInConversation.remove(conversationID) }

        let alert = NSAlert()
        alert.messageText = "Route to \(target.displayName)?"
        var info = """
        Diakonos detected a `\(target == .claudeCode ? "Code" : "Codex"):` trigger in this conversation.

        Task: \(snippet(payloadPreview))

        The task will run in your chosen project folder. Choose Always to skip this prompt for the rest of this conversation.
        """
        if postbackMode == .fullAuto {
            info += "\n\n⚠️ Pane is in Full Auto. Even with Always, the per-conversation opt-in still applies — but assistant Code:/Codex: triggers will route automatically once enabled."
        }
        alert.informativeText = info
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

extension Notification.Name {
    /// Fires when the Full Auto loop hits the max-turns limit. Object
    /// is `["slotID": "<uuid>", "max": Int]`.
    static let diakonosAutoMaxTurns = Notification.Name("DiakonosAutoMaxTurns")
    /// Fires when the Stop button halts an auto loop.
    static let diakonosAutoStopped  = Notification.Name("DiakonosAutoStopped")
}
