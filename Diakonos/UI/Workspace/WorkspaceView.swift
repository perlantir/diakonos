import SwiftUI
import AppKit

/// v1.2 — slot-driven 2x2 pane grid.
///   - Slots TL/TR/BL/BR are fixed; kinds inside them are user-controlled and
///     persisted via `WorkspaceLayout` in UserDefaults.
///   - One slot can be "maximized" → renders full-bleed, others hidden.
///   - Minimized slots collapse to header height.
struct WorkspaceView: View {
    @EnvironmentObject private var preferences: Preferences
    @StateObject private var layout = WorkspaceLayout()

    @State private var columnSplit: CGFloat = 0.5
    @State private var rowSplit: CGFloat = 0.5
    @State private var columnSplitBase: CGFloat = 0.5
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
    }

    private var grid: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let totalH = geo.size.height

            let leftW  = max(220, totalW * columnSplit  - gutter / 2)
            let rightW = max(220, totalW * (1 - columnSplit) - gutter / 2)
            let topH   = max(160, totalH * rowSplit     - gutter / 2)
            let botH   = max(160, totalH * (1 - rowSplit) - gutter / 2)

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
    }

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
            ClaudeCodeFolderChip(preferences: preferences)
        case .codex:
            CodexFolderChip(preferences: preferences)
        case .claudeChat, .chatgptChat:
            RoutingBadge(slot: slot)
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
                // codex login flow runs inside the pane on next respawn —
                // simplest path is to send the user to the codex login command
                // via the existing PTY. For v1.3 we just bump respawn and let
                // codex itself surface the OAuth flow if not signed in.
                layout.bumpRespawn(slot.id)
            }
        case .claudeChat:
            Button("Sign in to Claude…") {
                // navigates to https://claude.ai which prompts login
            }
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
        case .claudeChat:  return Color(hex: 0xCC785C)   // Anthropic warm tan
        case .chatgptChat: return Color(hex: 0x10A37F)   // OpenAI green
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
}

extension Notification.Name {
    static let diakonosBrowserReload = Notification.Name("DiakonosBrowserReload")
    static let diakonosBrowserPopout = Notification.Name("DiakonosBrowserPopout")
    static let diakonosBrowserResetSandbox = Notification.Name("DiakonosBrowserResetSandbox")
    static let diakonosTerminalSendBytes = Notification.Name("DiakonosTerminalSendBytes")
}
