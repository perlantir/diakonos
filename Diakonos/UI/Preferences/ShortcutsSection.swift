import SwiftUI

struct ShortcutsSection: View {
    /// Static list of v1 shortcuts. (Customization arrives in v0.2.)
    private struct Shortcut: Identifiable {
        let id = UUID()
        let action: String
        let keys: String
    }

    private let shortcuts: [Shortcut] = [
        .init(action: "Open Preferences",     keys: "⌘ ,"),
        .init(action: "Toggle full-screen",   keys: "⌃ ⌘ F"),
        .init(action: "Focus Terminal pane",  keys: "⌘ 1"),
        .init(action: "Focus Claude pane",    keys: "⌘ 2"),
        .init(action: "Focus Hermes pane",    keys: "⌘ 3"),
        .init(action: "Focus Browser pane",   keys: "⌘ 4"),
        .init(action: "Reset sandbox",        keys: "⌃ ⌘ R"),
        .init(action: "Quit Diakonos",        keys: "⌘ Q")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {
                PreferencesSection(title: "Keyboard shortcuts",
                                   subtitle: "v1 ships with fixed shortcuts. Custom bindings land in v0.2.") {
                    ForEach(shortcuts) { sc in
                        PreferenceRow(label: sc.action) {
                            Text(sc.keys)
                                .font(Typography.mono(Typography.Size.sm, weight: .semibold))
                                .foregroundStyle(DesignTokens.Palette.textPrimary)
                                .padding(.horizontal, DesignTokens.Spacing.s2)
                                .padding(.vertical, 4)
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
            }
            .padding(DesignTokens.Spacing.s5)
        }
    }
}
