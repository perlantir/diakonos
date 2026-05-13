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
    /// Terminal slots exist; otherwise just the kind's default label.
    func title(for slot: PaneSlot) -> String {
        switch slot.kind {
        case .empty:
            return "Choose pane type"
        case .terminal:
            let terminals = slots.filter { $0.kind == .terminal }
            if terminals.count <= 1 { return "Terminal" }
            if let n = terminals.firstIndex(of: slot) {
                return n == 0 ? "Terminal" : "Terminal \(n + 1)"
            }
            return "Terminal"
        case .claudeCode:
            return "Claude Code"
        case .browser:
            return "Browser"
        }
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
