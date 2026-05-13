import SwiftUI

struct AgentSection: View {
    @ObservedObject var preferences: Preferences

    private let models = [
        "claude-opus-4-7",
        "claude-sonnet-4-6",
        "claude-haiku-4-5-20251001",
        "gpt-4o",
        "gemini-2.0-flash"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {

                PreferencesSection(title: "Model") {
                    PreferenceRow(label: "Preferred model") {
                        Picker("", selection: $preferences.preferredModel) {
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 240)
                    }
                    PreferenceRow(label: "Temperature",
                                  detail: "Higher = more exploratory; lower = more deterministic.") {
                        HStack(spacing: DesignTokens.Spacing.s3) {
                            Slider(value: $preferences.agentTemperature, in: 0...1, step: 0.05)
                                .frame(width: 220)
                            Text(String(format: "%.2f", preferences.agentTemperature))
                                .font(Typography.mono(Typography.Size.sm))
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                PreferencesSection(title: "API keys",
                                   subtitle: "Stored in macOS Keychain. Never logged or transmitted by Diakonos.") {
                    keyRow("Anthropic",  binding: $preferences.anthropicKey, key: .anthropic)
                    keyRow("OpenAI",     binding: $preferences.openAIKey,    key: .openai)
                    keyRow("Hermes",     binding: $preferences.hermesKey,    key: .hermes)
                    keyRow("Google AI",  binding: $preferences.googleAIKey,  key: .googleAI)
                }
            }
            .padding(DesignTokens.Spacing.s5)
        }
    }

    @ViewBuilder
    private func keyRow(_ label: String, binding: Binding<String>, key: KeychainStore.Key) -> some View {
        PreferenceRow(label: label) {
            SecretField(placeholder: "sk-…", value: binding)
                .onSubmit {
                    preferences.persistAPIKey(key, value: binding.wrappedValue)
                }
        }
    }
}
