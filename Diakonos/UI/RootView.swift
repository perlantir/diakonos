import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            DesignTokens.Palette.bgApp
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.s3) {
                Text("Diakonos")
                    .font(Typography.display(Typography.Size.xxxl, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)

                Text("Sandboxed AI agent workspace")
                    .font(Typography.text(Typography.Size.md))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
        }
        .frame(minWidth: 1024, minHeight: 640)
    }
}

#Preview {
    RootView()
}
