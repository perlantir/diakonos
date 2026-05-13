import SwiftUI

struct IconButton: View {
    let systemImage: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 14
    var action: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(
                    hovering
                        ? DesignTokens.Palette.textPrimary
                        : DesignTokens.Palette.textSecondary
                )
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                        .fill(hovering ? DesignTokens.Palette.bgElevated : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
