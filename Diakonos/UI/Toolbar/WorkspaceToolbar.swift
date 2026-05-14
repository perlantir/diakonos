import SwiftUI
import AppKit

struct WorkspaceToolbar: View {
    var onSettings: () -> Void = {}
    var onFullscreen: () -> Void = {}

    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var layout: WorkspaceLayout

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s3) {
            HStack(spacing: DesignTokens.Spacing.s2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(preferences.accentColor)
                        .frame(width: 18, height: 18)
                    Image(systemName: "cube.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Diakonos")
                    .font(Typography.text(Typography.Size.sm, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
            }

            Spacer()

            // 4-pane / 6-pane toggle. Segmented to make the current mode
            // obvious. New in v1.6. Tapping the inactive segment switches
            // mode; 6 → 4 with non-empty middle slots prompts confirm.
            paneCountSegmented

            HStack(spacing: 2) {
                IconButton(systemImage: "gearshape", action: onSettings)
                IconButton(systemImage: "arrow.up.left.and.arrow.down.right", action: onFullscreen)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s5)
        .padding(.vertical, DesignTokens.Spacing.s3)
        .frame(height: 56)
        .background(
            DesignTokens.Palette.bgApp
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DesignTokens.Palette.borderSoft)
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private var paneCountSegmented: some View {
        HStack(spacing: 2) {
            paneCountButton(count: .four, label: "4")
            paneCountButton(count: .six,  label: "6")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.Palette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DesignTokens.Palette.borderSoft, lineWidth: 1)
                )
        )
        .help("Toggle 4-pane (2×2) or 6-pane (2×3) layout")
    }

    @ViewBuilder
    private func paneCountButton(count: WorkspacePaneCount, label: String) -> some View {
        let isActive = (layout.paneCount == count)
        Button {
            requestPaneCountChange(to: count)
        } label: {
            Text(label)
                .font(Typography.text(Typography.Size.xs, weight: .semibold))
                .foregroundStyle(isActive ? .white : DesignTokens.Palette.textSecondary)
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? preferences.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    /// User clicked the 4 or 6 segment. If switching 6 → 4 will hide
    /// non-empty middle slots, show an NSAlert first.
    private func requestPaneCountChange(to newCount: WorkspacePaneCount) {
        guard newCount != layout.paneCount else { return }
        if newCount == .four {
            let losers = layout.slotsHiddenByFourPaneToggle()
            if !losers.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Switch to 4-pane layout?"
                let names = losers.map { "• \(layout.title(for: $0))" }.joined(separator: "\n")
                alert.informativeText = "These middle-column panes will be hidden but their state will be preserved when you switch back to 6-pane:\n\n\(names)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Switch to 4-pane")
                alert.addButton(withTitle: "Cancel")
                let resp = alert.runModal()
                guard resp == .alertFirstButtonReturn else { return }
            }
        }
        layout.setPaneCount(newCount)
    }
}
