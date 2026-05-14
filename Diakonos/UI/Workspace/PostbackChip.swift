import SwiftUI
import AppKit

/// Header chip for chat panes that toggles the **postback mode**
/// (Manual / Auto-send / Full Auto). Visible only on chat-kind panes;
/// hidden when the routing mode is `.soloChat` because there's no
/// reason to set postback when no routing happens.
///
/// Switching to Full Auto **does not** auto-bypass the per-conversation
/// first-route confirm modal (safeguard (a)).
struct PostbackChip: View {
    let slot: PaneSlot
    @ObservedObject var layout: WorkspaceLayout

    var body: some View {
        Menu {
            ForEach(PostbackMode.allCases) { mode in
                Button {
                    layout.setPostback(slot.id, postback: mode)
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if mode == slot.resolvedPostback { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon(for: slot.resolvedPostback))
                    .font(.system(size: 9, weight: .bold))
                Text(slot.resolvedPostback.displayName)
                    .font(Typography.text(Typography.Size.xs, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color(for: slot.resolvedPostback)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Postback mode. Manual = textarea only; Auto-send = +click Send; Full Auto = autonomous loop with safeguards.")
    }

    private func icon(for mode: PostbackMode) -> String {
        switch mode {
        case .manual:   return "hand.raised"
        case .autoSend: return "paperplane.fill"
        case .fullAuto: return "infinity"
        }
    }
    private func color(for mode: PostbackMode) -> Color {
        switch mode {
        case .manual:   return Color(hex: 0x6B7280)
        case .autoSend: return Color(hex: 0xF59E0B) // amber: heads-up
        case .fullAuto: return Color(hex: 0xDC2626) // red: dangerous
        }
    }
}

/// Red status chip + Stop button shown in the header during Full Auto.
/// "AUTO N/MAX" plus a one-click Stop that halts within ~1s and
/// demotes the pane to `.manual`. Visible only when slot is in
/// `.fullAuto` postback. The status chip pulls live turn count via
/// `ChatBridge.autoStatus`.
struct AutoStatusChip: View {
    let slot: PaneSlot
    @ObservedObject var layout: WorkspaceLayout
    @State private var status: (turn: Int, max: Int, active: Bool) = (0, 10, false)

    var body: some View {
        Group {
            if slot.resolvedPostback == .fullAuto {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: 0xDC2626)).frame(width: 6, height: 6)
                        Text("AUTO \(status.turn)/\(status.max)")
                            .font(Typography.mono(Typography.Size.xs, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: 0xDC2626))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .stroke(Color(hex: 0xDC2626), lineWidth: 1)
                            .background(Capsule().fill(Color(hex: 0xDC2626).opacity(0.08)))
                    )
                    Button {
                        ChatBridge.shared.stopAutoLoop(slotID: slot.id, layout: layout)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Stop")
                                .font(Typography.text(Typography.Size.xs, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: 0xDC2626)))
                    }
                    .buttonStyle(.plain)
                    .help("Halt the Full Auto loop. Demotes pane to Manual.")
                }
            }
        }
        .task(id: slot.id) {
            while !Task.isCancelled {
                if slot.resolvedPostback == .fullAuto {
                    status = ChatBridge.shared.autoStatus(forSlotPosition: slot.position, layout: layout)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 Hz for live count
            }
        }
    }
}
