import SwiftUI

enum PaneKind: String, Identifiable, CaseIterable, Hashable {
    case terminal
    case claudeCode
    case hermesAgent
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal:    return "Terminal"
        case .claudeCode:  return "Claude Code"
        case .hermesAgent: return "Agent Chat"
        case .browser:     return "Browser"
        }
    }

    /// Per screen 09 "Pane type icons" — Terminal (green), Claude Code (purple),
    /// Hermes (orange), Browser (blue).
    var iconSystemName: String {
        switch self {
        case .terminal:    return "terminal.fill"
        case .claudeCode:  return "sparkles"
        case .hermesAgent: return "bubble.left.and.bubble.right.fill"
        case .browser:     return "globe"
        }
    }

    var accent: Color {
        switch self {
        case .terminal:    return DesignTokens.Palette.statusHealthy
        case .claudeCode:  return Color(hex: 0x8B5CF6)
        case .hermesAgent: return DesignTokens.Palette.hermesOrange
        case .browser:     return DesignTokens.Palette.accentPrimary
        }
    }
}
