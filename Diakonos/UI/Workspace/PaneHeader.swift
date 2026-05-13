import SwiftUI

/// Header bar at the top of every pane. v1.2 wiring:
///   - left: pane icon + title + state dot + optional `actionChip`
///   - right: 3-dot menu (kind-specific items), minimize, maximize/restore, close
struct PaneHeader<ActionChip: View, MenuContent: View>: View {
    let title: String
    let iconSystemName: String
    let accent: Color
    let state: SandboxState
    let viewState: PaneSlotViewState
    let isMaximized: Bool

    var onMinimize: () -> Void = {}
    var onMaximizeToggle: () -> Void = {}
    var onClose: () -> Void = {}
    @ViewBuilder var menuContent: () -> MenuContent
    @ViewBuilder var actionChip: () -> ActionChip

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Image(systemName: iconSystemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 18, height: 18)

            Text(title)
                .font(Typography.text(Typography.Size.sm, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)
                .lineLimit(1)

            Circle()
                .fill(state.indicatorColor)
                .frame(width: 6, height: 6)

            actionChip()

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                IconButton(systemImage: viewState == .minimized ? "plus" : "minus",
                           size: 22, iconSize: 11,
                           action: onMinimize)

                IconButton(systemImage: isMaximized
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right",
                           size: 22, iconSize: 10,
                           action: onMaximizeToggle)

                IconButton(systemImage: "xmark", size: 22, iconSize: 10,
                           action: onClose)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s3)
        .padding(.vertical, DesignTokens.Spacing.s2)
        .frame(height: 36)
        .background(
            DesignTokens.Palette.bgElevated
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DesignTokens.Palette.borderSoft)
                        .frame(height: 1)
                }
        )
    }
}

extension PaneHeader where ActionChip == EmptyView {
    init(title: String,
         iconSystemName: String,
         accent: Color,
         state: SandboxState,
         viewState: PaneSlotViewState,
         isMaximized: Bool,
         onMinimize: @escaping () -> Void = {},
         onMaximizeToggle: @escaping () -> Void = {},
         onClose: @escaping () -> Void = {},
         @ViewBuilder menuContent: @escaping () -> MenuContent) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.accent = accent
        self.state = state
        self.viewState = viewState
        self.isMaximized = isMaximized
        self.onMinimize = onMinimize
        self.onMaximizeToggle = onMaximizeToggle
        self.onClose = onClose
        self.menuContent = menuContent
        self.actionChip = { EmptyView() }
    }
}

extension PaneHeader where MenuContent == EmptyView, ActionChip == EmptyView {
    init(title: String,
         iconSystemName: String,
         accent: Color,
         state: SandboxState,
         viewState: PaneSlotViewState,
         isMaximized: Bool,
         onMinimize: @escaping () -> Void = {},
         onMaximizeToggle: @escaping () -> Void = {},
         onClose: @escaping () -> Void = {}) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.accent = accent
        self.state = state
        self.viewState = viewState
        self.isMaximized = isMaximized
        self.onMinimize = onMinimize
        self.onMaximizeToggle = onMaximizeToggle
        self.onClose = onClose
        self.menuContent = { EmptyView() }
        self.actionChip = { EmptyView() }
    }
}
