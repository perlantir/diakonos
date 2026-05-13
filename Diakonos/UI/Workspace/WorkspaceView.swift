import SwiftUI

/// 2x2 pane grid with two draggable dividers. Phase 3: all four panes live.
struct WorkspaceView: View {
    @EnvironmentObject private var sandbox: CUASandboxManager

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
                    pane(topLeft, w: leftW, h: topH)

                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: topH)

                    pane(topRight, w: rightW, h: topH)
                }

                SplitDivider(axis: .horizontal,
                             onDrag: { dy in
                                 rowSplit = clampSplit(rowSplitBase + dy / totalH)
                             },
                             onDragEnded: { rowSplitBase = rowSplit })
                .frame(width: totalW)

                HStack(spacing: 0) {
                    pane(botLeft, w: leftW, h: botH)

                    SplitDivider(axis: .vertical,
                                 onDrag: { dx in
                                     columnSplit = clampSplit(columnSplitBase + dx / totalW)
                                 },
                                 onDragEnded: { columnSplitBase = columnSplit })
                    .frame(height: botH)

                    pane(botRight, w: rightW, h: botH)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, gutter)
        }
        .background(DesignTokens.Palette.bgApp)
    }

    @ViewBuilder
    private func pane(_ kind: PaneKind, w: CGFloat, h: CGFloat) -> some View {
        PaneView(kind: kind, state: state(for: kind)) {
            paneBody(for: kind)
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func paneBody(for kind: PaneKind) -> some View {
        switch kind {
        case .terminal:
            SandboxedPaneBody(kind: kind, state: sandbox.state, containerName: sandbox.containerName) { container in
                TerminalPaneView(containerName: container)
            }
        case .claudeCode:
            SandboxedPaneBody(kind: kind, state: sandbox.state, containerName: sandbox.containerName) { container in
                ClaudeCodePaneView(containerName: container)
            }
        case .hermesAgent:
            SandboxedPaneBody(kind: kind, state: sandbox.state, containerName: sandbox.containerName) { container in
                HermesAgentPaneView(containerName: container)
            }
        case .browser:
            // Browser pane bypasses the sandbox entirely (D6).
            BrowserPaneView()
        }
    }

    private func state(for kind: PaneKind) -> SandboxState {
        // Browser pane is independent of the cua sandbox per D6.
        if kind == .browser { return .running }
        return sandbox.state
    }

    private func clampSplit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), 0.85)
    }
}
