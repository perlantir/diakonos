import SwiftUI

struct SandboxSection: View {
    @ObservedObject var preferences: Preferences
    @EnvironmentObject var sandbox: CUASandboxManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {

                PreferencesSection(title: "Runtime",
                                   subtitle: "Diakonos talks to cua via `npx cuabot --serve` on port 7842.") {
                    PreferenceRow(label: "Status",
                                  detail: sandbox.lastStatusMessage) {
                        StatusIndicator(state: sandbox.state)
                    }
                    PreferenceRow(label: "Container") {
                        Text(sandbox.containerName ?? "—")
                            .font(Typography.mono(Typography.Size.sm))
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                    }
                }

                PreferencesSection(title: "Resources",
                                   subtitle: "Set in the Docker daemon; shown here for reference.") {
                    PreferenceRow(label: "CPU limit (cores)") {
                        HStack(spacing: DesignTokens.Spacing.s3) {
                            Slider(value: $preferences.sandboxCPULimit, in: 1...16, step: 1)
                                .frame(width: 220)
                            Text("\(Int(preferences.sandboxCPULimit))")
                                .font(Typography.mono(Typography.Size.sm))
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                    PreferenceRow(label: "Memory (GB)") {
                        HStack(spacing: DesignTokens.Spacing.s3) {
                            Slider(value: $preferences.sandboxMemoryGB, in: 2...32, step: 1)
                                .frame(width: 220)
                            Text("\(Int(preferences.sandboxMemoryGB)) GB")
                                .font(Typography.mono(Typography.Size.sm))
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                PreferencesSection(title: "Behavior") {
                    PreferenceRow(label: "Auto-update sandbox image",
                                  detail: "Pulls the latest trycua/cuabot image on launch.") {
                        Toggle("", isOn: $preferences.autoUpdateSandbox).labelsHidden()
                    }
                }
            }
            .padding(DesignTokens.Spacing.s5)
        }
    }
}
