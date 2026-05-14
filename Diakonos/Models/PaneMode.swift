import Foundation

/// How a pane routes — distinct from `PaneSlotKind` (which is WHAT process
/// runs). Orthogonal axis added in v1.7:
///
///   - `.soloChat`: chat pane stands alone; Diakonos NEVER routes. Trigger
///     phrases like `Code:` are ignored. Safe default for chat panes.
///   - `.coordinator`: chat pane drives implementer panes. User-authored
///     `Code:` / `Codex:` triggers fire the route state machine.
///   - `.implementer`: terminal pane runs `claude` / `codex` as the
///     routed target. Fixed for `.claudeCode` and `.codex` slot kinds.
///   - `.browserDriver`: the Browser pane. Diakonos never routes from
///     it (browser content is untrusted; see "Browser content
///     prompt-injection guardrail" in `docs/v1.7-spec.md`).
///
/// Modes are user-editable only for chat-kind panes. The chip in the pane
/// header surfaces and toggles between `.soloChat` and `.coordinator`.
enum PaneMode: String, Codable, CaseIterable, Identifiable {
    case soloChat
    case coordinator
    case implementer
    case browserDriver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soloChat:      return "Solo Chat"
        case .coordinator:   return "Coordinator"
        case .implementer:   return "Implementer"
        case .browserDriver: return "Browser"
        }
    }

    /// Routes user-authored triggers to local implementers?
    var routesTriggers: Bool {
        self == .coordinator
    }

    /// Whether the user can toggle this mode for a given `PaneSlotKind`.
    /// Chat kinds (claudeChat / chatgptChat) toggle between `.soloChat` and
    /// `.coordinator`. Everything else has a fixed mode.
    static func userToggleable(forKind kind: PaneSlotKind) -> [PaneMode] {
        switch kind {
        case .claudeChat, .chatgptChat: return [.soloChat, .coordinator]
        case .claudeCode, .codex:       return [.implementer]
        case .browser:                  return [.browserDriver]
        case .terminal, .empty:         return []
        }
    }

    /// Default mode for a freshly assigned slot of `kind`. New chat panes
    /// start in `.soloChat` (no routing) — opt-in design per v1.7.
    static func defaultMode(for kind: PaneSlotKind) -> PaneMode {
        switch kind {
        case .claudeChat, .chatgptChat: return .soloChat
        case .claudeCode, .codex:       return .implementer
        case .browser:                  return .browserDriver
        case .terminal, .empty:         return .soloChat
        }
    }
}
