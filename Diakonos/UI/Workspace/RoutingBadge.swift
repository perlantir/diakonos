import SwiftUI

/// Header chip shown on a chat pane when ChatBridge has an active routing
/// thread for that pane's current conversation. Refreshes every 2 s by
/// re-querying ChatBridge.
struct RoutingBadge: View {
    let slot: PaneSlot
    @State private var target: ChatBridge.ChatThread.Target? = nil

    var body: some View {
        Group {
            if let target {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(label(for: target))
                        .font(Typography.text(Typography.Size.xs, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(color(for: target))
                )
            } else {
                EmptyView()
            }
        }
        .task(id: slot.id) {
            while !Task.isCancelled {
                target = await currentTarget()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @MainActor
    private func currentTarget() async -> ChatBridge.ChatThread.Target? {
        // The badge needs the sandbox instance to query ChatBridge.
        // We can't cleanly reach it from here without coupling; instead,
        // ChatBridge exposes a position-keyed lookup.
        return ChatBridge.shared.activeTarget(forSlotPosition: slot.position)
    }

    private func label(for target: ChatBridge.ChatThread.Target) -> String {
        switch target {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        }
    }

    private func color(for target: ChatBridge.ChatThread.Target) -> Color {
        switch target {
        case .claudeCode: return Color(hex: 0x8B5CF6)
        case .codex:      return Color(hex: 0x10A37F)
        }
    }
}
