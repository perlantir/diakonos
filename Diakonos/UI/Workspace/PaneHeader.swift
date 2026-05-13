import SwiftUI

/// Header bar at the top of every pane. The optional `actionChip` slot lets a
/// pane mount an interactive label/button — the Claude Code pane uses it to show
/// the selected project folder.
struct PaneHeader<ActionChip: View>: View {
    let kind: PaneKind
    let state: SandboxState
    @ViewBuilder var actionChip: () -> ActionChip

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Image(systemName: kind.iconSystemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kind.accent)
                .frame(width: 18, height: 18)

            Text(kind.title)
                .font(Typography.text(Typography.Size.sm, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)

            Circle()
                .fill(state.indicatorColor)
                .frame(width: 6, height: 6)

            actionChip()

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                IconButton(systemImage: "ellipsis", size: 22, iconSize: 12)
                IconButton(systemImage: "minus", size: 22, iconSize: 11)
                IconButton(systemImage: "arrow.up.left.and.arrow.down.right", size: 22, iconSize: 10)
                IconButton(systemImage: "xmark", size: 22, iconSize: 10)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s3)
        .padding(.vertical, DesignTokens.Spacing.s2)
        .frame(height: 36)
        .background(
            DesignTokens.Palette.bgElevated
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DesignTokens.Palette.borderSoft)
                        .frame(height: 1)
                }
        )
    }
}

extension PaneHeader where ActionChip == EmptyView {
    init(kind: PaneKind, state: SandboxState) {
        self.kind = kind
        self.state = state
        self.actionChip = { EmptyView() }
    }
}
