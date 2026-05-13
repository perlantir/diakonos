import SwiftUI

/// Generic pane wrapper. Bodies render only when `viewState == .normal`;
/// when minimized, only the header is visible. Maximize is handled at the
/// WorkspaceView level — a single slot gets full-bleed, others are hidden.
struct PaneView<Body: View, ActionChip: View, MenuContent: View>: View {
    let title: String
    let iconSystemName: String
    let accent: Color
    let state: SandboxState
    let viewState: PaneSlotViewState
    let isMaximized: Bool

    var onMinimize: () -> Void = {}
    var onMaximizeToggle: () -> Void = {}
    var onClose: () -> Void = {}
    @ViewBuilder var menuContent: () -> MenuContent
    @ViewBuilder var actionChip: () -> ActionChip
    @ViewBuilder var content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: title,
                iconSystemName: iconSystemName,
                accent: accent,
                state: state,
                viewState: viewState,
                isMaximized: isMaximized,
                onMinimize: onMinimize,
                onMaximizeToggle: onMaximizeToggle,
                onClose: onClose,
                menuContent: menuContent,
                actionChip: actionChip
            )

            if viewState != .minimized {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

/// Initializing placeholder body. Only used by the Browser pane while cua boots.
struct InitializingPaneBody: View {
    let iconSystemName: String
    let accent: Color
    let title: String
    var message: String = "Sandbox is initializing…"

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s4) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: iconSystemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(spacing: DesignTokens.Spacing.s1) {
                Text(title)
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
