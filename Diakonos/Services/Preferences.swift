import SwiftUI

/// Persistent user preferences. Mirrored to UserDefaults so settings survive
/// across launches. API keys are stored in Keychain, not UserDefaults (see
/// `KeychainStore`).
@MainActor
final class Preferences: ObservableObject {

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage("autoStartSandbox") var autoStartSandbox: Bool = true
    @AppStorage("autoUpdateSandbox") var autoUpdateSandbox: Bool = false
    @AppStorage("sandboxCPU") var sandboxCPULimit: Double = 4
    @AppStorage("sandboxMemoryGB") var sandboxMemoryGB: Double = 4
    @AppStorage("preferredModel") var preferredModel: String = "claude-opus-4-7"
    @AppStorage("agentTemperature") var agentTemperature: Double = 0.7
    @AppStorage("agentDefaultMode") var agentDefaultModeRaw: String = AgentMode.manual.rawValue
    @AppStorage("browserHomeURL") var browserHomeURL: String = "https://www.apple.com"
    @AppStorage("paneAssignments") var paneAssignmentsRaw: String = "terminal,claudeCode,hermesAgent,browser"

    @Published var anthropicKey: String = KeychainStore.read(.anthropic) ?? ""
    @Published var openAIKey: String = KeychainStore.read(.openai) ?? ""
    @Published var hermesKey: String = KeychainStore.read(.hermes) ?? ""
    @Published var googleAIKey: String = KeychainStore.read(.googleAI) ?? ""

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var agentDefaultMode: AgentMode {
        get { AgentMode(rawValue: agentDefaultModeRaw) ?? .manual }
        set { agentDefaultModeRaw = newValue.rawValue }
    }

    func persistAPIKey(_ key: KeychainStore.Key, value: String) {
        if value.isEmpty {
            KeychainStore.delete(key)
        } else {
            KeychainStore.write(key, value: value)
        }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
