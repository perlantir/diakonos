import SwiftUI

enum Typography {

    enum Size {
        static let xs: CGFloat   = 12
        static let sm: CGFloat   = 13
        static let md: CGFloat   = 14
        static let lg: CGFloat   = 16
        static let xl: CGFloat   = 20
        static let xxl: CGFloat  = 28
        static let xxxl: CGFloat = 34
    }

    /// SF Pro Display for headings/large text.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// SF Pro Text for body and UI labels.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// SF Mono for terminal/code surfaces.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
