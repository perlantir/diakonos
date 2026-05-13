import SwiftUI

/// 2x2 pane grid with two draggable dividers.
/// v1.1: three panes are native (Terminal, Claude Code, Terminal 2). Only
/// the Browser pane reaches into a sandbox, and its state lives in its own
/// BrowserSandbox manager — no global sandbox env-object.
struct WorkspaceView: View {
    @EnvironmentObject private var preferences: Preferences

    private let topLeft: PaneKind  = .terminal
    private let topRight: PaneKind = .claudeCode
    private let botLeft: PaneKind  = .terminal2
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
                    paneCell(topLeft, w: leftW, h: topH)
                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: topH)
                    paneCell(topRight, w: rightW, h: topH)
                }

                SplitDivider(axis: .horizontal,
                             onDrag: { dy in
                                 rowSplit = clampSplit(rowSplitBase + dy / totalH)
                             },
                             onDragEnded: { rowSplitBase = rowSplit })
                .frame(width: totalW)

                HStack(spacing: 0) {
                    paneCell(botLeft, w: leftW, h: botH)
                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: botH)
                    paneCell(botRight, w: rightW, h: botH)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, gutter)
        }
        .background(DesignTokens.Palette.bgApp)
    }

    @ViewBuilder
    private func paneCell(_ kind: PaneKind, w: CGFloat, h: CGFloat) -> some View {
        Group {
            switch kind {
            case .terminal, .terminal2:
                PaneView(kind: kind, state: .running) {
                    TerminalPaneView()
                }
            case .claudeCode:
                PaneView(kind: kind, state: .running,
                         actionChip: { ClaudeCodeFolderChip(preferences: preferences) }) {
                    ClaudeCodePaneView(preferences: preferences)
                }
            case .browser:
                PaneView(kind: kind, state: .running) {
                    BrowserPaneView()
                }
            }
        }
        .frame(width: w, height: h)
    }

    private func clampSplit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), 0.85)
    }
}
