import SwiftUI

struct GeneralSection: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {

                PreferencesSection(title: "Appearance") {
                    PreferenceRow(label: "Theme") {
                        Picker("", selection: Binding(
                            get: { preferences.appearance },
                            set: { preferences.appearance = $0 }
                        )) {
                            ForEach(Preferences.Appearance.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                    PreferenceRow(label: "Accent color",
                                  detail: "Used for buttons, indicators, and highlights.") {
                        AccentChipRow()
                    }
                }

                PreferencesSection(title: "Startup") {
                    PreferenceRow(label: "Auto-start sandbox on launch",
                                  detail: "Boots the cua sandbox when Diakonos opens.") {
                        Toggle("", isOn: $preferences.autoStartSandbox).labelsHidden()
                    }
                    PreferenceRow(label: "Default agent mode") {
                        Picker("", selection: Binding(
                            get: { preferences.agentDefaultMode },
                            set: { preferences.agentDefaultMode = $0 }
                        )) {
                            ForEach(AgentMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                }

                PreferencesSection(title: "Updates",
                                   subtitle: "Diakonos v1 is a developer build. Auto-update arrives in v0.5+.") {
                    PreferenceRow(label: "Diakonos version") {
                        Text("0.1.0").font(Typography.mono(Typography.Size.sm))
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.s5)
        }
    }
}
