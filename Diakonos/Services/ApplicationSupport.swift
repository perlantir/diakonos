import Foundation

/// Locations under `~/Library/Application Support/Diakonos/` for
/// user-owned state that's NOT in UserDefaults: role cards, project
/// session logs, and ad-hoc preferences that need to live as files
/// (so the user can edit them in their text editor).
///
/// The directory tree is lazily ensured on first access. Diakonos
/// runs sandboxed-or-not the same way: NSApplicationSupportDirectory
/// resolves to the right path either way.
enum ApplicationSupport {

    /// `~/Library/Application Support/Diakonos/`
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Diakonos", isDirectory: true)
    }

    /// `<root>/RoleCards/`
    static var roleCards: URL { root.appendingPathComponent("RoleCards", isDirectory: true) }

    /// `<root>/Sessions/`
    static var sessions: URL { root.appendingPathComponent("Sessions", isDirectory: true) }

    /// Ensure all known subdirectories exist. Idempotent. Called from
    /// `DiakonosApp.init` so the first launch creates them.
    static func ensureDirectories() {
        for url in [root, roleCards, sessions] {
            try? FileManager.default.createDirectory(at: url,
                                                    withIntermediateDirectories: true)
        }
    }
}
