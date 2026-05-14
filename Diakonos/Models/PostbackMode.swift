import Foundation

/// How Diakonos hands a routed reply back to the chat pane. Stored per
/// PaneSlot (so two chat panes can be in different modes).
///
///   - `.manual` (default): Diakonos sets the chat textarea and stops.
///     The user reviews and presses Send. **No assistant message ever
///     fires a route** (DOM attribution guarantees this — the scrape
///     selector matches user-authored nodes only).
///
///   - `.autoSend`: Diakonos sets the textarea AND clicks the Send
///     button (via CDP DOM injection, with an explicit ~300ms wait
///     between insertText and click so React's onChange settles).
///     The coordinator's reply is still assistant-authored, so it
///     **still does not route**. This mode is for "I trust the chain
///     but want full visibility of each turn."
///
///   - `.fullAuto`: `.autoSend` plus the bridge ALSO scrapes
///     assistant-authored last messages. A leading `Code:` / `Codex:`
///     / `Exit:` from the assistant routes a new turn — this is the
///     **autonomous loop**. Gated by all of:
///       (a) the first-route confirm modal (still required, even in
///           this mode, per new conversation);
///       (b) a per-conversation max-turns counter (Preferences,
///           default 10) that pauses the loop and reverts to Manual;
///       (d) a persistent red "🔴 AUTO — turn N/MAX" chip + ever-
///           present Stop button (halts within ~1s, returns to Manual).
///     Letter (c) of the spec was Coordinator-reply scraping; it's
///     covered by (a)/(b)/(d). Letter labels mirror Nick's brief.
enum PostbackMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case autoSend
    case fullAuto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:   return "Manual"
        case .autoSend: return "Auto-send"
        case .fullAuto: return "Full Auto"
        }
    }

    /// Diakonos clicks Send after posting the response?
    var sendsAutomatically: Bool {
        self != .manual
    }

    /// The bridge scrapes assistant messages for triggers too?
    /// Only `.fullAuto`. Everything else is user-only — the DOM
    /// attribution v1.7 §5 guarantee.
    var scrapesAssistantMessages: Bool {
        self == .fullAuto
    }
}
