import SwiftUI

struct PaneView<Body: View, ActionChip: View>: View {
    let kind: PaneKind
    let state: SandboxState
    @ViewBuilder var actionChip: () -> ActionChip
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(kind: kind, state: state, actionChip: actionChip)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignTokens.Palette.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Palette.borderSoft, lineWidth: 1)
        )
        .diakonosShadow(.sm)
    }
}

extension PaneView where ActionChip == EmptyView {
    init(kind: PaneKind, state: SandboxState, @ViewBuilder content: @escaping () -> Body) {
        self.kind = kind
        self.state = state
        self.actionChip = { EmptyView() }
        self.content = content
    }
}

/// Placeholder body. v1.1 only the Browser pane uses this (while its sandbox boots).
struct InitializingPaneBody: View {
    let kind: PaneKind
    var message: String = "Sandbox is initializing…"

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s4) {
            ZStack {
                Circle()
                    .fill(kind.accent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: kind.iconSystemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(kind.accent)
            }

            VStack(spacing: DesignTokens.Spacing.s1) {
                Text(kind.title)
                    .font(Typography.text(Typography.Size.lg, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Text(message)
                    .font(Typography.text(Typography.Size.sm))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Palette.bgSurface)
    }
}
