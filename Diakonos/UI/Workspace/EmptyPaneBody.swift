import SwiftUI

/// Empty pane placeholder per `design/screens/07-empty-pane.png`. Shows a
/// dropdown the user clicks to assign a kind (Terminal / Claude Code /
/// Browser) to this slot.
struct EmptyPaneBody: View {
    let slotID: UUID
    @ObservedObject var layout: WorkspaceLayout

    @State private var hovering = false

    private let kinds: [PaneSlotKind] = [.terminal, .claudeCode, .browser]

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        DesignTokens.Palette.borderStrong,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textMuted)
            }

            VStack(spacing: DesignTokens.Spacing.s1) {
                Text("Empty pane")
                    .font(Typography.text(Typography.Size.lg, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Text("Pick what runs here.")
                    .font(Typography.text(Typography.Size.sm))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            Menu {
                ForEach(kinds) { kind in
                    Button {
                        layout.assign(slotID, kind: kind)
                    } label: {
                        Label(kind.dropdownLabel, systemImage: kind.iconSystemName)
                    }
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.s2) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Choose pane type")
                        .font(Typography.text(Typography.Size.sm, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.s4)
                .padding(.vertical, DesignTokens.Spacing.s2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(hovering
                              ? DesignTokens.Palette.accentHover
                              : DesignTokens.Palette.accentPrimary)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { hovering = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Palette.bgSurface)
    }
}
