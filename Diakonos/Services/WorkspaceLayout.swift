import SwiftUI
import Combine

/// Owns the user-facing state of which pane lives in which slot, plus
/// minimize/maximize and **pane count** (4 or 6 — new in v1.6). Persists to
/// UserDefaults as JSON under a v2 schema; reads v1 (4-pane only) for
/// backward compatibility.
@MainActor
final class WorkspaceLayout: ObservableObject {

    /// v1 schema (pre-v1.6): [PaneSlot] of length 4 in fourPaneOrder.
    static let userDefaultsKeyV1 = "workspaceLayout.slots.v1"
    /// v2 schema (v1.6+): { paneCount: 4|6, slots: [PaneSlot of length 6] }.
    static let userDefaultsKeyV2 = "workspaceLayout.v2"

    /// All six slots, always. `paneCount` controls which are rendered. This
    /// lets 6→4→6 toggles preserve what was in `.topMid` / `.bottomMid`.
    @Published var slots: [PaneSlot] = WorkspaceLayout.defaultSlots()
    @Published var paneCount: WorkspacePaneCount = .four
    @Published var maximizedSlotID: UUID? = nil

    /// In-memory counter bumped by the 3-dot "Reset shell" / "Restart" menu
    /// items. Folded into the pane view's `spawnIdentity` so that triggering
    /// a reset forces SwiftUI to respawn the underlying process. Not persisted.
    @Published private(set) var respawnVersion: [UUID: Int] = [:]

    func bumpRespawn(_ id: UUID) {
        respawnVersion[id, default: 0] += 1
    }

    func respawnTag(_ id: UUID) -> String {
        "v\(respawnVersion[id] ?? 0)"
    }

    init() {
        // Prefer v2 if present, else migrate v1.
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKeyV2),
           let decoded = try? JSONDecoder().decode(PersistedV2.self, from: data),
           decoded.slots.count == 6 {
            slots = decoded.slots
            paneCount = decoded.paneCount
        } else if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKeyV1),
                  let decoded = try? JSONDecoder().decode([PaneSlot].self, from: data),
                  decoded.count == 4 {
            // Migrate: keep TL/TR/BL/BR; append empty .topMid + .bottomMid.
            var migrated: [PaneSlot] = []
            for pos in PaneSlotPosition.sixPaneOrder {
                if let existing = decoded.first(where: { $0.position == pos }) {
                    migrated.append(existing)
                } else {
                    migrated.append(PaneSlot(position: pos, kind: .empty))
                }
            }
            slots = migrated
            paneCount = .four
            persist()
        }
    }

    // MARK: - Mutations

    /// Slots visible in the current paneCount, in reading order.
    var visibleSlots: [PaneSlot] {
        let positions = paneCount.positions
        return positions.compactMap { pos in slots.first(where: { $0.position == pos }) }
    }

    func slot(at position: PaneSlotPosition) -> PaneSlot? {
        slots.first(where: { $0.position == position })
    }

    func slot(withID id: UUID) -> PaneSlot? {
        slots.first(where: { $0.id == id })
    }

    func update(_ id: UUID, _ mutation: (inout PaneSlot) -> Void) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        var slot = slots[idx]
        mutation(&slot)
        slots[idx] = slot
        persist()
    }

    func assign(_ id: UUID, kind: PaneSlotKind) {
        update(id) { $0.kind = kind; $0.viewState = .normal }
    }

    func close(_ id: UUID) {
        update(id) { $0.kind = .empty; $0.viewState = .normal }
        if maximizedSlotID == id { maximizedSlotID = nil }
    }

    func minimize(_ id: UUID) {
        update(id) { $0.viewState = .minimized }
    }

    func restore(_ id: UUID) {
        update(id) { $0.viewState = .normal }
    }

    func toggleMaximize(_ id: UUID) {
        maximizedSlotID = (maximizedSlotID == id) ? nil : id
    }

    // MARK: - Pane-count toggle

    /// Switch between 4-pane (2×2) and 6-pane (2×3) layouts. When switching
    /// 6 → 4 with non-empty `.topMid` / `.bottomMid` slots, the caller
    /// should first prompt the user (`hiddenSlotsOnFourPane()` describes
    /// what will be hidden). State for hidden slots is preserved; toggling
    /// back to 6 restores them.
    func setPaneCount(_ newCount: WorkspacePaneCount) {
        guard newCount != paneCount else { return }
        paneCount = newCount
        // If we're shrinking and the maximized slot is now hidden, clear it.
        if newCount == .four,
           let maxID = maximizedSlotID,
           let s = slot(withID: maxID),
           s.position.isSixPaneOnly {
            maximizedSlotID = nil
        }
        persist()
    }

    /// Returns the non-empty `.topMid` / `.bottomMid` slots that would
    /// disappear from view on a 6 → 4 toggle. Used by the toolbar to
    /// decide whether to show a confirm dialog.
    func slotsHiddenByFourPaneToggle() -> [PaneSlot] {
        return slots.filter { $0.position.isSixPaneOnly && $0.kind != .empty }
    }

    // MARK: - Titles

    /// Auto-numbered title: "Terminal", "Terminal 2", … when multiple
    /// Terminal slots exist; same auto-numbering for Codex when multiple
    /// Codex slots exist; otherwise just the kind's default label.
    func title(for slot: PaneSlot) -> String {
        switch slot.kind {
        case .empty:       return "Choose pane type"
        case .terminal:    return autoNumberedTitle(for: slot, kind: .terminal, base: "Terminal")
        case .claudeCode:  return "Claude Code"
        case .codex:       return autoNumberedTitle(for: slot, kind: .codex, base: "Codex")
        case .claudeChat:  return "Claude Chat"
        case .chatgptChat: return "ChatGPT"
        case .browser:     return "Browser"
        }
    }

    private func autoNumberedTitle(for slot: PaneSlot, kind: PaneSlotKind, base: String) -> String {
        let peers = slots.filter { $0.kind == kind }
        if peers.count <= 1 { return base }
        if let n = peers.firstIndex(of: slot) {
            return n == 0 ? base : "\(base) \(n + 1)"
        }
        return base
    }

    // MARK: - Persistence

    /// v2 wire schema.
    private struct PersistedV2: Codable {
        var paneCount: WorkspacePaneCount
        var slots: [PaneSlot]
    }

    private func persist() {
        let payload = PersistedV2(paneCount: paneCount, slots: slots)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKeyV2)
        }
    }

    /// Defaults: 6 slots seeded with reasonable starting kinds for the
    /// 4-pane positions, and empty for the 6-pane-only positions.
    static func defaultSlots() -> [PaneSlot] {
        [
            PaneSlot(position: .topLeft,     kind: .terminal),
            PaneSlot(position: .topMid,      kind: .empty),
            PaneSlot(position: .topRight,    kind: .claudeCode),
            PaneSlot(position: .bottomLeft,  kind: .terminal),
            PaneSlot(position: .bottomMid,   kind: .empty),
            PaneSlot(position: .bottomRight, kind: .browser),
        ]
    }
}
