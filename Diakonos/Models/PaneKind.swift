import SwiftUI

enum PaneKind: String, Identifiable, CaseIterable, Hashable {
    case terminal
    case claudeCode
    case terminal2
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:   return "Terminal"
        case .claudeCode: return "Claude Code"
        case .terminal2:  return "Terminal 2"
        case .browser:    return "Browser"
        }
    }

    /// v1.1: neutral terminal icons for both terminals (Hermes is gone),
    /// Claude Code keeps purple, Browser keeps blue.
    var iconSystemName: String {
        switch self {
        case .terminal, .terminal2: return "terminal.fill"
        case .claudeCode:           return "sparkles"
        case .browser:              return "globe"
        }
    }

    var accent: Color {
        switch self {
        case .terminal, .terminal2: return DesignTokens.Palette.statusHealthy
        case .claudeCode:           return Color(hex: 0x8B5CF6)
        case .browser:              return DesignTokens.Palette.accentPrimary
        }
    }
}
