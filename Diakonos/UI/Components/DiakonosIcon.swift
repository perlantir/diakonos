import SwiftUI

/// SwiftUI-rendered facsimile of the Diakonos app icon (see `design/screens/09-assets-naming.png`).
/// A rounded indigo square with a white sandboxed-cube glyph. Used for the About page and
/// AppIcon asset generation. Phase-4 stand-in until a designer asset replaces it.
struct DiakonosIcon: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x3B82F6),
                            Color(hex: 0x1E3A8A)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Stylized hex/cube glyph
            Image(systemName: "cube")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
                .frame(width: size * 0.55, height: size * 0.55)
                .shadow(color: .black.opacity(0.25), radius: size * 0.03, y: size * 0.02)
        }
        .frame(width: size, height: size)
    }
}
