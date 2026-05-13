import Foundation

/// Builds the `environment:` array passed to SwiftTerm's `startProcess` for
/// each pane type. Injects:
///   - API keys from Keychain (ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY)
///   - Claude model selection (ANTHROPIC_MODEL)
///   - Whatever the user's host shell already exposes (PATH, HOME, etc.)
///
/// Returned format: array of `"KEY=VALUE"` strings, the form SwiftTerm
/// passes to `posix_spawn`.
enum EnvironmentBuilder {

    /// Base environment = current process environment, merged with optional
    /// overrides. Returned as `["KEY=VALUE", …]` for SwiftTerm.
    static func env(overrides: [String: String] = [:]) -> [String] {
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in overrides where !v.isEmpty {
            merged[k] = v
        }
        return merged.map { "\($0.key)=\($0.value)" }
    }

    /// Environment for a pane that may want LLM-driven tools (Claude Code,
    /// any terminal where the user might run `claude`/`openai`).
    @MainActor
    static func aiEnv(preferences: Preferences) -> [String] {
        var overrides: [String: String] = [:]

        let anthropic = KeychainStore.read(.anthropic) ?? ""
        let openai    = KeychainStore.read(.openai) ?? ""
        let google    = KeychainStore.read(.googleAI) ?? ""

        if !anthropic.isEmpty { overrides["ANTHROPIC_API_KEY"] = anthropic }
        if !openai.isEmpty    { overrides["OPENAI_API_KEY"] = openai }
        if !google.isEmpty    { overrides["GOOGLE_API_KEY"] = google }

        let model = preferences.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            overrides["ANTHROPIC_MODEL"] = model
        }

        return env(overrides: overrides)
    }
}
