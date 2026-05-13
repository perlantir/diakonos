import Foundation

enum AgentMode: String, CaseIterable, Identifiable, Hashable {
    case manual
    case autonomous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:     return "Manual"
        case .autonomous: return "Autonomous"
        }
    }
}
