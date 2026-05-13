import Foundation

/// One of the four physical pane positions in the 2x2 grid.
enum PaneSlotPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
}

/// What the user has assigned to this slot. Empty means the slot is in the
/// "Choose pane type" placeholder state (screen 07).
enum PaneSlotKind: String, Codable, CaseIterable, Identifiable {
    case empty
    case terminal
    case claudeCode
    case codex
    case browser

    var id: String { rawValue }

    /// Label for the empty-pane dropdown.
    var dropdownLabel: String {
        switch self {
        case .empty:      return "Empty"
        case .terminal:   return "Terminal"
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .browser:    return "Browser"
        }
    }

    /// SF Symbol for the empty-pane dropdown.
    var iconSystemName: String {
        switch self {
        case .empty:      return "square.dashed"
        case .terminal:   return "terminal.fill"
        case .claudeCode: return "sparkles"
        case .codex:      return "chevron.left.forwardslash.chevron.right"
        case .browser:    return "globe"
        }
    }
}

enum PaneSlotViewState: String, Codable {
    case normal
    case minimized
}

/// User-state for a single slot. Persisted to UserDefaults as JSON.
struct PaneSlot: Identifiable, Codable, Equatable {
    let id: UUID
    let position: PaneSlotPosition
    var kind: PaneSlotKind
    var viewState: PaneSlotViewState

    init(id: UUID = UUID(), position: PaneSlotPosition, kind: PaneSlotKind, viewState: PaneSlotViewState = .normal) {
        self.id = id
        self.position = position
        self.kind = kind
        self.viewState = viewState
    }
}
