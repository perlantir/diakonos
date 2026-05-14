import Foundation

/// Append-only JSONL event log, one file per conversation, under
/// `~/Library/Application Support/Diakonos/Sessions/<conversation-id>.jsonl`.
///
/// Format: one JSON object per line. Each line is a self-contained event.
/// `Diagnostics` reads via tail-from-disk; nothing in Diakonos rewrites
/// or compacts these files in v1.7 — they grow forever (one chat session's
/// worth of events fits comfortably in MB-sized files anyway).
///
/// Why JSONL and not full-JSON-array? Append-only writes mean each
/// transition is a single fsync, never a read-modify-write race.
@MainActor
final class SessionEventLog {

    struct Event: Codable {
        let timestamp: Date
        let kind: Kind
        let routeID: UUID
        let conversationID: String
        let state: RouteState
        let detail: String

        enum Kind: String, Codable {
            case routeDetected   = "route_detected"
            case routeSent       = "route_sent"
            case routeRunning    = "route_running"
            case routeReply      = "route_reply"
            case routePosted     = "route_posted"
            case routeReviewed   = "route_reviewed"
            case routeClosed    = "route_closed"
            case info           = "info"
            case warning        = "warning"
            case error          = "error"
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Append one event for the given conversation. Creates the file
    /// on first write. All file I/O is best-effort: failure here is
    /// logged to NSLog but doesn't propagate (we don't want a bad log
    /// to break a route).
    static func append(_ event: Event) {
        ApplicationSupport.ensureDirectories()
        let url = fileURL(forConversation: event.conversationID)
        guard var data = try? encoder.encode(event) else { return }
        data.append(0x0A) // newline
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Read the last `tail` events across ALL sessions, newest first.
    /// Used by the Diagnostics tab.
    static func recentEvents(tail: Int = 500) -> [Event] {
        ApplicationSupport.ensureDirectories()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: ApplicationSupport.sessions, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        // Sort by modification time desc, take a handful of newest files.
        let sorted = contents.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        var events: [Event] = []
        for url in sorted.prefix(20) where url.pathExtension == "jsonl" {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in raw.split(separator: "\n") {
                if let data = line.data(using: .utf8),
                   let ev = try? decoder.decode(Event.self, from: data) {
                    events.append(ev)
                    if events.count >= tail { break }
                }
            }
            if events.count >= tail { break }
        }
        return events
    }

    private static func fileURL(forConversation conversationID: String) -> URL {
        // Sanitize: conversation IDs from claude.ai/chatgpt.com are
        // UUIDs, so this is mostly defensive against future shapes.
        let safe = conversationID.replacingOccurrences(of: "/", with: "_")
                                 .replacingOccurrences(of: "..", with: "_")
        return ApplicationSupport.sessions.appendingPathComponent("\(safe).jsonl")
    }
}
