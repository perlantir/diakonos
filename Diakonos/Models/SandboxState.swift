import SwiftUI

enum SandboxState: String, Equatable, Hashable {
    case initializing
    case running           // "Healthy"
    case warning
    case error
    case stopped

    var label: String {
        switch self {
        case .initializing: return "Initializing"
        case .running:      return "Healthy"
        case .warning:      return "Degraded"
        case .error:        return "Error"
        case .stopped:      return "Stopped"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .initializing: return DesignTokens.Palette.statusWarning
        case .running:      return DesignTokens.Palette.statusHealthy
        case .warning:      return DesignTokens.Palette.statusWarning
        case .error:        return DesignTokens.Palette.statusError
        case .stopped:      return DesignTokens.Palette.statusStopped
        }
    }
}
