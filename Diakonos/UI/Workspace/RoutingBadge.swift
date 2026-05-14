import SwiftUI

/// Header chip shown on a chat pane when ChatBridge has an active routing
/// thread for that pane's current conversation. Refreshes every 2s.
///
/// v1.7: `ChatThread.Target` → `TriggerDetector.RouteTarget`.
struct RoutingBadge: View {
    let slot: PaneSlot
    @State private var target: TriggerDetector.RouteTarget? = nil

    var body: some View {
        Group {
            if let target {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(target.displayName)
                        .font(Typography.text(Typography.Size.xs, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(color(for: target)))
            } else {
                EmptyView()
            }
        }
        .task(id: slot.id) {
            while !Task.isCancelled {
                target = ChatBridge.shared.activeTarget(forSlotPosition: slot.position)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func color(for target: TriggerDetector.RouteTarget) -> Color {
        switch target {
        case .claudeCode: return Color(hex: 0x8B5CF6)
        case .codex:      return Color(hex: 0x10A37F)
        }
    }
}
