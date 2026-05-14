import SwiftUI

/// v1.4 — reads slots from `WorkspaceLayout` directly so reassignments
/// (including Codex) reflect here. v1.3 hard-iterated the old PaneKind enum
/// which never grew a `.codex` case — that left a shipped-broken row.
struct PanesSection: View {
    @ObservedObject var preferences: Preferences
    @StateObject private var layout = WorkspaceLayout()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {

                PreferencesSection(
                    title: "Layout",
                    subtitle: "v1.2+ slots are reassignable from the Close button on each pane. This list shows what each slot is currently set to."
                ) {
                    ForEach(layout.slots) { slot in
                        PreferenceRow(label: layout.title(for: slot),
                                      detail: positionLabel(for: slot.position)) {
                            HStack(spacing: DesignTokens.Spacing.s2) {
                                Image(systemName: slot.kind.iconSystemName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(accent(for: slot.kind))
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                }

                PreferencesSection(title: "Browser pane") {
                    PreferenceRow(label: "Home URL") {
                        TextField("", text: $preferences.browserHomeURL)
                            .textFieldStyle(.plain)
                            .font(Typography.mono(Typography.Size.sm))
                            .padding(.horizontal, DesignTokens.Spacing.s3)
                            .padding(.vertical, 6)
                            .frame(width: 320)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                                    .fill(DesignTokens.Palette.bgElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                                            .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
                                    )
                            )
                    }
                }
            }
            .padding(DesignTokens.Spacing.s5)
        }
    }

    private func positionLabel(for position: PaneSlotPosition) -> String {
        switch position {
        case .topLeft:     return "Top-left"
        case .topMid:      return "Top-mid"
        case .topRight:    return "Top-right"
        case .bottomLeft:  return "Bottom-left"
        case .bottomMid:   return "Bottom-mid"
        case .bottomRight: return "Bottom-right"
        }
    }

    private func accent(for kind: PaneSlotKind) -> Color {
        switch kind {
        case .empty:       return DesignTokens.Palette.textMuted
        case .terminal:    return DesignTokens.Palette.statusHealthy
        case .claudeCode:  return Color(hex: 0x8B5CF6)
        case .codex:       return Color(hex: 0x10A37F)
        case .claudeChat:  return Color(hex: 0xCC785C)
        case .chatgptChat: return Color(hex: 0x10A37F)
        case .browser:     return preferences.accentColor
        }
    }
}
