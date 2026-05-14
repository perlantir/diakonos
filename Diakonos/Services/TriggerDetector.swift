import Foundation

/// User-message trigger detection + safety filtering. v1.7 hardened
/// version of v1.5's ad-hoc ChatTriggerParser.
///
/// SAFETY (the headline of v1.7 §5):
/// 1. **Only user-authored DOM nodes are scraped.** The CDP JS in
///    `ChatPostbackJS.readLatestUserMessageClaude` / `…ChatGPT`
///    matches `[data-message-author-role="user"]` / `[data-testid=
///    "user-message"]` — never assistant nodes. Empirically verified
///    against synthetic DOM 2026-05-14: an assistant message
///    containing the string "Code: …" does NOT register.
/// 2. **Message-start only.** Pattern `^(Code|Codex|Exit):` anchored
///    at the start of the (trimmed) message.
/// 3. **No quotes/code blocks.** If the message is fenced in ```…``` or
///    quoted with leading `>`, ignore.
/// 4. **Escape with backslash.** `\Code:` does NOT fire.
///
/// 5. **First route per conversation gates on a UI confirm modal**
///    (handled by the caller — `ChatBridge` shows NSAlert before
///    invoking `RouteDispatcher`).
enum TriggerDetector {

    enum Trigger: Equatable {
        case startThread(target: RouteTarget, payload: String)
        case continueThread(payload: String)
        case exit
    }

    enum RouteTarget: String, Equatable {
        case claudeCode
        case codex

        var displayName: String {
            self == .claudeCode ? "Claude Code" : "Codex"
        }
    }

    /// Inspect a freshly-scraped user-message string and decide whether
    /// any trigger fires. Returns `nil` if the message is plain content.
    /// `activeThreadTarget` is the target currently routed for the
    /// conversation (or nil if no thread is open).
    static func classify(rawUserMessage raw: String,
                         activeThreadTarget: RouteTarget?) -> Trigger? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // (3) Quote/code-block guard. The whole message in fences or
        // every line prefixed with `>` means the user is quoting, not
        // commanding.
        if isFencedOrQuoted(trimmed) { return nil }

        // (4) Backslash escape. `\Code: x` is literally about Code:.
        if trimmed.hasPrefix("\\Code:") || trimmed.hasPrefix("\\Codex:") || trimmed.hasPrefix("\\Exit:") {
            return nil
        }

        // (2) Message-start trigger words.
        if trimmed.hasPrefix("Code:") {
            let payload = String(trimmed.dropFirst("Code:".count))
                .trimmingCharacters(in: .whitespaces)
            return .startThread(target: .claudeCode, payload: payload)
        }
        if trimmed.hasPrefix("Codex:") {
            let payload = String(trimmed.dropFirst("Codex:".count))
                .trimmingCharacters(in: .whitespaces)
            return .startThread(target: .codex, payload: payload)
        }
        if trimmed.hasPrefix("Exit:") || trimmed == "Exit" {
            return .exit
        }

        // No trigger. If a thread is active and the message is plain
        // text, treat as continuation.
        if activeThreadTarget != nil {
            return .continueThread(payload: trimmed)
        }
        return nil
    }

    /// True when the entire message is inside ```fenced``` or every
    /// non-empty line is a `>` block-quote. Conservative — partial
    /// fences (open ``` with no close) are NOT treated as fenced;
    /// would let the user accidentally bypass the guard.
    private static func isFencedOrQuoted(_ text: String) -> Bool {
        // Block quote: every non-blank line starts with `>`.
        let lines = text.split(separator: "\n").map { String($0) }
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !nonEmpty.isEmpty,
           nonEmpty.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }) {
            return true
        }
        // Fenced: starts with ``` and contains a matching ``` later.
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("```") {
            let rest = t.dropFirst(3)
            if rest.contains("```") { return true }
        }
        return false
    }
}
