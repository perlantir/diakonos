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

                PreferencesSection(
                    title: "Model",
                    subtitle: "Passed to Claude Code as ANTHROPIC_MODEL on pane spawn."
                ) {
                    PreferenceRow(label: "Preferred model") {
                        Picker("", selection: $preferences.preferredModel) {
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 240)
                    }
                }

                PreferencesSection(
                    title: "API keys",
                    subtitle: "Stored in macOS Keychain. Injected as ANTHROPIC_API_KEY / OPENAI_API_KEY / GOOGLE_API_KEY into pane processes on spawn."
                ) {
                    keyRow("Anthropic", binding: $preferences.anthropicKey, key: .anthropic)
                    keyRow("OpenAI",    binding: $preferences.openAIKey,    key: .openai)
                    keyRow("Google AI", binding: $preferences.googleAIKey,  key: .googleAI)
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
