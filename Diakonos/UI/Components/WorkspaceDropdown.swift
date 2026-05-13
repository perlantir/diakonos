import SwiftUI

struct WorkspaceDropdown: View {
    let title: String
    @State private var hovering = false

    var body: some View {
        Button { } label: {
            HStack(spacing: DesignTokens.Spacing.s2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DesignTokens.Palette.accentPrimary)
                        .frame(width: 18, height: 18)
                    Image(systemName: "cube.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(title)
                    .font(Typography.text(Typography.Size.sm, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.s3)
            .padding(.vertical, DesignTokens.Spacing.s1 + 2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(hovering
                          ? DesignTokens.Palette.bgElevated
                          : DesignTokens.Palette.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                            .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
