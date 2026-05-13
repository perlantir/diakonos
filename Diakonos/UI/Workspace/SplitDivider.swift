import SwiftUI

enum SplitAxis {
    case horizontal   // divider runs horizontally; drag changes Y
    case vertical     // divider runs vertically; drag changes X
}

struct SplitDivider: View {
    let axis: SplitAxis
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @EnvironmentObject private var preferences: Preferences
    @State private var hovering = false
    @State private var dragging = false

    private let thickness: CGFloat = 6

    var body: some View {
        ZStack {
            // Hit-area + tinted active band
            Rectangle()
                .fill(
                    dragging
                        ? preferences.accentColor.opacity(0.35)
                        : hovering
                            ? preferences.accentColor.opacity(0.18)
                            : Color.clear
                )

            // Visible 1px hairline
            Rectangle()
                .fill(
                    dragging
                        ? preferences.accentColor
                        : DesignTokens.Palette.borderSoft
                )
                .frame(
                    width:  axis == .vertical   ? 1 : nil,
                    height: axis == .horizontal ? 1 : nil
                )
        }
        .frame(
            width:  axis == .vertical   ? thickness : nil,
            height: axis == .horizontal ? thickness : nil
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragging = true
                    onDrag(axis == .vertical ? value.translation.width : value.translation.height)
                }
                .onEnded { _ in
                    dragging = false
                    onDragEnded()
                }
        )
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.set(axis == .vertical ? .resizeLeftRight : .resizeUpDown)
            case .ended:
                NSCursor.arrow.set()
            }
        }
        #endif
    }
}

#if os(macOS)
fileprivate extension NSCursor {
    static func set(_ cursor: NSCursor) { cursor.set() }
}
#endif
