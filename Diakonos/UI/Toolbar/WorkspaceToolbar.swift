import SwiftUI

struct WorkspaceToolbar: View {
    var onSettings: () -> Void = {}
    var onFullscreen: () -> Void = {}

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s3) {
            HStack(spacing: DesignTokens.Spacing.s2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DesignTokens.Palette.accentPrimary)
                        .frame(width: 18, height: 18)
                    Image(systemName: "cube.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Diakonos")
                    .font(Typography.text(Typography.Size.sm, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
            }

            Spacer()

            HStack(spacing: 2) {
                IconButton(systemImage: "gearshape", action: onSettings)
                IconButton(systemImage: "arrow.up.left.and.arrow.down.right", action: onFullscreen)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s5)
        .padding(.vertical, DesignTokens.Spacing.s3)
        .frame(height: 56)
        .background(
            DesignTokens.Palette.bgApp
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DesignTokens.Palette.borderSoft)
                        .frame(height: 1)
                }
        )
    }
}
