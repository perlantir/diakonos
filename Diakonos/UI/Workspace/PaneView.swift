import SwiftUI

struct PaneView<Body: View>: View {
    let kind: PaneKind
    let state: SandboxState
    @ViewBuilder let content: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(kind: kind, state: state)
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

/// Placeholder body used by Phase 1 — pane is "initializing" with icon + title.
struct InitializingPaneBody: View {
    let kind: PaneKind

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
                Text("Sandbox is initializing…")
                    .font(Typography.text(Typography.Size.sm))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Palette.bgSurface)
    }
}
