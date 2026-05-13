import SwiftUI

struct StatusIndicator: View {
    let state: SandboxState
    var showsLabel: Bool = true

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            ZStack {
                Circle()
                    .fill(state.indicatorColor.opacity(0.25))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(state.indicatorColor)
                    .frame(width: 8, height: 8)
            }

            if showsLabel {
                Text(state.label)
                    .font(Typography.text(Typography.Size.sm, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s3)
        .padding(.vertical, DesignTokens.Spacing.s1 + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(DesignTokens.Palette.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
                )
        )
    }
}
