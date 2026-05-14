# Diakonos routing protocol

How the chat coordinator (claude.ai / chatgpt.com) hands work to a
local implementer (Claude Code / Codex), what shape the call takes,
and the safety invariants the protocol promises.

This document is the human-readable accompaniment to
`Diakonos/Services/`'s routing code. Anything here that contradicts
the code is a doc bug; ship a patch.

---

## 1. Pieces

| Component | File | What it does |
|---|---|---|
| TriggerDetector | `Services/TriggerDetector.swift` | Decides whether a scraped message text triggers a route. Enforces escape / quote / code-block / message-start rules. |
| ChatPostbackJS | `Services/ChatPostbackJS.swift` | The JavaScript that runs inside the sandbox Chromium: scrape user/assistant messages, set textarea, click Send, render the in-chat banner. |
| ChatBridge | `Services/ChatBridge.swift` | Polls each chat-pane sandbox at 3 Hz, calls the detector, runs the state machine, dispatches. Per-conversation thread state. |
| RouteStateMachine | `Services/RouteStateMachine.swift` | 9-state lifecycle per route. Logs each transition into the session event log. |
| RouteEnvelope | `Services/RouteEnvelope.swift` | Structured wrapper: route_id, source/target pane, project_root, context_hash, role-card version, etc. Sent as Markdown-with-YAML-frontmatter on stdin. |
| RoutingContext | `Services/RoutingContext.swift` | Composes the 5-layer context preamble (Protocol → Mode card → Prefs → Project → Session). |
| RouteDispatcher | `Services/RouteDispatcher.swift` | `Process.runWithCWD(cwd: projectRoot)` — sets the subprocess CWD. Calls `claude --print` / `codex exec`. |
| RoleCardStore | `Services/RoleCardStore.swift` | Versioned markdown role cards on disk. |
| SessionEventLog | `Services/SessionEventLog.swift` | Append-only JSONL per conversation. |
| ContextDoctor | `Services/ContextDoctor.swift` | Scans AGENTS.md / .diakonos/context.md / CLAUDE.md and warns about conflicts. |

## 2. Trigger semantics

Triggers fire only when **all** are true:

1. **DOM attribution.** The scraped element matches the *user-only*
   selector (`[data-message-author-role="user"]` /
   `[data-testid="user-message"]`).
   - **Exception:** `.fullAuto` postback mode ALSO scrapes the
     assistant-only selector. The user opted into the autonomous
     loop and accepts the risk.
2. **Message-start.** The trigger word is the trimmed prefix.
   "Tell me about Code: prefixes" does not fire.
3. **Not in a quote.** Every non-empty line of the message must NOT
   start with `>`. Block-quoted `> Code: x` does not fire.
4. **Not in a fenced code block.** A message that starts with
   ```` ``` ```` and contains another ```` ``` ```` later does not fire.
5. **Not backslash-escaped.** `\Code:` does not fire — lets users
   discuss the protocol literally.
6. **Per-conversation opt-in.** First trigger in any conversation
   pops an NSAlert: Confirm / Cancel / Always-for-this-conversation.
   Even in `.fullAuto` mode, the per-conversation modal still
   appears on a new conversation.

Empirically verified 2026-05-14: 11/11 string-level cases pass
(`/tmp/trigger_safety_test.swift`). 8/8 postback-mode cases pass
(`/tmp/postback_mode_test.swift`). DOM attribution verified
against the live container Chromium via a synthetic ChatGPT-like
DOM probe.

## 3. State machine

```
   idle
     │
     │  user/assistant message matches a trigger
     ▼
   routeDraftDetected
     │
     ▼
   awaitingDispatch
     │
     │  preamble composed
     ▼
   sentToTarget
     │
     ▼
   targetRunning           (claude --print / codex exec)
     │
     ▼
   replyCaptured
     │
     ▼
   draftPostedToChat       (textarea set; auto-Send in autoSend/fullAuto)
     │
     ▼
   awaitingUserReview
     │
     │  user clicks Send (or auto-Send fires)
     ▼
   closed
```

