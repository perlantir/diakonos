import SwiftUI
import AppKit

enum DesignTokens {

    // MARK: - Color

    enum Palette {
        // Background
        static let bgApp           = dyn(light: 0xF5F6FA, dark: 0x0B1220)
        static let bgSurface       = dyn(light: 0xFFFFFF, dark: 0x111827)
        static let bgElevated      = dyn(light: 0xFCFCFD, dark: 0x161E2E)
        static let bgDarkSurface   = Color(hex: 0x111827)

        // Text
        static let textPrimary     = dyn(light: 0x111827, dark: 0xF9FAFB)
        static let textSecondary   = dyn(light: 0x667085, dark: 0xC4CADA)
        static let textMuted       = dyn(light: 0x98A2B3, dark: 0x8995AC)
        static let textInverse     = dyn(light: 0xF9FAFB, dark: 0x111827)

        // Border
        static let borderSoft      = dyn(light: 0xE8EDF5, dark: 0x222C42)
        static let borderDefault   = dyn(light: 0xE5E7EB, dark: 0x2A364F)
        static let borderStrong    = dyn(light: 0xD0D5DD, dark: 0x3A4663)

        // Accent
        static let accentPrimary   = Color(hex: 0x2F6BFF)
        static let accentHover     = Color(hex: 0x2556D8)
        static let accentSoft      = dyn(light: 0xE9F0FF, dark: 0x1E2A52)

        // Status
        static let statusHealthy   = Color(hex: 0x22C55E)
        static let statusWarning   = Color(hex: 0xF59E0B)
        static let statusError     = Color(hex: 0xEF4444)
        static let statusStopped   = Color(hex: 0x94A3B8)

        // Hermes
        static let hermesOrange    = Color(hex: 0xF59E0B)
        static let hermesOrangeSoft = dyn(light: 0xFFF7ED, dark: 0x3A2A14)
    }

    // MARK: - Spacing

    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s10: CGFloat = 40
        static let s12: CGFloat = 48
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Shadow

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let sm = Shadow(color: Color(red: 16/255, green: 24/255, blue: 40/255, opacity: 0.06),
                               radius: 2, x: 0, y: 1)
        static let md = Shadow(color: Color(red: 16/255, green: 24/255, blue: 40/255, opacity: 0.08),
                               radius: 24, x: 0, y: 8)
        static let lg = Shadow(color: Color(red: 16/255, green: 24/255, blue: 40/255, opacity: 0.12),
                               radius: 40, x: 0, y: 16)
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Returns a Color that resolves to `light` in Light appearance and `dark` in Dark appearance.
fileprivate func dyn(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
        let value = isDark ? dark : light
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >>  8) & 0xFF) / 255.0
        let b = CGFloat( value        & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    })
}

// MARK: - View modifiers for shadow tokens

extension View {
    func diakonosShadow(_ shadow: DesignTokens.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
