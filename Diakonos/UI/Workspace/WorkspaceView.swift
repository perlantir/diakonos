import SwiftUI
import AppKit

/// v1.6 — slot-driven workspace grid. Supports two modes:
///   - **4-pane** (default): 2×2 grid (TL/TR/BL/BR). One column divider,
///     one row divider, both draggable.
///   - **6-pane**: 2×3 grid (TL/TM/TR/BL/BM/BR). Two column dividers, one
///     row divider, all draggable.
/// Mode is owned by `WorkspaceLayout` (lifted to `RootView` in v1.6 so the
/// toolbar can toggle it). Slot kinds inside positions are user-controlled
/// and persisted via UserDefaults under the `workspaceLayout.v2` key.
struct WorkspaceView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var layout: WorkspaceLayout

    // 4-pane: one column split.
    @State private var columnSplit: CGFloat = 0.5
    @State private var columnSplitBase: CGFloat = 0.5
    // 6-pane: two column splits at ~1/3 and ~2/3.
    @State private var colSplit1: CGFloat = 1.0 / 3.0
    @State private var colSplit2: CGFloat = 2.0 / 3.0
    @State private var colSplit1Base: CGFloat = 1.0 / 3.0
    @State private var colSplit2Base: CGFloat = 2.0 / 3.0
    // Row split (shared).
    @State private var rowSplit: CGFloat = 0.5
    @State private var rowSplitBase: CGFloat = 0.5

    private let gutter: CGFloat = DesignTokens.Spacing.s3

    var body: some View {
        Group {
            if let maxID = layout.maximizedSlotID, let slot = layout.slot(withID: maxID) {
                paneCell(for: slot)
                    .padding(.horizontal, gutter)
                    .padding(.bottom, gutter)
            } else {
                grid
            }
        }
        .background(DesignTokens.Palette.bgApp)
        .onReceive(NotificationCenter.default.publisher(for: .diakonosFocusSlot)) { note in
            guard let raw = note.object as? String,
                  let pos = PaneSlotPosition(rawValue: raw) else { return }
            PaneFocusRegistry.shared.focus(pos)
        }
        .onReceive(NotificationCenter.default.publisher(for: .diakonosFocusIndex)) { note in
            // 1-based Cmd+1..6 mapped to the current pane-count's reading order.
            guard let idx = note.object as? Int, idx >= 1 else { return }
            let positions = layout.paneCount.positions
            guard idx <= positions.count else { return }
            PaneFocusRegistry.shared.focus(positions[idx - 1])
        }
    }

    @ViewBuilder
    private var grid: some View {
        GeometryReader { geo in
            switch layout.paneCount {
            case .four: fourPaneGrid(geo: geo)
            case .six:  sixPaneGrid(geo: geo)
            }
        }
    }

    // MARK: - 4-pane (2×2)

    @ViewBuilder
    private func fourPaneGrid(geo: GeometryProxy) -> some View {
        let totalW = geo.size.width
        let totalH = geo.size.height
        let leftW  = max(220, totalW * columnSplit         - gutter / 2)
        let rightW = max(220, totalW * (1 - columnSplit)   - gutter / 2)
        let topH   = max(160, totalH * rowSplit            - gutter / 2)
        let botH   = max(160, totalH * (1 - rowSplit)      - gutter / 2)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                slotCell(at: .topLeft, w: leftW, h: topH)
                SplitDivider(axis: .vertical,
                             onDrag: { dx in
                                 columnSplit = clampSplit(columnSplitBase + dx / totalW)
                             },
                             onDragEnded: { columnSplitBase = columnSplit })
                .frame(height: topH)
                slotCell(at: .topRight, w: rightW, h: topH)
            }

            SplitDivider(axis: .horizontal,
                         onDrag: { dy in
                             rowSplit = clampSplit(rowSplitBase + dy / totalH)
                         },
                         onDragEnded: { rowSplitBase = rowSplit })
            .frame(width: totalW)

            HStack(spacing: 0) {
                slotCell(at: .bottomLeft, w: leftW, h: botH)
                SplitDivider(axis: .vertical,
                             onDrag: { dx in
                                 columnSplit = clampSplit(columnSplitBase + dx / totalW)
                             },
                             onDragEnded: { columnSplitBase = columnSplit })
                .frame(height: botH)
                slotCell(at: .bottomRight, w: rightW, h: botH)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.bottom, gutter)
    }

    // MARK: - 6-pane (2×3)

    @ViewBuilder
    private func sixPaneGrid(geo: GeometryProxy) -> some View {
        let totalW = geo.size.width
        let totalH = geo.size.height
        // Two column boundaries split the width into three columns.
        let leftW  = max(180, totalW * colSplit1                        - gutter / 2)
        let midW   = max(180, totalW * (colSplit2 - colSplit1)          - gutter)
        let rightW = max(180, totalW * (1 - colSplit2)                  - gutter / 2)
        let topH   = max(160, totalH * rowSplit                         - gutter / 2)
        let botH   = max(160, totalH * (1 - rowSplit)                   - gutter / 2)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                slotCell(at: .topLeft, w: leftW, h: topH)
                SplitDivider(axis: .vertical,
                             onDrag: { dx in
                                 colSplit1 = clamp6Split1(colSplit1Base + dx / totalW)
                             },
                             onDragEnded: { colSplit1Base = colSplit1 })
                .frame(height: topH)
                slotCell(at: .topMid, w: midW, h: topH)
                SplitDivider(axis: .vertical,
                             onDrag: { dx in
                                 colSplit2 = clamp6Split2(colSplit2Base + dx / totalW)
                             },
                             onDragEnded: { colSplit2Base = colSplit2 })
                .frame(height: topH)
                slotCell(at: .topRight, w: rightW, h: topH)
            }

            SplitDivider(axis: .horizontal,
                         onDrag: { dy in
                             rowSplit = clampSplit(rowSplitBase + dy / totalH)
                         },
                         onDragEnded: { rowSplitBase = rowSplit })
            .frame(width: totalW)

            HStack(spacing: 0) {
                slotCell(at: .bottomLeft, w: leftW, h: botH)
                SplitDivider(axis: .vertical,
                             onDrag: { dx in
                                 colSplit1 = clamp6Split1(colSplit1Base + dx / totalW)
                             },
                             onDragEnded: { colSplit1Base = colSplit1 })
                .frame(height: botH)
                slotCell(at: .bottomMid, w: midW, h: botH)
                SplitDivider(axis: .vertical,
                             onDrag: { dx in
                                 colSplit2 = clamp6Split2(colSplit2Base + dx / totalW)
                             },
                             onDragEnded: { colSplit2Base = colSplit2 })
                .frame(height: botH)
                slotCell(at: .bottomRight, w: rightW, h: botH)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.bottom, gutter)
    }

    // MARK: - Cells

    @ViewBuilder
    private func slotCell(at pos: PaneSlotPosition, w: CGFloat, h: CGFloat) -> some View {
        if let slot = layout.slot(at: pos) {
            paneCell(for: slot)
                .frame(width: w,
                       height: slot.viewState == .minimized ? 36 : h,
                       alignment: .top)
                .frame(width: w, height: h, alignment: .top)
        }
    }

    @ViewBuilder
    private func paneCell(for slot: PaneSlot) -> some View {
        let title = layout.title(for: slot)
        let icon = slot.kind.iconSystemName
        let accent = accentFor(slot: slot)
        let isMax = (layout.maximizedSlotID == slot.id)

        PaneView(
            title: title,
            iconSystemName: icon,
            accent: accent,
            state: .running,
            viewState: slot.viewState,
            isMaximized: isMax,
            onMinimize: {
                if slot.viewState == .minimized {
                    layout.restore(slot.id)
                } else {
                    layout.minimize(slot.id)
                }
            },
            onMaximizeToggle: { layout.toggleMaximize(slot.id) },
            onClose: { layout.close(slot.id) },
            menuContent: { menuItems(for: slot) },
            actionChip: { actionChip(for: slot) }
        ) {
            paneBody(for: slot)
        }
    }

    @ViewBuilder
    private func paneBody(for slot: PaneSlot) -> some View {
        switch slot.kind {
        case .empty:
            EmptyPaneBody(slotID: slot.id, layout: layout)
        case .terminal:
            TerminalPaneView(
                spawnIdentity: "term:\(slot.id):\(layout.respawnTag(slot.id))",
                focusPosition: slot.position
            )
        case .claudeCode:
            ClaudeCodePaneView(
                preferences: preferences,
                focusPosition: slot.position,
                respawnTag: layout.respawnTag(slot.id)
            )
        case .codex:
            CodexPaneView(
                preferences: preferences,
                focusPosition: slot.position,
                respawnTag: layout.respawnTag(slot.id)
            )
        case .claudeChat:
            WebAppPaneView(kind: .claudeChat, focusPosition: slot.position)
        case .chatgptChat:
            WebAppPaneView(kind: .chatgptChat, focusPosition: slot.position)
        case .browser:
            BrowserPaneView(focusPosition: slot.position)
        }
    }

    @ViewBuilder
    private func actionChip(for slot: PaneSlot) -> some View {
        switch slot.kind {
        case .claudeCode:
            HStack(spacing: 6) {
                PaneModeChip(slot: slot, layout: layout)
                ClaudeCodeFolderChip(preferences: preferences)
            }
        case .codex:
            HStack(spacing: 6) {
                PaneModeChip(slot: slot, layout: layout)
                CodexFolderChip(preferences: preferences)
            }
        case .claudeChat, .chatgptChat:
            // Order: AUTO chip + Stop (loud, leftmost), then mode toggle,
            // then postback toggle, then routing badge. Routing badge
            // stays rightmost so it's visible against the rest.
            HStack(spacing: 6) {
                AutoStatusChip(slot: slot, layout: layout)
                PaneModeChip(slot: slot, layout: layout)
                if slot.resolvedMode == .coordinator {
                    PostbackChip(slot: slot, layout: layout)
                }
                RoutingBadge(slot: slot)
            }
        case .browser:
            PaneModeChip(slot: slot, layout: layout)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func menuItems(for slot: PaneSlot) -> some View {
        switch slot.kind {
        case .empty:
            EmptyView()
        case .terminal:
            Button("Reset shell") {
                layout.bumpRespawn(slot.id)
            }
        case .claudeCode:
            Button("Restart Claude Code") {
                layout.bumpRespawn(slot.id)
            }
            Button("Change project folder…") {
                pickClaudeFolder()
            }
        case .codex:
            Button("Restart Codex") {
                layout.bumpRespawn(slot.id)
            }
            Button("Change project folder…") {
                pickCodexFolder()
            }
            Button("Sign in to Codex…") {
                layout.bumpRespawn(slot.id)
            }
        case .claudeChat:
            Button("Sign in to Claude…") { }
        case .chatgptChat:
            Button("Sign in to ChatGPT…") { }
        case .browser:
            Button("Reload") {
                NotificationCenter.default.post(name: .diakonosBrowserReload, object: slot.position.rawValue)
            }
            Button("Open in floating window") {
                NotificationCenter.default.post(name: .diakonosBrowserPopout, object: slot.position.rawValue)
            }
            Divider()
            Button("Reset sandbox", role: .destructive) {
                NotificationCenter.default.post(name: .diakonosBrowserResetSandbox, object: slot.position.rawValue)
            }
        }
    }

    private func accentFor(slot: PaneSlot) -> Color {
        switch slot.kind {
        case .empty:       return DesignTokens.Palette.textMuted
        case .terminal:    return DesignTokens.Palette.statusHealthy
        case .claudeCode:  return Color(hex: 0x8B5CF6)
        case .codex:       return Color(hex: 0x10A37F)
        case .claudeChat:  return Color(hex: 0xCC785C)
        case .chatgptChat: return Color(hex: 0x10A37F)
        case .browser:     return preferences.accentColor
        }
    }

    private func pickCodexFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose project folder for Codex"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: preferences.codexResolvedCwd, isDirectory: true)
        if let win = NSApp.keyWindow {
            panel.beginSheetModal(for: win) { resp in
                if resp == .OK, let u = panel.url {
                    preferences.codexFolderPath = u.path
                }
            }
        } else if panel.runModal() == .OK, let u = panel.url {
            preferences.codexFolderPath = u.path
        }
    }

    private func pickClaudeFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose project folder for Claude Code"
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: preferences.claudeCodeResolvedCwd, isDirectory: true)
        if let win = NSApp.keyWindow {
            panel.beginSheetModal(for: win) { resp in
                if resp == .OK, let u = panel.url {
                    preferences.claudeCodeFolderPath = u.path
                }
            }
        } else if panel.runModal() == .OK, let u = panel.url {
            preferences.claudeCodeFolderPath = u.path
        }
    }

    private func clampSplit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), 0.85)
    }
    /// 6-pane left column boundary: 0.15..min(0.50, colSplit2-0.10).
    private func clamp6Split1(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.15), min(0.50, colSplit2 - 0.10))
    }
    /// 6-pane right column boundary: max(0.50, colSplit1+0.10)..0.85.
    private func clamp6Split2(_ value: CGFloat) -> CGFloat {
        max(min(value, 0.85), max(0.50, colSplit1 + 0.10))
    }
}

extension Notification.Name {
    static let diakonosBrowserReload = Notification.Name("DiakonosBrowserReload")
    static let diakonosBrowserPopout = Notification.Name("DiakonosBrowserPopout")
    static let diakonosBrowserResetSandbox = Notification.Name("DiakonosBrowserResetSandbox")
    static let diakonosTerminalSendBytes = Notification.Name("DiakonosTerminalSendBytes")
    /// Posted by `DiakonosApp`'s Cmd+1..6 commands. `object` is a 1-based
    /// Int. `WorkspaceView` resolves the index against `layout.paneCount`'s
    /// reading order to a `PaneSlotPosition`, then asks the focus registry.
    static let diakonosFocusIndex = Notification.Name("DiakonosFocusIndex")
}
