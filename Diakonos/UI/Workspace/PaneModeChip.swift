import SwiftUI
import AppKit

/// Header chip showing the pane's current routing mode. For chat-kind
/// panes (.claudeChat / .chatgptChat) the chip is a menu — the user
/// toggles between `.soloChat` (no routing) and `.coordinator` (Diakonos
/// will route their `Code:`/`Codex:` triggers).
///
/// For non-chat kinds the chip is non-interactive (terminal/code panes
/// have a fixed mode by definition — see `PaneMode.userToggleable`).
struct PaneModeChip: View {
    let slot: PaneSlot
    @ObservedObject var layout: WorkspaceLayout

    var body: some View {
        if PaneMode.userToggleable(forKind: slot.kind).count > 1 {
            menuChip
        } else if slot.kind == .claudeChat || slot.kind == .chatgptChat
                  || slot.kind == .claudeCode || slot.kind == .codex
                  || slot.kind == .browser {
            staticChip
        } else {
            EmptyView()
        }
    }

    private var resolved: PaneMode { slot.resolvedMode }

    private var staticChip: some View {
        chipBody(label: resolved.displayName, color: color(for: resolved),
                 interactive: false)
    }

    private var menuChip: some View {
        Menu {
            ForEach(PaneMode.userToggleable(forKind: slot.kind)) { mode in
                Button(action: { layout.setMode(slot.id, mode: mode) }) {
                    HStack {
                        Text(mode.displayName)
                        if mode == resolved { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            chipBody(label: resolved.displayName, color: color(for: resolved),
                     interactive: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Routing mode. Coordinator routes your `Code:`/`Codex:` triggers; Solo Chat ignores them.")
    }

    @ViewBuilder
    private func chipBody(label: String, color: Color, interactive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon(for: resolved))
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(Typography.text(Typography.Size.xs, weight: .semibold))
            if interactive {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color))
    }

    private func icon(for mode: PaneMode) -> String {
        switch mode {
        case .soloChat:      return "bubble.left"
        case .coordinator:   return "arrow.triangle.branch"
        case .implementer:   return "wrench.and.screwdriver"
        case .browserDriver: return "globe"
        }
    }

    private func color(for mode: PaneMode) -> Color {
        switch mode {
        case .soloChat:      return Color(hex: 0x6B7280) // neutral gray
        case .coordinator:   return Color(hex: 0x2F6BFF) // accent blue
        case .implementer:   return Color(hex: 0x8B5CF6) // claude purple
        case .browserDriver: return Color(hex: 0x10A37F) // green
        }
    }
}
