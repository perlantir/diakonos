import Foundation
import Combine

/// Disk-backed store for role cards. Cards live under
/// `~/Library/Application Support/Diakonos/RoleCards/<id>@<semver>.md`.
/// On first launch the store copies any missing built-in cards from the
/// app bundle so the directory is seeded with defaults.
///
/// Editing in the Settings tab calls `save(id:, body:)` which auto-bumps
/// the patch version and writes a new file. Older versions are NOT
/// deleted — active sessions hold pinned references to specific
/// versions and need them to keep working.
@MainActor
final class RoleCardStore: ObservableObject {

    static let shared = RoleCardStore()

    /// Latest version per id (the one new sessions pin to).
    @Published private(set) var latest: [String: RoleCard] = [:]

    private var cancellable: AnyCancellable?

    init() {
        ApplicationSupport.ensureDirectories()
        seedFromBundleIfNeeded()
        reload()
    }

    // MARK: - Public API

    /// All cards on disk, newest version first per id.
    var allCards: [RoleCard] {
        let everything = scanDisk()
        return everything.sorted { $0.version > $1.version }
    }

    /// Look up a specific version. Used by sessions to load the exact
    /// version they were started with.
    func card(id: String, version: Semver) -> RoleCard? {
        scanDisk().first { $0.id == id && $0.version == version }
    }

    /// Latest version available for `id`, or nil if no file matches.
    func latestVersion(forId id: String) -> RoleCard? { latest[id] }

    /// Save edited body, bumping patch. Returns the new card.
    @discardableResult
    func save(id: String, body: String) -> RoleCard? {
        let nextVersion = (latest[id]?.version ?? Semver.initial).bumpingPatch()
        let card = RoleCard(id: id, version: nextVersion, body: body)
        let url = ApplicationSupport.roleCards.appendingPathComponent(card.filename)
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[Diakonos] RoleCardStore: failed to save \(card.filename): \(error)")
            return nil
        }
        reload()
        return card
    }

    // MARK: - Internals

    private func reload() {
        var newest: [String: RoleCard] = [:]
        for card in scanDisk() {
            if let existing = newest[card.id] {
                if card.version > existing.version { newest[card.id] = card }
            } else {
                newest[card.id] = card
            }
        }
        latest = newest
    }

    /// List every `<id>@<semver>.md` under the RoleCards dir.
    private func scanDisk() -> [RoleCard] {
        let dir = ApplicationSupport.roleCards
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                           includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [RoleCard] = []
        for url in contents where url.pathExtension == "md" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let atIdx = name.lastIndex(of: "@") else { continue }
            let id = String(name[..<atIdx])
            let verStr = String(name[name.index(after: atIdx)...])
            guard let ver = Semver.parse(verStr) else { continue }
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append(RoleCard(id: id, version: ver, body: body))
        }
        return out
    }

    /// Copy bundled `Resources/RoleCards/<id>@1.0.0.md` into the support
    /// dir for any id that isn't already present. Idempotent.
    private func seedFromBundleIfNeeded() {
        guard let bundleDir = Bundle.main.url(forResource: "RoleCards", withExtension: nil) else {
            return
        }
        guard let bundled = try? FileManager.default.contentsOfDirectory(at: bundleDir,
                                                                          includingPropertiesForKeys: nil) else {
            return
        }
        for src in bundled where src.pathExtension == "md" {
            let name = src.deletingPathExtension().lastPathComponent
            guard let atIdx = name.lastIndex(of: "@") else { continue }
            let id = String(name[..<atIdx])
            // Skip if this id already has any version on disk — user may
            // have edited it; we don't want to clobber.
            let existing = (try? FileManager.default.contentsOfDirectory(at: ApplicationSupport.roleCards,
                                                                          includingPropertiesForKeys: nil)) ?? []
            let alreadyHaveId = existing.contains { $0.lastPathComponent.hasPrefix("\(id)@") }
            if alreadyHaveId { continue }
            let dst = ApplicationSupport.roleCards.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.copyItem(at: src, to: dst)
        }
    }
}
