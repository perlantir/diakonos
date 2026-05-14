import Foundation

/// One of the physical pane positions in the workspace grid. v1.6 added
/// `.topMid` and `.bottomMid` to support a 3-column (6-pane) layout. The
/// default mode is still 4-pane (`.topLeft`, `.topRight`, `.bottomLeft`,
/// `.bottomRight`); when the user toggles to 6-pane, `.topMid` and
/// `.bottomMid` slots become visible. The raw values are stable so on-disk
/// persistence (UserDefaults) survives mode toggles.
enum PaneSlotPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft, topMid, topRight, bottomLeft, bottomMid, bottomRight

    var id: String { rawValue }

    /// The 4-pane reading order: TL, TR, BL, BR.
    static var fourPaneOrder: [PaneSlotPosition] {
        [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
    /// The 6-pane reading order: TL, TM, TR, BL, BM, BR. Cmd+N maps to
    /// position N-1 in this list when 6-pane mode is active.
    static var sixPaneOrder: [PaneSlotPosition] {
        [.topLeft, .topMid, .topRight, .bottomLeft, .bottomMid, .bottomRight]
    }
    /// True when this position is only visible in 6-pane mode.
    var isSixPaneOnly: Bool {
        self == .topMid || self == .bottomMid
    }
}

/// Number of visible panes in the workspace. Default 4. Toggled via the
/// toolbar 4/6 control. Codable raw values let the enum live directly in
/// UserDefaults.
enum WorkspacePaneCount: Int, Codable, CaseIterable {
    case four = 4
    case six  = 6

    var toggled: WorkspacePaneCount {
        self == .four ? .six : .four
    }
    var positions: [PaneSlotPosition] {
        self == .four ? PaneSlotPosition.fourPaneOrder : PaneSlotPosition.sixPaneOrder
    }
}

/// What the user has assigned to this slot. Empty means the slot is in the
/// "Choose pane type" placeholder state (screen 07).
enum PaneSlotKind: String, Codable, CaseIterable, Identifiable {
    case empty
    case terminal
    case claudeCode
    case codex
    case claudeChat
    case chatgptChat
    case browser

    var id: String { rawValue }

    /// User-selectable kinds for the EmptyPaneBody dropdown. Derived from
    /// `allCases` so adding a new case automatically surfaces it in the UI
    /// — this kills the "half-landed audit" bug class that bit v1.3 and
    /// v1.5. Order is the stable display order; not alphabetical.
    static var userSelectable: [PaneSlotKind] {
        let order: [PaneSlotKind] = [.terminal, .claudeCode, .codex, .browser, .claudeChat, .chatgptChat]
        // Defensive: if a new case is added to PaneSlotKind but not to the
        // order array, append it at the end so it still shows up.
        let known = Set(order)
        let missing = allCases.filter { $0 != .empty && !known.contains($0) }
        #if DEBUG
        assert(missing.isEmpty,
               "PaneSlotKind case(s) missing from userSelectable order: \(missing). Add to PaneSlotKind.userSelectable.")
        #endif
        return order + missing
    }

    var dropdownLabel: String {
        switch self {
        case .empty:       return "Empty"
        case .terminal:    return "Terminal"
        case .claudeCode:  return "Claude Code"
        case .codex:       return "Codex"
        case .claudeChat:  return "Claude Chat"
        case .chatgptChat: return "ChatGPT"
        case .browser:     return "Browser"
        }
    }

    var iconSystemName: String {
        switch self {
        case .empty:       return "square.dashed"
        case .terminal:    return "terminal.fill"
        case .claudeCode:  return "sparkles"
        case .codex:       return "chevron.left.forwardslash.chevron.right"
        case .claudeChat:  return "bubble.left.fill"
        case .chatgptChat: return "bubble.left.and.bubble.right.fill"
        case .browser:     return "globe"
        }
    }

    /// True for kinds that present a sandboxed Chromium-backed chat/web view.
    /// Distinguishes "chat" panes (claude.ai / chatgpt.com) from the generic
    /// Browser pane.
    var isChatKind: Bool {
        self == .claudeChat || self == .chatgptChat
    }
}

enum PaneSlotViewState: String, Codable {
    case normal
    case minimized
}

struct PaneSlot: Identifiable, Codable, Equatable {
    let id: UUID
    let position: PaneSlotPosition
    var kind: PaneSlotKind
    var viewState: PaneSlotViewState
    /// v1.7: routing role. `nil` means "use `PaneMode.defaultMode(for: kind)`."
    /// Stored separately so reassigning the slot's kind also resets to the
    /// new kind's default mode unless the user has explicitly chosen one.
    var mode: PaneMode?
    /// v1.7 Part B: postback mode. Manual = default = no auto-Send +
    /// no assistant trigger scrape. AutoSend = auto-press Send.
    /// FullAuto = autonomous loop with safeguards.
    var postback: PostbackMode?

    init(id: UUID = UUID(),
         position: PaneSlotPosition,
         kind: PaneSlotKind,
         viewState: PaneSlotViewState = .normal,
         mode: PaneMode? = nil,
         postback: PostbackMode? = nil) {
        self.id = id
        self.position = position
        self.kind = kind
        self.viewState = viewState
        self.mode = mode
        self.postback = postback
    }

    /// Resolved mode: explicit `mode` if set, else the kind's default.
    var resolvedMode: PaneMode {
        mode ?? PaneMode.defaultMode(for: kind)
    }

    /// Resolved postback mode. Always defaults to `.manual` — the
    /// safe baseline. User opts into `.autoSend` / `.fullAuto` via
    /// the header chip.
    var resolvedPostback: PostbackMode {
        postback ?? .manual
    }
}
