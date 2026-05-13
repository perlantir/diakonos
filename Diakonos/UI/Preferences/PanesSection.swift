import SwiftUI

struct PanesSection: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {

                PreferencesSection(title: "Layout",
                                   subtitle: "v1 ships with the four hardcoded panes shown below. Custom layouts arrive in v0.2.") {
                    ForEach(PaneKind.allCases) { kind in
                        PreferenceRow(label: kind.title,
                                      detail: positionLabel(for: kind)) {
                            HStack(spacing: DesignTokens.Spacing.s2) {
                                Image(systemName: kind.iconSystemName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(kind.accent)
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

    private func positionLabel(for kind: PaneKind) -> String {
        switch kind {
        case .terminal:    return "Top-left"
        case .claudeCode:  return "Top-right"
        case .hermesAgent: return "Bottom-left"
        case .browser:     return "Bottom-right"
        }
    }
}
