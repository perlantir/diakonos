import SwiftUI

/// 2x2 pane grid with two draggable dividers (one vertical between columns, one horizontal between rows).
/// Each pane is `PaneView` wrapping `InitializingPaneBody` for Phase 1.
struct WorkspaceView: View {
    // Static pane assignments per D7.
    private let topLeft: PaneKind  = .terminal
    private let topRight: PaneKind = .claudeCode
    private let botLeft: PaneKind  = .hermesAgent
    private let botRight: PaneKind = .browser

    // Pane states (will be driven by CUASandboxManager in Phase 2+).
    @State private var topLeftState: SandboxState  = .initializing
    @State private var topRightState: SandboxState = .initializing
    @State private var botLeftState: SandboxState  = .initializing
    @State private var botRightState: SandboxState = .initializing

    /// Column-split as a fraction of total width [0.15, 0.85].
    @State private var columnSplit: CGFloat = 0.5
    /// Row-split as a fraction of total height [0.15, 0.85].
    @State private var rowSplit: CGFloat = 0.5

    @State private var columnSplitBase: CGFloat = 0.5
    @State private var rowSplitBase: CGFloat = 0.5

    private let gutter: CGFloat = DesignTokens.Spacing.s3

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let totalH = geo.size.height

            let leftW  = max(220, totalW * columnSplit  - gutter / 2)
            let rightW = max(220, totalW * (1 - columnSplit) - gutter / 2)
            let topH   = max(160, totalH * rowSplit     - gutter / 2)
            let botH   = max(160, totalH * (1 - rowSplit) - gutter / 2)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    PaneView(kind: topLeft, state: topLeftState) {
                        InitializingPaneBody(kind: topLeft)
                    }
                    .frame(width: leftW, height: topH)

                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: topH)

                    PaneView(kind: topRight, state: topRightState) {
                        InitializingPaneBody(kind: topRight)
                    }
                    .frame(width: rightW, height: topH)
                }

                SplitDivider(axis: .horizontal,
                             onDrag: { dy in
                                 rowSplit = clampSplit(rowSplitBase + dy / totalH)
                             },
                             onDragEnded: { rowSplitBase = rowSplit })
                .frame(width: totalW)

                HStack(spacing: 0) {
                    PaneView(kind: botLeft, state: botLeftState) {
                        InitializingPaneBody(kind: botLeft)
                    }
                    .frame(width: leftW, height: botH)

                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: botH)

                    PaneView(kind: botRight, state: botRightState) {
                        InitializingPaneBody(kind: botRight)
                    }
                    .frame(width: rightW, height: botH)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, gutter)
        }
        .background(DesignTokens.Palette.bgApp)
    }

    private func clampSplit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), 0.85)
    }
}
