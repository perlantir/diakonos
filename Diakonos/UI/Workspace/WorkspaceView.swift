import SwiftUI

/// 2x2 pane grid with two draggable dividers (one vertical between columns, one horizontal between rows).
/// Phase 2: top-left wires SwiftTerm + docker exec into the cua sandbox; other three remain placeholders.
struct WorkspaceView: View {
    @EnvironmentObject private var sandbox: CUASandboxManager

    // Static pane assignments per D7.
    private let topLeft: PaneKind  = .terminal
    private let topRight: PaneKind = .claudeCode
    private let botLeft: PaneKind  = .hermesAgent
    private let botRight: PaneKind = .browser

    @State private var columnSplit: CGFloat = 0.5
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
                    PaneView(kind: topLeft, state: sandbox.state) {
                        SandboxedPaneBody(
                            kind: topLeft,
                            state: sandbox.state,
                            containerName: sandbox.containerName
                        ) { container in
                            TerminalPaneView(containerName: container, commandInContainer: "/bin/bash")
                        }
                    }
                    .frame(width: leftW, height: topH)

                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: topH)

                    PaneView(kind: topRight, state: sandbox.state) {
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
                    PaneView(kind: botLeft, state: sandbox.state) {
                        InitializingPaneBody(kind: botLeft)
                    }
                    .frame(width: leftW, height: botH)

                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: botH)

                    PaneView(kind: botRight, state: sandbox.state) {
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
