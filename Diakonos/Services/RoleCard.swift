import Foundation

/// A single role card: markdown prose telling the AI on a given surface
/// what role it plays in Diakonos's routing protocol. Stored on disk as
/// `<id>@<semver>.md` under `~/Library/Application Support/Diakonos/RoleCards/`.
///
/// `id` identifies the role+surface combination (e.g.
/// `coordinator.claude-web`, `implementer.claude-code`). `version` is a
/// semver string the store auto-bumps on each save. The body is plain
/// markdown — the route envelope composer copies it verbatim into the
/// prompt context.
struct RoleCard: Equatable, Hashable {
    let id: String
    let version: Semver
    let body: String

    /// Filename on disk: `coordinator.claude-web@1.4.2.md`.
    var filename: String { "\(id)@\(version.string).md" }
}

/// Minimal semver: major.minor.patch (no prerelease/build metadata).
/// Auto-bumped on each Settings save.
struct Semver: Comparable, Hashable, Codable {
    let major: Int
    let minor: Int
    let patch: Int

    var string: String { "\(major).\(minor).\(patch)" }

    static let initial = Semver(major: 1, minor: 0, patch: 0)

    /// Parse `1.4.2` etc. Returns nil if not three integer parts.
    static func parse(_ s: String) -> Semver? {
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Semver(major: parts[0], minor: parts[1], patch: parts[2])
    }

    /// Increment the patch component. Major / minor stay put. Used by
    /// `RoleCardStore.save` so each user edit creates a new file
    /// (older versions stay around — active sessions pinned to them
    /// keep working).
    func bumpingPatch() -> Semver {
        Semver(major: major, minor: minor, patch: patch + 1)
    }

    static func < (lhs: Semver, rhs: Semver) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Built-in role card identities. The Settings UI surfaces these by
/// `id`; new ones can be added by dropping markdown files into the
/// RoleCards directory.
enum BuiltInRoleCardID: String, CaseIterable {
    case coordinatorClaudeWeb   = "coordinator.claude-web"
    case coordinatorChatGPTWeb  = "coordinator.chatgpt-web"
    case implementerClaudeCode  = "implementer.claude-code"
    case implementerCodex       = "implementer.codex"
    case browserDriver          = "browser-driver"

    /// Display name shown in the Settings sidebar.
    var displayName: String {
        switch self {
        case .coordinatorClaudeWeb:   return "Coordinator (Claude web)"
        case .coordinatorChatGPTWeb:  return "Coordinator (ChatGPT web)"
        case .implementerClaudeCode:  return "Implementer (Claude Code)"
        case .implementerCodex:       return "Implementer (Codex)"
        case .browserDriver:          return "Browser driver"
        }
    }
}
