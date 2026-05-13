import SwiftUI
import Combine

/// Owns the user-facing state of which pane lives in which slot, plus
/// minimize/maximize state. Persists to UserDefaults as JSON.
@MainActor
final class WorkspaceLayout: ObservableObject {

    static let userDefaultsKey = "workspaceLayout.slots.v1"

    @Published var slots: [PaneSlot] = WorkspaceLayout.defaultSlots()
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
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([PaneSlot].self, from: data),
           decoded.count == 4 {
            slots = decoded
        }
    }

    // MARK: - Mutations

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
        // "Close" tears down and swaps the slot to .empty.
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

    /// Auto-numbered title: "Terminal", "Terminal 2", … when multiple
    /// Terminal slots exist; same auto-numbering for Codex when multiple
    /// Codex slots exist; otherwise just the kind's default label.
    func title(for slot: PaneSlot) -> String {
        switch slot.kind {
        case .empty:
            return "Choose pane type"
        case .terminal:
            return autoNumberedTitle(for: slot, kind: .terminal, base: "Terminal")
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return autoNumberedTitle(for: slot, kind: .codex, base: "Codex")
        case .browser:
            return "Browser"
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

    private func persist() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func defaultSlots() -> [PaneSlot] {
        [
            PaneSlot(position: .topLeft, kind: .terminal),
            PaneSlot(position: .topRight, kind: .claudeCode),
            PaneSlot(position: .bottomLeft, kind: .terminal),
            PaneSlot(position: .bottomRight, kind: .browser)
        ]
    }
}
