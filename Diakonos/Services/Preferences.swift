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
    @AppStorage("preferredModel") var preferredModel: String = "claude-opus-4-7"
    @AppStorage("browserHomeURL") var browserHomeURL: String = "https://duckduckgo.com"
    @AppStorage("claudeCodeFolderPath") var claudeCodeFolderPath: String = ""

    @Published var anthropicKey: String = KeychainStore.read(.anthropic) ?? ""
    @Published var openAIKey: String = KeychainStore.read(.openai) ?? ""
    @Published var googleAIKey: String = KeychainStore.read(.googleAI) ?? ""

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    /// Resolved cwd for the Claude Code pane. Empty preference = $HOME default.
    var claudeCodeResolvedCwd: String {
        let trimmed = claudeCodeFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return NSHomeDirectory() }
        return (trimmed as NSString).expandingTildeInPath
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
