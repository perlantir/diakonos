import SwiftUI

/// Persistent user preferences. Mirrored to UserDefaults so settings survive
/// across launches. v1.3 dropped the Keychain-backed API-key fields and the
/// model picker — agents (Claude Code, Codex) auth via their own CLIs.
@MainActor
final class Preferences: ObservableObject {

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage("accentColorHex") var accentColorHex: String = "#2F6BFF"
    @AppStorage("browserHomeURL") var browserHomeURL: String = "https://duckduckgo.com"
    @AppStorage("claudeCodeFolderPath") var claudeCodeFolderPath: String = ""
    @AppStorage("codexFolderPath") var codexFolderPath: String = ""

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Runtime-resolved accent color. Falls back to the v1.2 hex if the stored
    /// value is malformed.
    var accentColor: Color {
        Color(hexString: accentColorHex) ?? Color(hex: 0x2F6BFF)
    }

    /// Resolved cwd for the Claude Code pane. Empty preference = $HOME default.
    var claudeCodeResolvedCwd: String {
        let trimmed = claudeCodeFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return NSHomeDirectory() }
        return (trimmed as NSString).expandingTildeInPath
    }

    /// Resolved cwd for the Codex pane. Empty preference = $HOME default.
    var codexResolvedCwd: String {
        let trimmed = codexFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return NSHomeDirectory() }
        return (trimmed as NSString).expandingTildeInPath
    }
}

extension Color {
    /// Parse `#RRGGBB` or `RRGGBB` into a Color, nil on malformed input.
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