`closed` is reachable from any state on `Exit:` trigger, Stop button
press, or max-turns ceiling.

## 4. Envelope shape

```yaml
---
route_id: <UUID>
source_pane: chat:claudeChat
target_pane: claudeCode:terminal
project_root: /Users/perlantir/Projects/diakonos     # absolute path
context_hash: <sha256[12]>
role_card: implementer.claude-code
role_card_version: 1.0.0
protocol_version: "1"
conversation_id: <chat UUID>
created_at: 2026-05-14T17:38:53Z
---

## Reply contract

Reply with these sections, in this order:
1. Summary — 1-3 sentences of what you did.
2. Files touched — relative paths with one-line "why."
3. Commands run — shell commands you executed.
4. Tests — what you verified, what you didn't.
5. Risks — anything Diakonos's user should review before shipping.

Keep it under ~400 words unless the task genuinely demands more.
```

After the envelope: the literal `# Task` heading + the user's text
after `Code:` / `Codex:`.

## 5. CWD invariant

The subprocess runs with `currentDirectoryURL = URL(fileURLWithPath: projectRoot)`.
v1.5/v1.6 silently inherited Diakonos's launch CWD; v1.7
`RouteDispatcher.Process.runWithCWD` always sets it. Verified by
`CWDSelfTest` on every app launch (logs PASS/FAIL via NSLog).

## 6. Postback modes (v1.7 Part B)

| Mode | Textarea write | Send click | Assistant-trigger scrape |
|---|---|---|---|
| `.manual` (default) | Yes (with banner if user typed) | No | No |
| `.autoSend` | Yes | Yes (300ms after write so React settles) | No |
| `.fullAuto` | Yes | Yes | Yes — opt-in autonomous loop |

Full Auto safeguards (all enforced):
- **(a) First-route confirm** still required per conversation.
- **(b) Max-turns counter** (Preferences.fullAutoMaxTurns, default 10). On
  limit, loop pauses; pane demotes to `.manual`; notification posted.
- **(d) Visible red "AUTO N/MAX" chip + Stop button** in pane header.
- **(e) Stop button** sets an in-memory flag the next poll checks
  (≤1s after click); current in-flight subprocess completes; loop
  does not schedule another. Pane demoted to `.manual`.

## 7. Conversation IDs

`ChatPaneSandbox.extractConversationID(from:url:kind:)` parses the
last URL path segment for a UUID-shaped string. claude.ai → `/chat/<uuid>`,
chatgpt.com → `/c/<uuid>`. A new conversation = new ID = new state
machine, new first-route confirm, new turn counter, new session log
file.

## 8. Browser content guardrail

Browser-pane sandboxes never register with ChatBridge. Route detection
structurally cannot fire on browser content. The `diakonos-browser`
MCP tool descriptions in `Resources/mcp_browser.py` carry an explicit
UNTRUSTED warning. The `browser-driver@1.0.0` role card reinforces
this on the agent side.

## 9. Diagnostics tabs

- **In-memory ChatBridge events** (the existing v1.5 log).
- **Per-session JSONL log** at `~/Library/Application Support/Diakonos/Sessions/<conv-id>.jsonl`
  — read by `SessionEventLog.recentEvents`.
- **Context Doctor** — Settings → Diagnostics → "Check Context"
  surfaces conflicts between AGENTS.md / CLAUDE.md / .diakonos/context.md.

## 10. What can break

The selectors in `ChatPostbackJS` are the protocol's biggest single
fragility. claude.ai and chatgpt.com redesign without notice. When a
trigger stops firing, look at `DiagnosticsLog` for
`selectorMissing` entries, then update the selectors. v1.7 hardened
the selectors with fallback chains, but if all candidates miss, the
bridge silently does nothing.

Patch point: `ChatPostbackJS.readLatestUserMessage{Claude,ChatGPT}` and
`readLatestAssistantMessage{Claude,ChatGPT}` strings.
